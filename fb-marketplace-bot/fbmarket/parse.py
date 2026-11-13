"""Turn Facebook's page data into Listing objects.

Marketplace ships listing data two ways, and the scraper reads both:

1. JSON: the first results are embedded in <script type="application/json"> tags, and
   results loaded on scroll arrive as GraphQL responses. Listing objects inside carry
   `marketplace_listing_title`, which we find by walking the whole tree, so this keeps
   working when Facebook reshuffles the surrounding structure.
2. DOM: each result card is an <a href="/marketplace/item/<id>/"> whose visible text is
   price line(s), then title, then location. This is the fallback.
"""

from __future__ import annotations

import json
import re
from typing import Any, Iterator

from .models import Listing

ITEM_ID_RE = re.compile(r"/marketplace/item/(\d+)")
_SCRIPT_RE = re.compile(r'<script type="application/json"[^>]*>(.*?)</script>', re.S)
_NUMBER_RE = re.compile(r"\d[\d.,\s  ]*")
_FREE_WORDS = {"free", "gratis", "gratuit", "kostenlos", "gratuito"}


def parse_price(text: str | None) -> float | None:
    """Read an amount from a price label: "$1,200" → 1200, "1.234,50 €" → 1234.5, "Free" → 0."""
    if not text:
        return None
    t = text.strip()
    if t.lower() in _FREE_WORDS:
        return 0.0
    m = _NUMBER_RE.search(t)
    if not m:
        return None
    num = re.sub(r"[\s  ]", "", m.group()).rstrip(".,")
    if "," in num and "." in num:
        # Whichever separator comes last is the decimal point.
        if num.rfind(",") > num.rfind("."):
            num = num.replace(".", "").replace(",", ".")
        else:
            num = num.replace(",", "")
    elif "," in num or "." in num:
        sep = "," if "," in num else "."
        head, _, tail = num.rpartition(sep)
        if len(tail) == 3 or num.count(sep) > 1:
            num = num.replace(sep, "")          # thousands separator: 1,200 / 1.200.000
        else:
            num = head.replace(sep, "") + "." + tail  # decimal: 12,50 / 12.5
    try:
        return float(num)
    except ValueError:
        return None


def _looks_like_price(line: str) -> bool:
    if line.strip().lower() in _FREE_WORDS:
        return True
    # A short line holding a number plus a currency mark: "$120", "€45", "CA$300", "1.200 kr".
    return (
        len(line) <= 20
        and bool(re.search(r"\d", line))
        and bool(re.search(r"[$€£¥₹₩₱₦₪฿₫]|\b(kr|zł|R|Rs|RM|Kč|Ft|lei|CHF|AED|SAR)\b", line))
    )


def _dig(obj: Any, *path: str) -> Any:
    for key in path:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(key)
    return obj


def _walk(obj: Any) -> Iterator[dict[str, Any]]:
    stack = [obj]
    while stack:
        cur = stack.pop()
        if isinstance(cur, dict):
            yield cur
            stack.extend(cur.values())
        elif isinstance(cur, list):
            stack.extend(cur)


def _listing_from_node(node: dict[str, Any]) -> Listing | None:
    lid = str(node.get("id") or "")
    title = node.get("marketplace_listing_title")
    if not lid.isdigit() or not isinstance(title, str):
        return None
    if node.get("is_sold") or node.get("is_pending") or node.get("is_hidden"):
        return None
    price_obj = node.get("listing_price") or {}
    price_text = price_obj.get("formatted_amount") or ""
    price: float | None
    try:
        price = float(price_obj["amount"])
    except (KeyError, TypeError, ValueError):
        price = parse_price(price_text)
    geo = _dig(node, "location", "reverse_geocode") or {}
    location = _dig(geo, "city_page", "display_name") or ", ".join(
        p for p in (geo.get("city"), geo.get("state")) if p
    )
    image = _dig(node, "primary_listing_photo", "image", "uri") or _dig(
        node, "primary_listing_photo", "listing_image", "uri"
    )
    return Listing(id=lid, title=title.strip(), price=price, price_text=price_text,
                   location=location or "", image_url=image)


def listings_from_json(obj: Any) -> list[Listing]:
    found: dict[str, Listing] = {}
    for node in _walk(obj):
        if "marketplace_listing_title" in node:
            listing = _listing_from_node(node)
            if listing and listing.id not in found:
                found[listing.id] = listing
    return list(found.values())


def parse_json_payload(text: str) -> list[Any]:
    """Parse a GraphQL response body: may start with `for (;;);` and hold one JSON doc per line."""
    text = text.removeprefix("for (;;);").strip()
    try:
        return [json.loads(text)]
    except ValueError:
        pass
    docs = []
    for line in text.splitlines():
        line = line.strip()
        if line:
            try:
                docs.append(json.loads(line))
            except ValueError:
                continue
    return docs


def listings_from_html(html: str) -> list[Listing]:
    found: dict[str, Listing] = {}
    for blob in _SCRIPT_RE.findall(html):
        if "marketplace_listing_title" not in blob:
            continue
        try:
            data = json.loads(blob)
        except ValueError:
            continue
        for listing in listings_from_json(data):
            found.setdefault(listing.id, listing)
    return list(found.values())


def listing_from_card(href: str, text: str, image_url: str | None = None) -> Listing | None:
    """Parse one result card's link and visible text (the DOM fallback)."""
    m = ITEM_ID_RE.search(href or "")
    if not m:
        return None
    lines = [ln.strip() for ln in (text or "").splitlines() if ln.strip()]
    prices = []
    while lines and _looks_like_price(lines[0]):
        prices.append(lines.pop(0))       # current price, then the struck-out old price if any
    if not lines:
        return None
    price_text = prices[0] if prices else ""
    return Listing(
        id=m.group(1),
        title=lines[0],
        price=parse_price(price_text),
        price_text=price_text,
        location=lines[1] if len(lines) > 1 else "",
        image_url=image_url or None,
    )
