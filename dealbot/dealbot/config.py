"""Settings, loaded from a TOML file. Every value has a default."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from .chains import CHAINS


@dataclass
class Config:
    # where you are
    location: str = ""                 # "City, ST", street address or ZIP code
    lat: float | None = None
    lon: float | None = None
    city: str = ""                     # optional; filled in by geocoding when empty
    state: str = ""                    # full state name, e.g. "Tennessee"
    radius_miles: float = 10.0

    # which stores you'll shop at
    chains: list[str] = field(default_factory=lambda: list(CHAINS))

    # where deals come from
    reddit_queries: list[str] = field(default_factory=lambda: [
        "dollar general penny list",
        "dollar general penny",
        "home depot penny",
        "penny shopping",
        "hidden clearance",
        "target clearance 70%",
        "walmart clearance",
    ])
    google_news_queries: list[str] = field(default_factory=lambda: [
        "dollar general penny list",
        "home depot penny items",
        "target clearance",
        "walmart clearance",
        "lowe's clearance",
        "costco clearance markdown",
        "dollar tree deals",
    ])
    bing_news_queries: list[str] = field(default_factory=lambda: [
        "dollar general penny list",
        "home depot penny",
        "clearance deals walmart target",
    ])
    rss_feeds: list[str] = field(default_factory=lambda: [
        # Slickdeals searches (in-store and online deals; online-only ones score low)
        "https://slickdeals.net/newsearch.php?searcharea=deals&searchin=first&rss=1&q=clearance",
        "https://slickdeals.net/newsearch.php?searcharea=deals&searchin=first&rss=1&q=penny",
        "https://slickdeals.net/newsearch.php?searcharea=deals&searchin=first&rss=1&q=in-store",
        # deal blogs
        "https://hip2save.com/feed/",
        "https://www.thefreebieguy.com/feed/",
        "https://www.moneysavingmom.com/feed/",
    ])
    max_age_days: int = 7

    # what counts as worth showing
    min_score: float = 25.0
    penny_only: bool = False
    keywords: list[str] = field(default_factory=list)   # e.g. ["tide", "lego"]: only matching deals
    exclude_keywords: list[str] = field(default_factory=lambda: ["penny stock", "penny stocks", "crypto"])
    require_nearby_store: bool = True  # drop deals for chains with no store in your radius

    # alerts
    ntfy_topic: str = ""               # https://ntfy.sh topic name (pick something hard to guess)
    ntfy_server: str = "https://ntfy.sh"
    discord_webhook: str = ""
    alert_min_score: float = 50.0
    watch_interval_minutes: int = 60

    state_file: str = "dealbot_state.json"
    store_cache_days: int = 7


_SECTIONS = ("location", "stores", "sources", "filters", "alerts", "general")


# Environment variables override the file, so secrets (like your location and alert
# topic) can stay out of files, e.g. in GitHub Actions secrets.
ENV_OVERRIDES = {
    "DEALBOT_LOCATION": ("location", str),
    "DEALBOT_RADIUS_MILES": ("radius_miles", float),
    "DEALBOT_CHAINS": ("chains", lambda v: [c.strip() for c in v.split(",") if c.strip()]),
    "DEALBOT_NTFY_TOPIC": ("ntfy_topic", str),
    "DEALBOT_DISCORD_WEBHOOK": ("discord_webhook", str),
    "DEALBOT_ALERT_MIN_SCORE": ("alert_min_score", float),
    "DEALBOT_STATE_FILE": ("state_file", str),
    "DEALBOT_STORE_CACHE_DAYS": ("store_cache_days", int),
}


def load_config(path: str | Path | None, env: dict[str, str] | None = None) -> Config:
    cfg = _load_file(path)
    env = os.environ if env is None else env
    for var, (attr, conv) in ENV_OVERRIDES.items():
        value = (env.get(var) or "").strip()
        if value:
            try:
                setattr(cfg, attr, conv(value))
            except ValueError:
                raise ValueError(f"{var} has an invalid value") from None
    bad = [c for c in cfg.chains if c not in CHAINS]
    if bad:
        raise ValueError(f"Unknown chains {bad}. Choose from: {', '.join(CHAINS)}")
    return cfg


def _load_file(path: str | Path | None) -> Config:
    cfg = Config()
    if not path:
        return cfg
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Config file not found: {p}")
    with p.open("rb") as f:
        raw = tomllib.load(f)
    flat: dict = {}
    for key, value in raw.items():
        if key in _SECTIONS and isinstance(value, dict):
            flat.update(value)
        else:
            flat[key] = value
    if "query" in flat and "location" not in flat:
        flat["location"] = flat.pop("query")
    known = set(Config.__dataclass_fields__)
    unknown = sorted(set(flat) - known)
    if unknown:
        raise ValueError(f"Unknown config keys: {', '.join(unknown)}")
    for key, value in flat.items():
        setattr(cfg, key, value)
    return cfg
