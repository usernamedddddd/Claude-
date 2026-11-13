"""Where deals come from: Reddit search, Google News and any RSS/Atom feed.

Penny lists and clearance finds are shared by shoppers, not published by the
stores, so the bot reads the places shoppers post them.
"""

from __future__ import annotations

import hashlib
import logging
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

from .extract import clean_text
from .http import Http
from .models import Deal

log = logging.getLogger(__name__)

REDDIT_SEARCH = "https://www.reddit.com/search.json"
GOOGLE_NEWS = "https://news.google.com/rss/search"


def _id(*parts: str) -> str:
    return hashlib.sha1("|".join(parts).encode()).hexdigest()[:16]


def parse_reddit(payload: dict) -> list[Deal]:
    out = []
    for child in (payload.get("data") or {}).get("children", []):
        d = child.get("data") or {}
        if not d.get("id") or d.get("over_18"):
            continue
        created = d.get("created_utc")
        out.append(Deal(
            id=f"reddit:{d['id']}",
            title=clean_text(d.get("title", "")),
            url="https://www.reddit.com" + d.get("permalink", ""),
            source=f"r/{d.get('subreddit', '?')}",
            text=clean_text(d.get("selftext", ""))[:4000],
            published=datetime.fromtimestamp(created, timezone.utc) if created else None,
        ))
    return out


def _parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    value = value.strip()
    try:
        dt = parsedate_to_datetime(value)          # RSS: "Tue, 10 Nov 2026 08:00:00 GMT"
    except (TypeError, ValueError):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))   # Atom: ISO 8601
        except ValueError:
            return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def parse_feed(xml_text: str, source: str) -> list[Deal]:
    """Parse RSS 2.0 or Atom into deals."""
    root = ET.fromstring(xml_text)
    atom = "{http://www.w3.org/2005/Atom}"
    out = []
    items = root.findall(".//item")
    if items:
        for it in items:
            link = (it.findtext("link") or "").strip()
            title = clean_text(it.findtext("title") or "")
            src = it.find("source")
            out.append(Deal(
                id=f"feed:{_id(link or title)}",
                title=title,
                url=link,
                source=(src.text.strip() if src is not None and src.text else source),
                text=clean_text(it.findtext("description") or "")[:4000],
                published=_parse_date(it.findtext("pubDate")),
            ))
        return out
    for entry in root.findall(f"{atom}entry"):
        link_el = entry.find(f"{atom}link")
        link = link_el.get("href", "") if link_el is not None else ""
        title = clean_text(entry.findtext(f"{atom}title") or "")
        body = entry.findtext(f"{atom}summary") or entry.findtext(f"{atom}content") or ""
        out.append(Deal(
            id=f"feed:{_id(link or title)}",
            title=title,
            url=link,
            source=source,
            text=clean_text(body)[:4000],
            published=_parse_date(entry.findtext(f"{atom}updated") or entry.findtext(f"{atom}published")),
        ))
    return out


class Sources:
    def __init__(self, http: Http, cfg):
        self.http = http
        self.cfg = cfg

    def reddit(self, query: str) -> list[Deal]:
        t = "week" if self.cfg.max_age_days <= 7 else "month"
        data = self.http.get_json(REDDIT_SEARCH, {"q": query, "sort": "new", "t": t, "limit": 50})
        return parse_reddit(data)

    def google_news(self, query: str) -> list[Deal]:
        xml = self.http.get_text(GOOGLE_NEWS, {"q": f"{query} when:{self.cfg.max_age_days}d",
                                               "hl": "en-US", "gl": "US", "ceid": "US:en"})
        return parse_feed(xml, "Google News")

    def feed(self, url: str) -> list[Deal]:
        return parse_feed(self.http.get_text(url), url.split("/")[2] if "//" in url else url)

    def fetch_all(self) -> list[Deal]:
        jobs = ([(f"reddit '{q}'", self.reddit, q) for q in self.cfg.reddit_queries]
                + [(f"news '{q}'", self.google_news, q) for q in self.cfg.google_news_queries]
                + [(f"feed {u}", self.feed, u) for u in self.cfg.rss_feeds])
        deals: dict[str, Deal] = {}
        for label, fn, arg in jobs:
            try:
                got = fn(arg)
                log.info("%s: %d posts", label, len(got))
                for d in got:
                    deals.setdefault(d.id, d)
            except Exception as e:  # one broken source shouldn't stop the others
                log.warning("%s failed: %s", label, e)
        return list(deals.values())
