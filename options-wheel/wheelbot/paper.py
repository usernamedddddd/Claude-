"""Paper trading: real Robinhood market data, simulated account and fills."""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import date, datetime
from pathlib import Path
from typing import Callable
from zoneinfo import ZoneInfo

from .broker import Broker
from .config import ExecutionConfig
from .models import AccountSnapshot, OptionQuote, OrderResult, ShortOption, StockHolding

log = logging.getLogger(__name__)
NY = ZoneInfo("America/New_York")


class PaperBroker:
    """Fills every limit order immediately at its limit price (the mid), minus fees.

    Expired options settle on the first cycle after expiration day, against the last
    stock price seen on expiration day: puts below the strike are assigned, and calls
    above the strike are called away.
    """

    def __init__(self, market: Broker, cfg: ExecutionConfig, clock: Callable[[], float] = time.time):
        self.market = market
        self.fee = cfg.paper_fee_per_contract
        self.path = Path(cfg.paper_state_file)
        self.clock = clock
        self.cash = cfg.paper_starting_cash
        self.stocks: dict[str, StockHolding] = {}
        self.shorts: list[ShortOption] = []
        self.last_price: dict[str, tuple[str, float]] = {}   # symbol -> (date, price)
        self.events: list[dict] = []
        if self.path.exists():
            data = json.loads(self.path.read_text())
            self.cash = data["cash"]
            self.stocks = {s: StockHolding(**h) for s, h in data["stocks"].items()}
            self.shorts = [ShortOption.from_dict(o) for o in data["shorts"]]
            self.last_price = {s: tuple(v) for s, v in data.get("last_price", {}).items()}
            self.events = data.get("events", [])

    def save(self) -> None:
        data = {
            "cash": self.cash,
            "stocks": {s: vars(h) for s, h in self.stocks.items()},
            "shorts": [o.to_dict() for o in self.shorts],
            "last_price": self.last_price,
            "events": self.events,
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self.path)

    def _today(self) -> date:
        return datetime.fromtimestamp(self.clock(), NY).date()

    def _event(self, kind: str, o: ShortOption, price: float, note: str = "") -> None:
        self.events.append({"at": self.clock(), "event": kind, "contract": o.key, "quantity": o.quantity,
                            "stock_price": price, "note": note})
        log.info("PAPER %s %s x%d (stock $%.2f) %s", kind, o.key, o.quantity, price, note)

    # --- market data passes through, recording prices for settlement -----------
    def underlying_price(self, symbol: str) -> float:
        price = self.market.underlying_price(symbol)
        self.last_price[symbol] = (self._today().isoformat(), price)
        return price

    def expirations(self, symbol):
        return self.market.expirations(symbol)

    def option_quotes(self, symbol, expiration, option_type, spot):
        return self.market.option_quotes(symbol, expiration, option_type, spot)

    def option_quote(self, pos):
        # Record the stock price too, so a contract held to expiry settles on that day's price.
        self.underlying_price(pos.symbol)
        return self.market.option_quote(pos)

    def next_earnings(self, symbol, today):
        return self.market.next_earnings(symbol, today)

    def market_hours(self):
        return self.market.market_hours()

    # --- simulated account ---------------------------------------------------
    @property
    def collateral(self) -> float:
        return sum(o.strike * 100 * o.quantity for o in self.shorts if o.option_type == "put")

    def settle_expired(self, today: date) -> None:
        for o in [o for o in self.shorts if o.expiration < today]:
            seen = self.last_price.get(o.symbol)
            price = seen[1] if seen and seen[0] == o.expiration.isoformat() else self.market.underlying_price(o.symbol)
            shares = 100 * o.quantity
            if o.option_type == "put" and price < o.strike:
                h = self.stocks.get(o.symbol) or StockHolding(o.symbol, 0, 0)
                h.avg_cost = (h.quantity * h.avg_cost + shares * o.strike) / (h.quantity + shares)
                h.quantity += shares
                self.stocks[o.symbol] = h
                self.cash -= shares * o.strike
                self._event("ASSIGNED", o, price, f"bought {shares} shares at {o.strike:g}")
            elif o.option_type == "call" and price > o.strike:
                h = self.stocks[o.symbol]
                h.quantity -= shares
                self.cash += shares * o.strike
                if h.quantity <= 0:
                    del self.stocks[o.symbol]
                self._event("CALLED_AWAY", o, price,
                            f"sold {shares} shares at {o.strike:g} (cost {h.avg_cost:.2f})")
            else:
                self._event("EXPIRED", o, price, "worthless")
            self.shorts.remove(o)
        self.save()

    def account(self) -> AccountSnapshot:
        self.settle_expired(self._today())
        return AccountSnapshot(
            cash=self.cash - self.collateral,
            stocks={s: StockHolding(h.symbol, h.quantity, h.avg_cost) for s, h in self.stocks.items()},
            short_options=[ShortOption.from_dict(o.to_dict()) for o in self.shorts],
        )

    def _find(self, symbol: str, option_type: str, strike: float, expiration: date) -> ShortOption | None:
        return next((o for o in self.shorts if (o.symbol, o.option_type, o.strike, o.expiration)
                     == (symbol, option_type, strike, expiration)), None)

    def sell_to_open(self, q: OptionQuote, quantity: int, price: float) -> OrderResult:
        if q.option_type == "put" and self.cash - self.collateral < q.strike * 100 * quantity:
            return OrderResult("paper", "rejected", 0, price)
        if q.option_type == "call":
            h = self.stocks.get(q.symbol)
            covered = (h.quantity if h else 0) // 100 - sum(o.quantity for o in self.shorts
                                                             if o.symbol == q.symbol and o.option_type == "call")
            if covered < quantity:
                return OrderResult("paper", "rejected", 0, price)  # never sell naked calls
        self.cash += price * 100 * quantity - self.fee * quantity
        existing = self._find(q.symbol, q.option_type, q.strike, q.expiration)
        if existing:
            total = existing.quantity + quantity
            existing.avg_credit = (existing.avg_credit * existing.quantity + price * quantity) / total
            existing.quantity = total
        else:
            self.shorts.append(ShortOption(q.symbol, q.option_type, q.strike, q.expiration, quantity, price,
                                           q.instrument_id))
        self.save()
        return OrderResult("paper", "filled", quantity, price)

    def buy_to_close(self, pos: ShortOption, q: OptionQuote, quantity: int, price: float) -> OrderResult:
        held = self._find(pos.symbol, pos.option_type, pos.strike, pos.expiration)
        if not held:
            return OrderResult("paper", "rejected", 0, price)
        quantity = min(quantity, held.quantity)
        self.cash -= price * 100 * quantity + self.fee * quantity
        held.quantity -= quantity
        if held.quantity == 0:
            self.shorts.remove(held)
        self.save()
        return OrderResult("paper", "filled", quantity, price)
