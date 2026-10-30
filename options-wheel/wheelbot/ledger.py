"""The bot's own record of what it traded, persisted to a JSON file."""

from __future__ import annotations

import json
import os
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from .models import LedgerEntry, ShortOption

NY = ZoneInfo("America/New_York")


class Ledger:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.entries: list[LedgerEntry] = []
        self.known_shorts: dict[str, ShortOption] = {}   # short options open at the end of the last cycle
        if self.path.exists():
            data = json.loads(self.path.read_text())
            self.entries = [LedgerEntry(**e) for e in data.get("entries", [])]
            self.known_shorts = {k: ShortOption.from_dict(o) for k, o in data.get("known_shorts", {}).items()}

    def save(self) -> None:
        data = {
            "entries": [e.to_dict() for e in self.entries],
            "known_shorts": {k: o.to_dict() for k, o in self.known_shorts.items()},
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        os.replace(tmp, self.path)  # atomic: a crash never leaves a half-written state file

    def record(self, entry: LedgerEntry) -> None:
        self.entries.append(entry)
        self.save()

    def net_premium(self, today_only: bool = False, now_s: float | None = None) -> float:
        """Option credits received minus buy-back costs (excludes stock PnL and fees)."""
        if not today_only:
            return sum(e.cash_flow for e in self.entries)
        today = datetime.fromtimestamp(now_s or time.time(), NY).date()
        return sum(e.cash_flow for e in self.entries if datetime.fromtimestamp(e.at, NY).date() == today)
