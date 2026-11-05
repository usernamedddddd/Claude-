"""Contract selection and exit rules. Pure functions: this is the place to tune."""

from __future__ import annotations

import math
from datetime import date

from .config import ContractRules, ManageConfig
from .models import OptionQuote, ShortOption


def dte(expiration: date, today: date) -> int:
    return (expiration - today).days


def annualized_yield_pct(credit: float, strike: float, days: int) -> float:
    """Return on collateral (the strike) if the option expires worthless."""
    return credit / strike * 365 / max(days, 1) * 100


def pick_expiration(expirations: list[date], today: date, rules: ContractRules) -> date | None:
    ok = [e for e in expirations if rules.min_dte <= dte(e, today) <= rules.max_dte]
    return min(ok, key=lambda e: (abs(dte(e, today) - rules.target_dte), e)) if ok else None


def contract_rejection(q: OptionQuote, today: date, rules: ContractRules, min_strike: float | None = None) -> str | None:
    """None if `q` is acceptable to sell."""
    if q.delta is None:
        return "delta missing"
    if not rules.min_delta <= abs(q.delta) <= rules.max_delta:
        return f"delta {abs(q.delta):.2f} outside {rules.min_delta}-{rules.max_delta}"
    if min_strike is not None and q.strike < min_strike - 1e-9:
        return f"strike {q.strike:g} below floor {min_strike:.2f}"
    if q.bid < rules.min_bid:
        return f"bid {q.bid:.2f} < {rules.min_bid}"
    if q.open_interest < rules.min_open_interest:
        return f"OI {q.open_interest} < {rules.min_open_interest}"
    if q.spread_pct > rules.max_spread_pct:
        return f"spread {q.spread_pct:.0f}% > {rules.max_spread_pct}%"
    y = annualized_yield_pct(q.mid, q.strike, dte(q.expiration, today))
    if y < rules.min_annualized_yield_pct:
        return f"yield {y:.1f}% < {rules.min_annualized_yield_pct}%"
    return None


def pick_contract(quotes: list[OptionQuote], today: date, rules: ContractRules,
                  min_strike: float | None = None) -> OptionQuote | None:
    """Acceptable contract closest to the target delta (higher yield breaks ties)."""
    ok = [q for q in quotes if contract_rejection(q, today, rules, min_strike) is None]
    if not ok:
        return None
    return min(ok, key=lambda q: (abs(abs(q.delta) - rules.target_delta),
                                  -annualized_yield_pct(q.mid, q.strike, dte(q.expiration, today))))


def round_to_tick(price: float, q: OptionQuote, up: bool) -> float:
    tick = q.tick_below if price < q.tick_cutoff else q.tick_above
    n = price / tick
    n = math.ceil(n - 1e-9) if up else math.floor(n + 1e-9)
    return round(max(n, 1) * tick, 2)


def sell_price(q: OptionQuote) -> float:
    """Limit price to sell at: the mid, rounded down to a valid tick, never below the bid."""
    return max(round_to_tick(q.mid, q, up=False), round_to_tick(q.bid, q, up=True))


def buy_price(q: OptionQuote) -> float:
    """Limit price to buy back at: the mid, rounded up to a valid tick, never above the ask."""
    return min(round_to_tick(q.mid, q, up=True), round_to_tick(q.ask, q, up=False))


def close_signal(pos: ShortOption, mark: float, today: date, cfg: ManageConfig) -> str | None:
    """Reason to buy back a short option now, or None to keep holding it."""
    if pos.avg_credit <= 0:
        return None
    captured = (pos.avg_credit - mark) / pos.avg_credit * 100
    if captured >= cfg.take_profit_pct:
        return f"take profit: {captured:.0f}% of credit captured"
    if cfg.stop_loss_multiple and mark >= pos.avg_credit * cfg.stop_loss_multiple:
        return f"stop loss: option at {mark / pos.avg_credit:.1f}x credit"
    if cfg.close_at_dte is not None and dte(pos.expiration, today) <= cfg.close_at_dte:
        return f"close at {dte(pos.expiration, today)} DTE ({captured:+.0f}% of credit)"
    return None
