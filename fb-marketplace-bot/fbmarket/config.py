"""Configuration loading. Secrets (bot tokens, webhook URLs) come from environment variables."""

from __future__ import annotations

from dataclasses import dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any

import yaml

MIN_POLL_MINUTES = 5  # polling faster than this gets accounts rate-limited or checkpointed


@dataclass
class SearchConfig:
    name: str = ""
    query: str = ""
    # Location slug from a Marketplace URL, e.g. "nyc" in facebook.com/marketplace/nyc/...
    # or a numeric city id. Empty uses the location saved on your Facebook account.
    location: str = ""
    radius_km: int | None = None
    min_price: float | None = None
    max_price: float | None = None
    days_since_listed: int | None = 1    # 1, 7 or 30; None for any time
    must_include: list[str] = field(default_factory=list)   # every term must appear in the title
    include_any: list[str] = field(default_factory=list)    # at least one must appear (if given)
    exclude: list[str] = field(default_factory=list)        # none may appear
    allow_unknown_price: bool = False                        # keep listings whose price can't be read


@dataclass
class BrowserConfig:
    headless: bool = True
    user_data_dir: str = ".fb-profile"   # holds your logged-in session cookies; keep it private
    executable_path: str | None = None   # custom Chromium/Chrome binary, if Playwright's isn't installed
    scrolls: int = 3                     # page scrolls per search; each loads ~20-30 more listings
    page_timeout_s: float = 45
    min_delay_s: float = 8               # random pause between searches, to look less robotic
    max_delay_s: float = 20


@dataclass
class TelegramConfig:
    enabled: bool = False
    chat_id: str = ""                    # or set TELEGRAM_CHAT_ID; the token is TELEGRAM_BOT_TOKEN


@dataclass
class DiscordConfig:
    enabled: bool = False                # webhook URL comes from DISCORD_WEBHOOK_URL


@dataclass
class NtfyConfig:
    enabled: bool = False
    server: str = "https://ntfy.sh"
    topic: str = ""                      # pick something unguessable; anyone with it can read alerts


@dataclass
class NotifyConfig:
    console: bool = True
    telegram: TelegramConfig = field(default_factory=TelegramConfig)
    discord: DiscordConfig = field(default_factory=DiscordConfig)
    ntfy: NtfyConfig = field(default_factory=NtfyConfig)


@dataclass
class Config:
    poll_minutes: float = 10
    jitter_pct: float = 30               # randomize each wait by ± this percent
    state_file: str = "seen.json"
    alert_on_first_run: bool = False     # False: the first pass of a search only records what exists
    alert_price_drops: bool = True
    forget_after_days: float = 30
    browser: BrowserConfig = field(default_factory=BrowserConfig)
    notify: NotifyConfig = field(default_factory=NotifyConfig)
    searches: list[SearchConfig] = field(default_factory=list)


def _merge(obj: Any, data: dict[str, Any], path: str = "") -> Any:
    known = {f.name for f in fields(obj)}
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


def _validate(cfg: Config) -> Config:
    if cfg.poll_minutes < MIN_POLL_MINUTES:
        raise ValueError(f"poll_minutes must be at least {MIN_POLL_MINUTES}")
    if not cfg.searches:
        raise ValueError("Add at least one entry under `searches:`")
    names = set()
    for s in cfg.searches:
        if not s.query.strip():
            raise ValueError("Every search needs a `query`")
        s.name = s.name or s.query
        for attr in ("must_include", "include_any", "exclude"):
            terms = getattr(s, attr) or []
            if isinstance(terms, str):
                terms = [terms]
            setattr(s, attr, [str(t) for t in terms])   # YAML turns `55` into an int
        if s.name in names:
            raise ValueError(f"Duplicate search name: {s.name}")
        names.add(s.name)
        if s.min_price is not None and s.max_price is not None and s.min_price > s.max_price:
            raise ValueError(f"Search {s.name!r}: min_price is above max_price")
        if s.days_since_listed not in (None, 1, 7, 30):
            raise ValueError(f"Search {s.name!r}: days_since_listed must be 1, 7, 30 or null")
    if cfg.browser.min_delay_s > cfg.browser.max_delay_s:
        raise ValueError("browser.min_delay_s is above browser.max_delay_s")
    if cfg.notify.ntfy.enabled and not cfg.notify.ntfy.topic:
        raise ValueError("notify.ntfy.topic is required when ntfy is enabled")
    return cfg


def parse_config(data: dict[str, Any]) -> Config:
    data = dict(data or {})
    raw_searches = data.pop("searches", []) or []
    cfg = _merge(Config(), data)
    for i, raw in enumerate(raw_searches):
        if not isinstance(raw, dict):
            raise ValueError(f"searches[{i}] must be a mapping")
        cfg.searches.append(_merge(SearchConfig(), raw, f"searches[{i}]."))
    return _validate(cfg)


def load_config(path: str | Path) -> Config:
    return parse_config(yaml.safe_load(Path(path).read_text()) or {})
