"""Configuration loading. Every value has a conservative default."""

from __future__ import annotations

from dataclasses import dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass
class EntryConfig:
    min_liquidity_usd: float = 20_000
    max_liquidity_usd: float = 2_000_000
    min_market_cap_usd: float = 50_000
    max_market_cap_usd: float = 20_000_000
    min_age_minutes: float = 15          # skip the first minutes of launch chaos
    max_age_minutes: float = 24 * 60
    min_volume_h1_usd: float = 25_000
    min_txns_m5: int = 20
    min_buy_sell_ratio_m5: float = 1.2  # buys / sells over the last 5 minutes
    min_price_change_h1_pct: float = 5
    max_price_change_m5_pct: float = 25  # don't chase a vertical candle
    allowed_quote_symbols: list[str] = field(default_factory=lambda: ["SOL", "WSOL", "USDC"])


@dataclass
class SafetyConfig:
    enabled: bool = True
    max_risk_score: int = 1000           # RugCheck raw score; lower is safer
    reject_on_danger: bool = True        # any risk flagged "danger" rejects the token
    reject_if_unavailable: bool = True   # no report → don't trade


@dataclass
class ExitConfig:
    stop_loss_pct: float = 25
    # Each tier: sell `fraction` of the *original* position when gain >= `gain_pct`.
    take_profit_tiers: list[dict[str, float]] = field(
        default_factory=lambda: [
            {"gain_pct": 50, "fraction": 0.5},
            {"gain_pct": 150, "fraction": 0.25},
        ]
    )
    trailing_activation_pct: float = 30  # trailing stop arms once gain reaches this
    trailing_stop_pct: float = 20        # sell if price falls this far from the peak
    max_hold_minutes: float = 240
    liquidity_drop_exit_pct: float = 50  # liquidity fell this much since entry → likely rug


@dataclass
class RiskConfig:
    position_size_sol: float = 0.1
    max_open_positions: int = 3
    max_total_exposure_sol: float = 0.5
    daily_loss_limit_sol: float = 0.3    # stop opening positions after this realized loss
    reentry_cooldown_minutes: float = 360
    blacklist: list[str] = field(default_factory=list)


@dataclass
class ExecutionConfig:
    mode: str = "paper"                  # "paper" or "live"
    slippage_bps: int = 300
    paper_fee_pct: float = 1.0           # simulated DEX + priority fees per side
    rpc_url: str = "https://api.mainnet-beta.solana.com"
    jupiter_base_url: str = "https://lite-api.jup.ag/swap/v1"
    priority_fee_lamports: str | int = "auto"


@dataclass
class Config:
    chain: str = "solana"
    poll_seconds: float = 30
    max_candidates_per_cycle: int = 30
    state_file: str = "state.json"
    entry: EntryConfig = field(default_factory=EntryConfig)
    safety: SafetyConfig = field(default_factory=SafetyConfig)
    exit: ExitConfig = field(default_factory=ExitConfig)
    risk: RiskConfig = field(default_factory=RiskConfig)
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
    if path is None:
        return cfg
    data = yaml.safe_load(Path(path).read_text()) or {}
    cfg = _merge(cfg, data)
    if cfg.execution.mode not in ("paper", "live"):
        raise ValueError("execution.mode must be 'paper' or 'live'")
    return cfg
