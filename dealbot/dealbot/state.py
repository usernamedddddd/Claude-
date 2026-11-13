"""Remembers which deals were already alerted, and caches the store lookup."""

from __future__ import annotations

import json
import time
from dataclasses import asdict
from pathlib import Path

from .models import Store

SEEN_TTL_S = 30 * 86400


class State:
    def __init__(self, path: str):
        self.path = Path(path)
        self.seen: dict[str, float] = {}
        self.store_cache: dict = {}
        if self.path.exists():
            try:
                data = json.loads(self.path.read_text())
                self.seen = data.get("seen", {})
                self.store_cache = data.get("store_cache", {})
            except (json.JSONDecodeError, OSError):
                pass  # a corrupt state file just means we start fresh

    def is_new(self, deal_id: str) -> bool:
        return deal_id not in self.seen

    def mark_seen(self, deal_id: str, now: float | None = None) -> None:
        self.seen[deal_id] = now or time.time()

    def cached_stores(self, key: str, max_age_days: float, now: float | None = None) -> list[Store] | None:
        entry = self.store_cache.get(key)
        if not entry or (now or time.time()) - entry["at"] > max_age_days * 86400:
            return None
        return [Store(**s) for s in entry["stores"]]

    def cache_stores(self, key: str, stores: list[Store], now: float | None = None) -> None:
        self.store_cache = {key: {"at": now or time.time(), "stores": [asdict(s) for s in stores]}}

    def save(self, now: float | None = None) -> None:
        cutoff = (now or time.time()) - SEEN_TTL_S
        self.seen = {k: v for k, v in self.seen.items() if v >= cutoff}
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"seen": self.seen, "store_cache": self.store_cache}, indent=1))
        tmp.replace(self.path)
