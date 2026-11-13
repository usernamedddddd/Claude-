"""Ties it together: locate you, find nearby stores, collect deals, score and rank them."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone

from .config import Config
from .extract import enrich
from .geo import find_stores, geocode
from .http import Http
from .models import Deal, Location, Store
from .sources import Sources
from .state import State

log = logging.getLogger(__name__)

KIND_BASE = {"penny": 60, "clearance": 30, "sale": 15, "other": 0}


def score_deal(d: Deal, cfg: Config, now: datetime) -> float:
    s = KIND_BASE.get(d.kind, 0)
    s += min(40, (d.percent_off or 0) * 0.4)
    if d.price_notes:
        s += 10
    if d.upcs:
        s += 5                       # a UPC means you can scan and verify it in store
    if d.local_mention:
        s += 15
    if d.nearest_store and cfg.radius_miles > 0:
        s += 15 * max(0.0, 1 - d.nearest_store.distance_miles / cfg.radius_miles)
    if not d.chains:
        s -= 10
    if d.published:
        age_days = max(0.0, (now - d.published).total_seconds() / 86400)
        s *= max(0.3, 1 - 0.7 * age_days / max(1, cfg.max_age_days))
    return round(s, 1)


def _matches_any(text: str, words: list[str]) -> bool:
    return any(re.search(rf"\b{re.escape(w)}\b", text, re.IGNORECASE) for w in words)


def rank_deals(deals: list[Deal], cfg: Config, loc: Location | None, stores: list[Store] | None,
               now: datetime | None = None) -> list[Deal]:
    """Enrich, filter and sort deals, best first. `stores=None` means store lookup was skipped."""
    now = now or datetime.now(timezone.utc)
    nearest: dict[str, Store] = {}
    for st in stores or []:
        if st.chain not in nearest or st.distance_miles < nearest[st.chain].distance_miles:
            nearest[st.chain] = st

    out = []
    for d in deals:
        enrich(d, cfg.chains, loc)
        blob = f"{d.title} {d.text}"
        if d.published and (now - d.published).days > cfg.max_age_days:
            continue
        if cfg.exclude_keywords and _matches_any(blob, cfg.exclude_keywords):
            continue
        if cfg.keywords and not _matches_any(blob, cfg.keywords):
            continue
        if cfg.penny_only and d.kind != "penny":
            continue
        if d.chains and stores is not None:
            near = [nearest[c] for c in d.chains if c in nearest]
            if not near and cfg.require_nearby_store:
                continue
            d.nearest_store = min(near, key=lambda s: s.distance_miles) if near else None
        d.score = score_deal(d, cfg, now)
        if d.score >= cfg.min_score:
            out.append(d)
    return sorted(out, key=lambda d: d.score, reverse=True)


class DealFinder:
    def __init__(self, cfg: Config, http: Http | None = None, state: State | None = None):
        self.cfg = cfg
        self.http = http or Http()
        self.state = state or State(cfg.state_file)
        self.sources = Sources(self.http, cfg)
        self._loc: Location | None = None

    def locate(self) -> Location | None:
        if self._loc:
            return self._loc
        c = self.cfg
        if c.lat is not None and c.lon is not None:
            self._loc = Location(c.lat, c.lon, f"{c.lat:.4f},{c.lon:.4f}", c.city, c.state)
        elif c.location:
            self._loc = geocode(self.http, c.location)
            self._loc.city = c.city or self._loc.city
            self._loc.state = c.state or self._loc.state
        return self._loc

    def stores(self) -> list[Store] | None:
        """Nearby stores of your chains, or None when no location is configured or lookup failed."""
        loc = self.locate()
        if not loc:
            return None
        key = f"{loc.lat:.3f},{loc.lon:.3f},{self.cfg.radius_miles},{','.join(sorted(self.cfg.chains))}"
        cached = self.state.cached_stores(key, self.cfg.store_cache_days)
        if cached is not None:
            return cached
        try:
            found = find_stores(self.http, loc, self.cfg.radius_miles, self.cfg.chains)
        except Exception as e:
            log.warning("Store lookup failed (%s); showing deals for all chains.", e)
            return None
        self.state.cache_stores(key, found)
        self.state.save()
        return found

    def find(self) -> tuple[list[Deal], list[Store] | None]:
        stores = self.stores()
        deals = self.sources.fetch_all()
        return rank_deals(deals, self.cfg, self.locate(), stores), stores
