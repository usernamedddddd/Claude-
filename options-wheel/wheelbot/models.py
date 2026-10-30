"""Plain data types shared by the strategy, brokers and bot."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date


@dataclass
class OptionQuote:
    symbol: str
    option_type: str                     # "put" or "call"
    strike: float
    expiration: date
    bid: float
    ask: float
    delta: float | None = None
    implied_volatility: float | None = None
    open_interest: int = 0
    volume: int = 0
    instrument_id: str = ""
    tick_below: float = 0.01             # price increment under tick_cutoff
    tick_above: float = 0.05
    tick_cutoff: float = 3.00

    @property
    def mid(self) -> float:
        return (self.bid + self.ask) / 2

    @property
    def spread_pct(self) -> float:
        return (self.ask - self.bid) / self.mid * 100 if self.mid > 0 else float("inf")


@dataclass
class ShortOption:
    """An open short option position (we sold it and still owe it)."""
    symbol: str
    option_type: str
    strike: float
    expiration: date
    quantity: int                        # contracts, positive
    avg_credit: float                    # per share received when sold
    instrument_id: str = ""

    @property
    def key(self) -> str:
        return f"{self.symbol} {self.expiration.isoformat()} {self.strike:g}{self.option_type[0].upper()}"

    def to_dict(self) -> dict:
        d = asdict(self)
        d["expiration"] = self.expiration.isoformat()
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "ShortOption":
        return cls(**{**d, "expiration": date.fromisoformat(d["expiration"])})


@dataclass
class StockHolding:
    symbol: str
    quantity: float
    avg_cost: float


@dataclass
class AccountSnapshot:
    cash: float                          # free cash, after cash already reserved as put collateral
    stocks: dict[str, StockHolding] = field(default_factory=dict)
    short_options: list[ShortOption] = field(default_factory=list)

    def shares(self, symbol: str) -> float:
        h = self.stocks.get(symbol)
        return h.quantity if h else 0.0

    def shorts(self, symbol: str, option_type: str | None = None) -> list[ShortOption]:
        return [o for o in self.short_options
                if o.symbol == symbol and (option_type is None or o.option_type == option_type)]

    def committed(self, symbol: str | None = None) -> float:
        """Cash tied up in put collateral plus stock cost basis."""
        puts = sum(o.strike * 100 * o.quantity for o in self.short_options
                   if o.option_type == "put" and (symbol is None or o.symbol == symbol))
        stock = sum(h.quantity * h.avg_cost for s, h in self.stocks.items() if symbol is None or s == symbol)
        return puts + stock


@dataclass
class OrderResult:
    order_id: str
    state: str                           # "filled", "cancelled", "rejected", ...
    filled_quantity: int
    price: float                         # per share

    @property
    def filled(self) -> bool:
        return self.filled_quantity > 0


@dataclass
class LedgerEntry:
    at: float                            # unix seconds
    action: str                          # STO (sell to open), BTC (buy to close), GONE (expired or assigned)
    symbol: str
    option_type: str
    strike: float
    expiration: str
    quantity: int
    price: float                         # per share
    reason: str = ""

    @property
    def cash_flow(self) -> float:
        sign = {"STO": 1, "BTC": -1}.get(self.action, 0)
        return sign * self.price * 100 * self.quantity

    def to_dict(self) -> dict:
        return asdict(self)
