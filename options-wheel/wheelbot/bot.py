"""The wheel: sell cash-secured puts; if assigned, sell covered calls; repeat."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .broker import Broker
from .config import Config, ContractRules, RiskConfig
from .ledger import Ledger
from .models import AccountSnapshot, LedgerEntry, OptionQuote, ShortOption
from .strategy import (annualized_yield_pct, buy_price, close_signal, contract_rejection, dte,
                       pick_contract, pick_expiration, sell_price)

log = logging.getLogger(__name__)
NY = ZoneInfo("America/New_York")


def put_rejection(acct: AccountSnapshot, risk: RiskConfig, symbol: str, collateral: float) -> str | None:
    """None if selling a put needing `collateral` dollars stays within the risk limits."""
    if acct.committed(symbol) + collateral > risk.max_per_ticker_usd + 1e-9:
        return f"per-ticker limit (${acct.committed(symbol):,.0f} + ${collateral:,.0f} > ${risk.max_per_ticker_usd:,.0f})"
    if acct.committed() + collateral > risk.max_total_collateral_usd + 1e-9:
        return f"total limit (${acct.committed():,.0f} + ${collateral:,.0f} > ${risk.max_total_collateral_usd:,.0f})"
    if acct.cash - collateral < risk.min_cash_reserve_usd:
        return f"not enough cash (${acct.cash:,.0f} free, ${risk.min_cash_reserve_usd:,.0f} reserve)"
    return None


@dataclass
class Idea:
    """What the bot would sell for one ticker right now (used by `scan`)."""
    symbol: str
    option_type: str
    quote: OptionQuote | None
    note: str


class Bot:
    def __init__(self, cfg: Config, broker: Broker, ledger: Ledger):
        self.cfg = cfg
        self.broker = broker
        self.ledger = ledger

    # --- contract search -----------------------------------------------------
    def find_contract(self, symbol: str, option_type: str, today: date, spot: float,
                      min_strike: float | None = None) -> tuple[OptionQuote | None, str]:
        rules: ContractRules = self.cfg.puts if option_type == "put" else self.cfg.calls
        exp = pick_expiration(self.broker.expirations(symbol), today, rules)
        if exp is None:
            return None, f"no expiration within {rules.min_dte}-{rules.max_dte} DTE"
        if self.cfg.risk.avoid_earnings:
            earnings = self.broker.next_earnings(symbol, today)
            if earnings and earnings <= exp:
                return None, f"earnings on {earnings} before {exp} expiry"
        quotes = self.broker.option_quotes(symbol, exp, option_type, spot)
        q = pick_contract(quotes, today, rules, min_strike)
        if q is None:
            reasons: dict[str, int] = {}
            for x in quotes:
                label = contract_rejection(x, today, rules, min_strike).split(" ")[0]
                reasons[label] = reasons.get(label, 0) + 1
            return None, f"no {option_type} on {exp} passes the filters ({reasons or 'no quotes'})"
        return q, f"{exp} ({dte(exp, today)} DTE)"

    def ideas(self, today: date) -> list[Idea]:
        out = []
        acct = self.broker.account()
        for sym in self.cfg.tickers:
            try:
                spot = self.broker.underlying_price(sym)
                q, note = self.find_contract(sym, "put", today, spot)
                out.append(Idea(sym, "put", q, note))
                h = acct.stocks.get(sym)
                if h and h.quantity >= 100:
                    floor = h.avg_cost * (1 + self.cfg.risk.min_call_strike_above_cost_pct / 100)
                    q, note = self.find_contract(sym, "call", today, spot, floor)
                    out.append(Idea(sym, "call", q, note))
            except Exception as e:
                out.append(Idea(sym, "put", None, f"error: {e}"))
        return out

    # --- bookkeeping ---------------------------------------------------------
    def _watched(self, acct: AccountSnapshot) -> list[ShortOption]:
        return [o for o in acct.short_options if o.symbol in self.cfg.tickers]

    def reconcile(self, acct: AccountSnapshot, today: date, now_s: float) -> None:
        """Log short options that disappeared since last cycle without the bot closing them."""
        current = {o.key: o for o in self._watched(acct)}
        for key, o in self.ledger.known_shorts.items():
            if key not in current:
                why = "expired or assigned" if o.expiration <= today else "closed outside the bot (or early assignment)"
                self.ledger.entries.append(LedgerEntry(now_s, "GONE", o.symbol, o.option_type, o.strike,
                                                       o.expiration.isoformat(), o.quantity, 0.0, why))
                log.info("%s x%d is gone: %s", key, o.quantity, why)
        self.ledger.known_shorts = current
        self.ledger.save()

    # --- managing open shorts ------------------------------------------------
    def manage(self, acct: AccountSnapshot, today: date, now_s: float) -> bool:
        changed = False
        for pos in self._watched(acct):
            q = self.broker.option_quote(pos)
            if q is None or q.ask <= 0:
                log.warning("no quote for %s; holding", pos.key)
                continue
            reason = close_signal(pos, q.mid, today, self.cfg.manage)
            if reason is None:
                log.debug("hold %s: mark %.2f vs credit %.2f", pos.key, q.mid, pos.avg_credit)
                continue
            price = buy_price(q)
            res = self.broker.buy_to_close(pos, q, pos.quantity, price)
            if not res.filled:
                log.info("buy-to-close %s at %.2f not filled (%s); retrying next cycle", pos.key, price, res.state)
                continue
            changed = True
            self.ledger.entries.append(LedgerEntry(now_s, "BTC", pos.symbol, pos.option_type, pos.strike,
                                                   pos.expiration.isoformat(), res.filled_quantity, res.price, reason))
            known = self.ledger.known_shorts.get(pos.key)
            if known:
                known.quantity -= res.filled_quantity
                if known.quantity <= 0:
                    del self.ledger.known_shorts[pos.key]
            self.ledger.save()
            log.info("BTC %s x%d @ %.2f (sold @ %.2f): %s", pos.key, res.filled_quantity, res.price,
                     pos.avg_credit, reason)
        return changed

    # --- opening new shorts --------------------------------------------------
    def _sell(self, acct: AccountSnapshot, q: OptionQuote, quantity: int, today: date, now_s: float) -> bool:
        price = sell_price(q)
        res = self.broker.sell_to_open(q, quantity, price)
        if not res.filled:
            log.info("sell %s %s %g at %.2f not filled (%s)", q.symbol, q.expiration, q.strike, price, res.state)
            return False
        pos = ShortOption(q.symbol, q.option_type, q.strike, q.expiration, res.filled_quantity, res.price,
                          q.instrument_id)
        acct.short_options.append(pos)
        if q.option_type == "put":
            acct.cash -= q.strike * 100 * res.filled_quantity
        known = self.ledger.known_shorts.get(pos.key)
        if known:
            known.quantity += pos.quantity
        else:
            self.ledger.known_shorts[pos.key] = pos
        self.ledger.record(LedgerEntry(now_s, "STO", q.symbol, q.option_type, q.strike, q.expiration.isoformat(),
                                       res.filled_quantity, res.price,
                                       f"delta {abs(q.delta or 0):.2f}, "
                                       f"{annualized_yield_pct(res.price, q.strike, dte(q.expiration, today)):.0f}%/yr"))
        log.info("STO %s x%d @ %.2f (delta %.2f, %d DTE)", pos.key, pos.quantity, res.price,
                 abs(q.delta or 0), dte(q.expiration, today))
        return True

    def open_for(self, sym: str, acct: AccountSnapshot, today: date, now_s: float) -> None:
        risk = self.cfg.risk
        spot = self.broker.underlying_price(sym)

        # Covered calls on every free 100 shares.
        h = acct.stocks.get(sym)
        free_lots = int(acct.shares(sym) // 100) - sum(o.quantity for o in acct.shorts(sym, "call"))
        if self.cfg.calls.enabled and h and free_lots > 0:
            floor = h.avg_cost * (1 + risk.min_call_strike_above_cost_pct / 100)
            q, note = self.find_contract(sym, "call", today, spot, floor)
            if q:
                self._sell(acct, q, min(free_lots, risk.contracts_per_trade), today, now_s)
            else:
                log.info("%s: no covered call: %s", sym, note)

        # One cash-secured put at a time per ticker, within the collateral limits.
        if self.cfg.puts.enabled and not acct.shorts(sym, "put"):
            qty = risk.contracts_per_trade
            # Cheap pre-check before fetching the chain: no put we'd pick costs less than this.
            blocked = put_rejection(acct, risk, sym, spot * 0.6 * 100 * qty)
            if blocked:
                log.info("%s: no put: %s", sym, blocked)
                return
            q, note = self.find_contract(sym, "put", today, spot)
            if q is None:
                log.info("%s: no put: %s", sym, note)
                return
            blocked = put_rejection(acct, risk, sym, q.strike * 100 * qty)
            if blocked:
                log.info("%s: no put at %g: %s", sym, q.strike, blocked)
                return
            self._sell(acct, q, qty, today, now_s)

    # --- loop ------------------------------------------------------------------
    def window_rejection(self, now: datetime) -> str | None:
        hours = self.broker.market_hours()
        if hours is None:
            return "market closed today"
        opens, closes = hours
        start = opens + timedelta(minutes=self.cfg.market.skip_first_minutes)
        end = closes - timedelta(minutes=self.cfg.market.skip_last_minutes)
        if not start <= now <= end:
            return f"outside trading window {start.astimezone(NY):%H:%M}-{end.astimezone(NY):%H:%M} ET"
        return None

    def cycle(self, now: datetime | None = None) -> str | None:
        """One pass. Returns why it skipped trading, or None if it ran."""
        now = now or datetime.now(timezone.utc)
        skipped = self.window_rejection(now)
        if skipped:
            return skipped
        today, now_s = now.astimezone(NY).date(), now.timestamp()
        acct = self.broker.account()
        self.reconcile(acct, today, now_s)
        if self.manage(acct, today, now_s):
            acct = self.broker.account()
        for sym in self.cfg.tickers:
            try:
                self.open_for(sym, acct, today, now_s)
            except Exception:
                log.exception("%s: failed; skipping this cycle", sym)
        return None

    def run_forever(self) -> None:
        log.info("wheel bot started in %s mode on %s", self.cfg.execution.mode.upper(), ", ".join(self.cfg.tickers))
        last_skip = None
        while True:
            try:
                skip = self.cycle()
                if skip != last_skip and skip:
                    log.info("waiting: %s", skip)
                last_skip = skip
            except Exception:
                log.exception("cycle failed; retrying next poll")
            time.sleep(self.cfg.poll_seconds)
