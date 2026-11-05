"""Robinhood access through the unofficial `robin_stocks` library.

`RobinhoodBroker` is both the market-data source (also used in paper mode) and the
live order executor. Robinhood has no official options API: endpoints can change
without notice, so every response is parsed defensively.
"""

from __future__ import annotations

import logging
import time
from datetime import date, datetime
from typing import Any, Callable, Protocol

from .models import AccountSnapshot, OptionQuote, OrderResult, ShortOption, StockHolding

log = logging.getLogger(__name__)

DONE_STATES = {"filled", "cancelled", "canceled", "rejected", "failed", "expired"}


class Broker(Protocol):
    def underlying_price(self, symbol: str) -> float: ...
    def expirations(self, symbol: str) -> list[date]: ...
    def option_quotes(self, symbol: str, expiration: date, option_type: str, spot: float) -> list[OptionQuote]: ...
    def option_quote(self, pos: ShortOption) -> OptionQuote | None: ...
    def next_earnings(self, symbol: str, today: date) -> date | None: ...
    def market_hours(self) -> tuple[datetime, datetime] | None: ...
    def account(self) -> AccountSnapshot: ...
    def sell_to_open(self, q: OptionQuote, quantity: int, price: float) -> OrderResult: ...
    def buy_to_close(self, pos: ShortOption, q: OptionQuote, quantity: int, price: float) -> OrderResult: ...


def login(rh: Any, username: str | None, password: str | None, mfa_secret: str | None = None) -> None:
    """Log in, reusing robin_stocks' cached session when it is still valid."""
    mfa_code = None
    if mfa_secret:
        import pyotp
        mfa_code = pyotp.TOTP(mfa_secret).now()
    rh.login(username, password, mfa_code=mfa_code, store_session=True)


def _f(value: Any, default: float = 0.0) -> float:
    try:
        return float(value) if value not in (None, "") else default
    except (TypeError, ValueError):
        return default


