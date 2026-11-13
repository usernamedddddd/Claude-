"""Build deals.json: every recent store deal from every source, for the phone app.

The file is the same for everyone (no location in it). The phone app ranks it
against the user's own location and stores, on the phone.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .chains import CHAINS
from .config import Config
from .extract import enrich
from .http import Http
from .models import Deal
from .sources import SourceStatus, Sources

MAX_TEXT = 800
MAX_DEALS = 600


def is_store_deal(d: Deal) -> bool:
    """Keep posts about a store we know, or that are clearly penny/clearance finds."""
    return bool(d.chains) or d.kind in ("penny", "clearance")


def build(deals: list[Deal], statuses: list[SourceStatus], cfg: Config, now: datetime) -> dict:
    cutoff = now - timedelta(days=cfg.max_age_days)
    kept = []
    for d in deals:
        if d.published and d.published < cutoff:
            continue
        enrich(d, list(CHAINS))
        if is_store_deal(d):
            kept.append(d)
    kept.sort(key=lambda d: d.published or cutoff, reverse=True)
    return {
        "generated_at": int(now.timestamp() * 1000),
        "sources": [asdict(s) for s in statuses],
        "deals": [{
            "id": d.id, "title": d.title, "url": d.url, "source": d.source,
            "text": d.text[:MAX_TEXT],
            "published": int(d.published.timestamp() * 1000) if d.published else None,
        } for d in kept[:MAX_DEALS]],
    }


def export(cfg: Config, out: str | Path, http: Http | None = None, now: datetime | None = None) -> dict:
    deals, statuses = Sources(http or Http(timeout=15, retries=1), cfg).fetch_all_with_status()
    data = build(deals, statuses, cfg, now or datetime.now(timezone.utc))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    return data
