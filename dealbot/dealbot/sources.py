"""Where deals come from: Reddit search, Google News and any RSS/Atom feed.

Penny lists and clearance finds are shared by shoppers, not published by the
stores, so the bot reads the places shoppers post them.
"""

from __future__ import annotations

import hashlib
import logging
import re
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

from .extract import clean_text
from .http import Http
from .models import Deal

log = logging.getLogger(__name__)

REDDIT_SEARCH = "https://www.reddit.com/search.json"
GOOGLE_NEWS = "https://news.google.com/rss/search"
BING_NEWS = "https://www.bing.com/news/search"


@dataclass
class SourceStatus:
    name: str
    ok: bool
    count: int = 0
    error: str = ""


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


_XML_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}


def _repair_xml(text: str) -> str:
    """Fix the usual mistakes in real-world feeds: HTML entities like &nbsp; and bare '&'."""
    import html.entities
    def entity(m):
        name = m.group(1)
        if name in _XML_ENTITIES:
            return m.group(0)
        cp = html.entities.name2codepoint.get(name)
        return f"&#{cp};" if cp else f"&amp;{name};"
    text = re.sub(r"&([A-Za-z][A-Za-z0-9]*);", entity, text)
    text = re.sub(r"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9]*;)", "&amp;", text)
    return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", text)   # control characters XML forbids


def _tag(block: str, name: str) -> str:
    m = re.search(rf"<{name}(?:\s[^>]*)?>(.*?)</{name}\s*>", block, re.S | re.I)
    if not m:
        return ""
    value = m.group(1).strip()
    cdata = re.fullmatch(r"<!\[CDATA\[(.*?)\]\]>", value, re.S)
    return cdata.group(1) if cdata else value


def _scan_feed(text: str, source: str) -> list[Deal]:
    """Last-resort reader for feeds with broken XML: find each <item>/<entry> with regexes."""
    out = []
    for block in re.findall(r"<(?:item|entry)(?:\s[^>]*)?>(.*?)</(?:item|entry)\s*>", text, re.S | re.I):
        title = clean_text(_tag(block, "title"))
        link = _tag(block, "link")
        if not link:   # Atom: <link href="..."/>
            m = re.search(r"<link[^>]*\bhref=[\"']([^\"']+)", block, re.I)
            link = m.group(1) if m else ""
        link = clean_text(link)
        if not (title or link):
            continue
        body = _tag(block, "description") or _tag(block, "summary") or _tag(block, "content")
        date = _tag(block, "pubDate") or _tag(block, "updated") or _tag(block, "published")
        out.append(Deal(id=f"feed:{_id(link or title)}", title=title, url=link, source=source,
                        text=clean_text(body)[:4000], published=_parse_date(clean_text(date))))
    return out


def parse_feed(xml_text: str, source: str) -> list[Deal]:
    """Parse RSS 2.0 or Atom into deals."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        try:
            root = ET.fromstring(_repair_xml(xml_text))
        except ET.ParseError:
            # Too broken for an XML parser: pull the items out directly.
            deals = _scan_feed(xml_text, source)
            if not deals:
                if re.search(r"<html|<!doctype html", xml_text[:2000], re.I):
                    raise ValueError("blocked: the site sent a web page instead of a feed") from None
                raise
            return deals
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

    def bing_news(self, query: str) -> list[Deal]:
        xml = self.http.get_text(BING_NEWS, {"q": query, "format": "rss", "qft": 'interval="8"'})
        return parse_feed(xml, "Bing News")

    def feed(self, url: str) -> list[Deal]:
        return parse_feed(self.http.get_text(url), feed_name(url))

    def jobs(self) -> list[tuple[str, object, str]]:
        return ([(f"Reddit: {q}", self.reddit, q) for q in self.cfg.reddit_queries]
                + [(f"Google News: {q}", self.google_news, q) for q in self.cfg.google_news_queries]
                + [(f"Bing News: {q}", self.bing_news, q) for q in self.cfg.bing_news_queries]
                + [(feed_name(u), self.feed, u) for u in self.cfg.rss_feeds])

    def fetch_all_with_status(self, workers: int = 6) -> tuple[list[Deal], list[SourceStatus]]:
        """Fetch every source in parallel. A broken source is reported, never fatal."""
        def run(job):
            label, fn, arg = job
            try:
                got = fn(arg)
                log.info("%s: %d posts", label, len(got))
                return got, SourceStatus(label, True, len(got))
            except Exception as e:
                log.warning("%s failed: %s", label, e)
                return [], SourceStatus(label, False, 0, str(e)[:200])

        with ThreadPoolExecutor(max_workers=workers) as pool:
            results = list(pool.map(run, self.jobs()))
        deals: dict[str, Deal] = {}
        seen_titles: set[str] = set()
        for got, _ in results:
            for d in got:
                key = title_key(d.title)
                if d.id in deals or (key and key in seen_titles):
                    continue        # same story from two places (e.g. Google and Bing News)
                deals[d.id] = d
                seen_titles.add(key)
        return list(deals.values()), [st for _, st in results]

    def fetch_all(self) -> list[Deal]:
        return self.fetch_all_with_status()[0]


def feed_name(url: str) -> str:
    host = url.split("/")[2] if "//" in url else url
    host = host.removeprefix("www.")
    if host == "slickdeals.net":
        q = re.search(r"[?&]q=([^&]+)", url)
        return f"Slickdeals: {q.group(1).replace('+', ' ')}" if q else "Slickdeals"
    return host


def title_key(title: str) -> str:
    # News titles often end with " - Publisher"; drop it so syndicated copies match.
    t = re.sub(r"\s+[-|–]\s+[^-|–]{2,40}$", "", title.lower())
    return re.sub(r"[^a-z0-9]+", "", t)[:80]