def _iso(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def parse_quote(inst: dict, md: dict) -> OptionQuote:
    ticks = inst.get("min_ticks") or {}
    delta = md.get("delta")
    iv = md.get("implied_volatility")
    return OptionQuote(
        symbol=inst["chain_symbol"], option_type=inst["type"], strike=_f(inst["strike_price"]),
        expiration=date.fromisoformat(inst["expiration_date"]),
        bid=_f(md.get("bid_price")), ask=_f(md.get("ask_price")),
        delta=_f(delta) if delta not in (None, "") else None,
        implied_volatility=_f(iv) if iv not in (None, "") else None,
        open_interest=int(_f(md.get("open_interest"))), volume=int(_f(md.get("volume"))),
        instrument_id=inst["id"],
        tick_below=_f(ticks.get("below_tick"), 0.01), tick_above=_f(ticks.get("above_tick"), 0.05),
        tick_cutoff=_f(ticks.get("cutoff_price"), 3.0),
    )


class RobinhoodBroker:
    # Only fetch market data for strikes in this band around the stock price; far strikes are never picked.
    STRIKE_BAND = {"put": (0.60, 1.05), "call": (0.95, 1.60)}
    MARKETDATA_BATCH = 40

    def __init__(self, rh: Any, account_number: str | None = None, order_timeout_s: float = 60,
                 sleep: Callable[[float], None] = time.sleep):
        self.rh = rh
        self.account_number = account_number
        self.order_timeout_s = order_timeout_s
        self.sleep = sleep
        self._instruments: dict[str, dict] = {}

    # --- market data -------------------------------------------------------
    def underlying_price(self, symbol: str) -> float:
        prices = self.rh.stocks.get_latest_price(symbol, includeExtendedHours=False)
        price = _f(prices[0] if prices else None)
        if price <= 0:
            raise RuntimeError(f"no price for {symbol}")
        return price

    def expirations(self, symbol: str) -> list[date]:
        chain = self.rh.options.get_chains(symbol) or {}
        return sorted(date.fromisoformat(d) for d in chain.get("expiration_dates", []))

    def _market_data(self, instruments: list[dict]) -> dict[str, dict]:
        """Market data keyed by instrument id, fetched in batches."""
        out: dict[str, dict] = {}
        url = self.rh.urls.marketdata_options_url()
        for i in range(0, len(instruments), self.MARKETDATA_BATCH):
            chunk = instruments[i:i + self.MARKETDATA_BATCH]
            by_url = {inst["url"]: inst["id"] for inst in chunk}
            rows = self.rh.helper.request_get(url, "results", {"instruments": ",".join(by_url)}) or []
            for md in rows:
                if not md:
                    continue
                inst_id = md.get("instrument_id") or by_url.get(md.get("instrument", ""))
                if inst_id:
                    out[inst_id] = md
        return out

    def option_quotes(self, symbol: str, expiration: date, option_type: str, spot: float) -> list[OptionQuote]:
        lo, hi = self.STRIKE_BAND[option_type]
        tradable = self.rh.options.find_tradable_options(symbol, expiration.isoformat(), optionType=option_type) or []
        insts = [i for i in tradable
                 if i.get("expiration_date") == expiration.isoformat() and i.get("tradability", "tradable") == "tradable"
                 and lo * spot <= _f(i.get("strike_price")) <= hi * spot]
        for inst in insts:
            self._instruments[inst["id"]] = inst
        mds = self._market_data(insts)
        return [parse_quote(inst, mds[inst["id"]]) for inst in insts if inst["id"] in mds]

    def _instrument(self, instrument_id: str) -> dict:
        if instrument_id not in self._instruments:
            inst = self.rh.options.get_option_instrument_data_by_id(instrument_id)
            if not inst:
                raise RuntimeError(f"option instrument {instrument_id} not found")
            self._instruments[instrument_id] = inst
        return self._instruments[instrument_id]

    def option_quote(self, pos: ShortOption) -> OptionQuote | None:
        md = self.rh.options.get_option_market_data_by_id(pos.instrument_id)
        if isinstance(md, list):
            md = md[0] if md else None
        if not md:
            return None
        return parse_quote(self._instrument(pos.instrument_id), md)

    def next_earnings(self, symbol: str, today: date) -> date | None:
        upcoming = []
        for row in self.rh.stocks.get_earnings(symbol) or []:
            report = (row or {}).get("report") or {}
            if report.get("date"):
                d = date.fromisoformat(report["date"])
                if d >= today:
                    upcoming.append(d)
        return min(upcoming) if upcoming else None

    def market_hours(self) -> tuple[datetime, datetime] | None:
        """Today's regular session (UTC-aware), or None if the market is closed today."""
        hours = self.rh.markets.get_market_today_hours("XNYS") or {}
        if not hours.get("is_open") or not hours.get("opens_at"):
            return None
        return _iso(hours["opens_at"]), _iso(hours["closes_at"])

    # --- account -----------------------------------------------------------
    def account(self) -> AccountSnapshot:
        profile = self.rh.profiles.load_account_profile(account_number=self.account_number) or {}
        # The smaller of the two never counts margin or unsettled funds as collateral.
        cash = min(_f(profile.get("buying_power")), _f(profile.get("cash_available_for_withdrawal")))

        stocks = {}
        for p in self.rh.account.get_open_stock_positions(account_number=self.account_number) or []:
            qty = _f(p.get("quantity"))
            if qty <= 0:
                continue
            symbol = self.rh.stocks.get_symbol_by_url(p["instrument"])
            stocks[symbol] = StockHolding(symbol, qty, _f(p.get("average_buy_price")))

        shorts = []
        for p in self.rh.options.get_open_option_positions(account_number=self.account_number) or []:
            qty = int(_f(p.get("quantity")))
            if qty <= 0:
                continue
            if p.get("type") != "short":
                log.debug("ignoring long option position %s", p.get("chain_symbol"))
                continue
            inst = self._instrument(p["option_id"])
            shorts.append(ShortOption(
                symbol=p["chain_symbol"], option_type=inst["type"], strike=_f(inst["strike_price"]),
                expiration=date.fromisoformat(inst["expiration_date"]), quantity=qty,
                avg_credit=abs(_f(p.get("average_price"))) / 100,  # Robinhood reports per contract
                instrument_id=p["option_id"],
            ))
        return AccountSnapshot(cash=cash, stocks=stocks, short_options=shorts)

    # --- orders ------------------------------------------------------------
    def _wait(self, order_id: str, price: float) -> OrderResult:
        deadline = time.monotonic() + self.order_timeout_s
        info = self.rh.orders.get_option_order_info(order_id) or {}
        while info.get("state") not in DONE_STATES and time.monotonic() < deadline:
            self.sleep(2)
            info = self.rh.orders.get_option_order_info(order_id) or {}
        if info.get("state") not in DONE_STATES:
            log.info("order %s not filled after %.0fs; cancelling", order_id, self.order_timeout_s)
            self.rh.orders.cancel_option_order(order_id)
            self.sleep(2)
            info = self.rh.orders.get_option_order_info(order_id) or info
        return OrderResult(order_id, info.get("state", "unknown"),
                           int(_f(info.get("processed_quantity"))), _f(info.get("price"), price))

    def _submit(self, resp: Any, price: float) -> OrderResult:
        if not isinstance(resp, dict) or not resp.get("id"):
            raise RuntimeError(f"order rejected by Robinhood: {resp}")
        return self._wait(resp["id"], price)

    def sell_to_open(self, q: OptionQuote, quantity: int, price: float) -> OrderResult:
        resp = self.rh.orders.order_sell_option_limit(
            "open", "credit", price, q.symbol, quantity, q.expiration.isoformat(), q.strike,
            optionType=q.option_type, account_number=self.account_number, timeInForce="gfd")
        return self._submit(resp, price)

    def buy_to_close(self, pos: ShortOption, q: OptionQuote, quantity: int, price: float) -> OrderResult:
        resp = self.rh.orders.order_buy_option_limit(
            "close", "debit", price, pos.symbol, quantity, pos.expiration.isoformat(), pos.strike,
            optionType=pos.option_type, account_number=self.account_number, timeInForce="gfd")
        return self._submit(resp, price)
