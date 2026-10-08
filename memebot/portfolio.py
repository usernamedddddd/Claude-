"""Open positions, trade history and risk limits, persisted to a JSON file."""

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from .config import RiskConfig
from .models import ClosedTrade, Position


class Portfolio:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.positions: dict[str, Position] = {}
        self.closed: list[ClosedTrade] = []
        self.last_exit_at: dict[str, float] = {}
        if self.path.exists():
            data = json.loads(self.path.read_text())
            self.positions = {m: Position.from_dict(p) for m, p in data.get("positions", {}).items()}
            self.closed = [ClosedTrade(**t) for t in data.get("closed", [])]
            self.last_exit_at = data.get("last_exit_at", {})

    def save(self) -> None:
        data = {
            "positions": {m: p.to_dict() for m, p in self.positions.items()},
            "closed": [t.to_dict() for t in self.closed],
            "last_exit_at": self.last_exit_at,
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self.path)  # atomic: a crash never leaves a half-written state file

    @property
    def exposure_sol(self) -> float:
        return sum(p.cost_sol * p.remaining_fraction for p in self.positions.values())

    def realized_pnl_today(self, now_s: float | None = None) -> float:
        today = datetime.fromtimestamp(now_s or time.time(), timezone.utc).date()
        return sum(
            t.pnl_sol for t in self.closed
            if datetime.fromtimestamp(t.closed_at, timezone.utc).date() == today
        )

    def total_realized_pnl(self) -> float:
        return sum(t.pnl_sol for t in self.closed)


def open_rejection(pf: Portfolio, cfg: RiskConfig, mint: str, now_s: float) -> str | None:
    """None if a new position in `mint` is allowed under the risk limits."""
    if mint in cfg.blacklist:
        return "blacklisted"
    if mint in pf.positions:
        return "already holding"
    last = pf.last_exit_at.get(mint)
    if last is not None and (now_s - last) / 60 < cfg.reentry_cooldown_minutes:
        return "re-entry cooldown"
    if len(pf.positions) >= cfg.max_open_positions:
        return "max open positions"
    if pf.exposure_sol + cfg.position_size_sol > cfg.max_total_exposure_sol + 1e-12:
        return "max total exposure"
    if pf.realized_pnl_today(now_s) <= -cfg.daily_loss_limit_sol:
        return "daily loss limit hit"
    return None
