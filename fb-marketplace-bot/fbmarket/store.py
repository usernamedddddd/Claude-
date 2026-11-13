"""Remembers which listings were already seen (and at what price), in a JSON file."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .models import Listing


class SeenStore:
    def __init__(self, path: str | Path, clock=time.time):
        self.path = Path(path)
        self.clock = clock
        self.listings: dict[str, dict] = {}
        self.seeded: set[str] = set()      # searches that finished their silent first pass
        if self.path.exists():
            data = json.loads(self.path.read_text())
            self.listings = data.get("listings", {})
            self.seeded = set(data.get("seeded", []))

    def is_seeded(self, search: str) -> bool:
        return search in self.seeded

    def mark_seeded(self, search: str) -> None:
        self.seeded.add(search)

    def observe(self, listing: Listing) -> tuple[str | None, float | None]:
        """Record a listing. Returns ("new", None), ("price_drop", old_price) or (None, None)."""
        now = self.clock()
        entry = self.listings.get(listing.id)
        if entry is None:
            self.listings[listing.id] = {
                "title": listing.title, "price": listing.price,
                "first_seen": now, "last_seen": now,
            }
            return "new", None
        entry["last_seen"] = now
        old = entry.get("price")
        if listing.price is not None:
            entry["price"] = listing.price
            if old is not None and listing.price < old:
                return "price_drop", old
        return None, None

    def prune(self, max_age_days: float) -> int:
        cutoff = self.clock() - max_age_days * 86400
        stale = [k for k, v in self.listings.items() if v.get("last_seen", 0) < cutoff]
        for k in stale:
            del self.listings[k]
        return len(stale)

    def save(self) -> None:
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(
            {"listings": self.listings, "seeded": sorted(self.seeded)}, indent=1))
        os.replace(tmp, self.path)
