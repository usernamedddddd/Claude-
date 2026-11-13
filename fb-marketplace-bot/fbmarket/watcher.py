"""The polling loop: search, filter, dedupe against what we've seen, alert."""

from __future__ import annotations

import logging
import random
import time
from typing import Callable, Protocol

from .config import Config, SearchConfig
from .filters import matches
from .models import Alert, Listing
from .notify import Notifier
from .scraper import LoginRequired
from .store import SeenStore

log = logging.getLogger(__name__)


class Scraper(Protocol):
    def search(self, s: SearchConfig) -> list[Listing]: ...


class Watcher:
    def __init__(self, cfg: Config, scraper: Scraper, store: SeenStore, notifier: Notifier,
                 sleep: Callable[[float], None] = time.sleep, rng: random.Random | None = None):
        self.cfg = cfg
        self.scraper = scraper
        self.store = store
        self.notifier = notifier
        self.sleep = sleep
        self.rng = rng or random.Random()

    def check_search(self, s: SearchConfig) -> list[Alert]:
        listings = self.scraper.search(s)
        hits = [li for li in listings if matches(li, s)]
        seeding = not self.store.is_seeded(s.name)
        alerts = []
        for li in hits:
            kind, old = self.store.observe(li)
            if kind is None or (kind == "price_drop" and not self.cfg.alert_price_drops):
                continue
            if seeding and not self.cfg.alert_on_first_run:
                continue
            alerts.append(Alert(li, kind, old))
        if seeding:
            self.store.mark_seeded(s.name)
            log.info("[%s] first pass: recorded %d matching listings%s", s.name, len(hits),
                     "" if self.cfg.alert_on_first_run else " (no alerts; new ones will alert from now on)")
        log.info("[%s] %d listings scraped, %d match, %d alerts", s.name, len(listings), len(hits), len(alerts))
        return alerts

    def cycle(self) -> list[Alert]:
        all_alerts: list[Alert] = []
        for i, s in enumerate(self.cfg.searches):
            if i:
                b = self.cfg.browser
                self.sleep(self.rng.uniform(b.min_delay_s, b.max_delay_s))
            try:
                alerts = self.check_search(s)
            except LoginRequired:
                raise
            except Exception as exc:  # noqa: BLE001 - one broken search shouldn't kill the rest
                log.warning("[%s] search failed: %s", s.name, exc)
                continue
            for a in alerts:
                self.notifier.send(a)
            all_alerts.extend(alerts)
            self.store.save()   # save after each search so a crash never re-sends alerts
        self.store.prune(self.cfg.forget_after_days)
        self.store.save()
        return all_alerts

    def next_wait_s(self) -> float:
        base = self.cfg.poll_minutes * 60
        j = self.cfg.jitter_pct / 100
        return base * self.rng.uniform(1 - j, 1 + j)

    def run_forever(self) -> None:
        while True:
            try:
                self.cycle()
            except LoginRequired as exc:
                self.notifier.send_text(f"Marketplace watcher stopped: {exc}")
                raise
            wait = self.next_wait_s()
            log.info("Next check in %.1f min", wait / 60)
            self.sleep(wait)
