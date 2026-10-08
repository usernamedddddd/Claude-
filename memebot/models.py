"""Plain data types shared across the bot."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class PairSnapshot:
    """One DEX pair as reported by DexScreener at a moment in time."""

    chain: str
    dex: str
    pair_address: str
    mint: str
    symbol: str
    name: str
    quote_symbol: str
    price_usd: float
    liquidity_usd: float
    market_cap_usd: float
    volume_h1_usd: float
    volume_h24_usd: float
    buys_m5: int
    sells_m5: int
    price_change_m5_pct: float
    price_change_h1_pct: float
    created_at_ms: int | None
    url: str = ""

    @property
    def txns_m5(self) -> int:
        return self.buys_m5 + self.sells_m5

    @property
    def buy_sell_ratio_m5(self) -> float:
        return self.buys_m5 / self.sells_m5 if self.sells_m5 else float(self.buys_m5)

    def age_minutes(self, now_ms: int) -> float | None:
        if not self.created_at_ms:
            return None
        return (now_ms - self.created_at_ms) / 60_000

    @classmethod
    def from_dexscreener(cls, pair: dict[str, Any]) -> "PairSnapshot":
        def num(v: Any) -> float:
            try:
                return float(v)
            except (TypeError, ValueError):
                return 0.0

        txns = (pair.get("txns") or {}).get("m5") or {}
        volume = pair.get("volume") or {}
        change = pair.get("priceChange") or {}
        base = pair.get("baseToken") or {}
        return cls(
            chain=pair.get("chainId", ""),
            dex=pair.get("dexId", ""),
            pair_address=pair.get("pairAddress", ""),
            mint=base.get("address", ""),
            symbol=base.get("symbol", "?"),
            name=base.get("name", ""),
            quote_symbol=(pair.get("quoteToken") or {}).get("symbol", ""),
            price_usd=num(pair.get("priceUsd")),
            liquidity_usd=num((pair.get("liquidity") or {}).get("usd")),
            market_cap_usd=num(pair.get("marketCap") or pair.get("fdv")),
            volume_h1_usd=num(volume.get("h1")),
            volume_h24_usd=num(volume.get("h24")),
            buys_m5=int(num(txns.get("buys"))),
            sells_m5=int(num(txns.get("sells"))),
            price_change_m5_pct=num(change.get("m5")),
            price_change_h1_pct=num(change.get("h1")),
            created_at_ms=pair.get("pairCreatedAt"),
            url=pair.get("url", ""),
        )


@dataclass
class Fill:
    price_usd: float        # effective price paid/received per token
    sol_amount: float       # SOL spent (buy) or received (sell)
    token_amount: float     # tokens received (buy) or sold (sell); raw units in live mode
    signature: str = "paper"


@dataclass
class Position:
    mint: str
    symbol: str
    pair_address: str
    entry_price_usd: float
    entry_liquidity_usd: float
    cost_sol: float                 # SOL spent opening the position
    token_amount: float             # tokens currently held
    initial_token_amount: float
    opened_at: float                # unix seconds
    peak_price_usd: float
    tiers_hit: list[int] = field(default_factory=list)
    realized_sol: float = 0.0       # SOL received from partial sells so far

    @property
    def remaining_fraction(self) -> float:
        if not self.initial_token_amount:
            return 0.0
        return self.token_amount / self.initial_token_amount

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Position":
        return cls(**d)


@dataclass
class ClosedTrade:
    mint: str
    symbol: str
    opened_at: float
    closed_at: float
    cost_sol: float
    proceeds_sol: float
    reason: str

    @property
    def pnl_sol(self) -> float:
        return self.proceeds_sol - self.cost_sol

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
