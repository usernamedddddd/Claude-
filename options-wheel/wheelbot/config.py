"""Configuration loading. Every value has a conservative default."""

from __future__ import annotations

from dataclasses import dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass
class ContractRules:
    """How to pick the option to sell. Used for both puts and calls."""
    enabled: bool = True
    target_delta: float = 0.25           # absolute delta; ~25% chance of finishing in the money
    min_delta: float = 0.15
    max_delta: float = 0.30
    min_dte: int = 21                    # days to expiration
    target_dte: int = 35
    max_dte: int = 45
    min_annualized_yield_pct: float = 12  # credit / strike, annualized
    min_bid: float = 0.10                # skip contracts priced at pennies
    min_open_interest: int = 100
    max_spread_pct: float = 15           # (ask - bid) / mid; wide spreads mean bad fills


def _call_defaults() -> ContractRules:
    return ContractRules(target_delta=0.30, min_delta=0.15, max_delta=0.40, min_annualized_yield_pct=8)


@dataclass
class ManageConfig:
    take_profit_pct: float = 50          # buy back once this much of the credit is captured
    stop_loss_multiple: float | None = None  # buy back if the option costs this many x the credit (null = never)
    close_at_dte: int | None = None      # buy back at this DTE whatever the PnL (null = hold to expiry)


@dataclass
class RiskConfig:
    contracts_per_trade: int = 1
    max_per_ticker_usd: float = 5_000    # put collateral + stock cost basis, per ticker
    max_total_collateral_usd: float = 10_000
    min_cash_reserve_usd: float = 500    # never commit the last of the cash
    min_call_strike_above_cost_pct: float = 0  # covered calls never strike below cost basis + this
    avoid_earnings: bool = True          # don't sell options that expire after an earnings report


@dataclass
class MarketConfig:
    skip_first_minutes: float = 15       # spreads are wide right after the open
    skip_last_minutes: float = 10


@dataclass
class ExecutionConfig:
    mode: str = "paper"                  # "paper" or "live"
    order_timeout_seconds: float = 60    # cancel an unfilled limit order after this long
    paper_starting_cash: float = 10_000
    paper_fee_per_contract: float = 0.05  # regulatory/exchange fees; Robinhood charges no commission
    paper_state_file: str = "paper_account.json"


@dataclass
class Config:
    tickers: list[str] = field(default_factory=list)
    poll_seconds: float = 300
    state_file: str = "state.json"
    puts: ContractRules = field(default_factory=ContractRules)
    calls: ContractRules = field(default_factory=_call_defaults)
    manage: ManageConfig = field(default_factory=ManageConfig)
    risk: RiskConfig = field(default_factory=RiskConfig)
    market: MarketConfig = field(default_factory=MarketConfig)
    execution: ExecutionConfig = field(default_factory=ExecutionConfig)


def _merge(obj: Any, data: dict[str, Any], path: str = "") -> Any:
    known = {f.name: f for f in fields(obj)}
    for key, value in data.items():
        if key not in known:
            raise ValueError(f"Unknown config key: {path}{key}")
        current = getattr(obj, key)
        if is_dataclass(current):
            if not isinstance(value, dict):
                raise ValueError(f"Config section {path}{key} must be a mapping")
            _merge(current, value, f"{path}{key}.")
        else:
            setattr(obj, key, value)
    return obj


def load_config(path: str | Path | None) -> Config:
    cfg = Config()
    if path is not None:
        data = yaml.safe_load(Path(path).read_text()) or {}
        cfg = _merge(cfg, data)
    cfg.tickers = [t.upper() for t in cfg.tickers]
    if cfg.execution.mode not in ("paper", "live"):
        raise ValueError("execution.mode must be 'paper' or 'live'")
    for name in ("puts", "calls"):
        r: ContractRules = getattr(cfg, name)
        if not (0 < r.min_delta <= r.target_delta <= r.max_delta < 1):
            raise ValueError(f"{name}: need 0 < min_delta <= target_delta <= max_delta < 1")
        if not (0 <= r.min_dte <= r.target_dte <= r.max_dte):
            raise ValueError(f"{name}: need min_dte <= target_dte <= max_dte")
    if cfg.risk.contracts_per_trade < 1:
        raise ValueError("risk.contracts_per_trade must be >= 1")
    return cfg
