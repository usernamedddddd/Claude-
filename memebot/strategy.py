"""Entry filters, candidate ranking and exit rules. Pure functions — easy to test and tune."""

from __future__ import annotations

from dataclasses import dataclass

from .config import EntryConfig, ExitConfig
from .models import PairSnapshot, Position


def entry_rejection(p: PairSnapshot, cfg: EntryConfig, now_ms: int) -> str | None:
    """None if the pair passes every entry filter, otherwise the first failing reason."""
    if p.price_usd <= 0:
        return "no price"
    if p.quote_symbol.upper() not in {s.upper() for s in cfg.allowed_quote_symbols}:
        return f"quote {p.quote_symbol} not allowed"
    if not cfg.min_liquidity_usd <= p.liquidity_usd <= cfg.max_liquidity_usd:
        return f"liquidity ${p.liquidity_usd:,.0f} out of range"
    if not cfg.min_market_cap_usd <= p.market_cap_usd <= cfg.max_market_cap_usd:
        return f"market cap ${p.market_cap_usd:,.0f} out of range"
    age = p.age_minutes(now_ms)
    if age is None or not cfg.min_age_minutes <= age <= cfg.max_age_minutes:
        return "age out of range" if age is not None else "unknown age"
    if p.volume_h1_usd < cfg.min_volume_h1_usd:
        return f"1h volume ${p.volume_h1_usd:,.0f} too low"
    if p.txns_m5 < cfg.min_txns_m5:
        return f"only {p.txns_m5} txns in 5m"
    if p.buy_sell_ratio_m5 < cfg.min_buy_sell_ratio_m5:
        return f"buy/sell ratio {p.buy_sell_ratio_m5:.2f} too low"
    if p.price_change_h1_pct < cfg.min_price_change_h1_pct:
        return f"1h change {p.price_change_h1_pct:+.1f}% too weak"
    if p.price_change_m5_pct > cfg.max_price_change_m5_pct:
        return f"5m change {p.price_change_m5_pct:+.1f}% too hot"
    return None


def momentum_score(p: PairSnapshot) -> float:
    """Rank candidates: volume turnover relative to liquidity, weighted by buy pressure."""
    turnover = p.volume_h1_usd / p.liquidity_usd if p.liquidity_usd else 0.0
    return turnover * min(p.buy_sell_ratio_m5, 3.0)


@dataclass
class ExitSignal:
    fraction: float     # fraction of the *current* holding to sell (1.0 = close)
    reason: str
    tier_index: int | None = None


def exit_signal(pos: Position, p: PairSnapshot, cfg: ExitConfig, now_s: float) -> ExitSignal | None:
    """Decide whether to sell some or all of a position. Full exits take priority."""
    price = p.price_usd
    gain_pct = (price / pos.entry_price_usd - 1) * 100
    peak = max(pos.peak_price_usd, price)

    if pos.entry_liquidity_usd and p.liquidity_usd < pos.entry_liquidity_usd * (1 - cfg.liquidity_drop_exit_pct / 100):
        return ExitSignal(1.0, f"liquidity collapsed to ${p.liquidity_usd:,.0f}")
    if gain_pct <= -cfg.stop_loss_pct:
        return ExitSignal(1.0, f"stop loss ({gain_pct:+.1f}%)")
    peak_gain_pct = (peak / pos.entry_price_usd - 1) * 100
    drawdown_pct = (1 - price / peak) * 100
    if peak_gain_pct >= cfg.trailing_activation_pct and drawdown_pct >= cfg.trailing_stop_pct:
        return ExitSignal(1.0, f"trailing stop ({drawdown_pct:.1f}% off peak, {gain_pct:+.1f}%)")
    if (now_s - pos.opened_at) / 60 >= cfg.max_hold_minutes:
        return ExitSignal(1.0, f"max hold time ({gain_pct:+.1f}%)")

    for i, tier in enumerate(cfg.take_profit_tiers):
        if i in pos.tiers_hit or gain_pct < tier["gain_pct"]:
            continue
        # Tier fractions are of the original size; convert to a fraction of what's left.
        remaining = pos.remaining_fraction
        if remaining <= 0:
            return None
        fraction = min(1.0, tier["fraction"] / remaining)
        return ExitSignal(fraction, f"take profit tier {i + 1} ({gain_pct:+.1f}%)", tier_index=i)
    return None
