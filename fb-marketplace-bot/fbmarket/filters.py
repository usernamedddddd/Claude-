"""Decide whether a listing matches a search. Facebook's own filters are loose, so we re-check."""

from __future__ import annotations

import re

from .config import SearchConfig
from .models import Listing


def _has(term: str, text: str) -> bool:
    # Whole-word match, case-insensitive; "tv" doesn't match "tvstand" but "4k tv" works.
    return re.search(r"(?<!\w)" + re.escape(term.lower()) + r"(?!\w)", text) is not None


def check(listing: Listing, search: SearchConfig) -> tuple[bool, str]:
    """Return (matches, reason). The reason explains a rejection, for `fbmarket check -v`."""
    title = listing.title.lower()
    if listing.price is None:
        if not search.allow_unknown_price:
            return False, "price unreadable"
    else:
        if search.min_price is not None and listing.price < search.min_price:
            return False, f"price {listing.price:g} < min {search.min_price:g}"
        if search.max_price is not None and listing.price > search.max_price:
            return False, f"price {listing.price:g} > max {search.max_price:g}"
    for term in search.exclude:
        if _has(term, title):
            return False, f"excluded word {term!r}"
    for term in search.must_include:
        if not _has(term, title):
            return False, f"missing required word {term!r}"
    if search.include_any and not any(_has(t, title) for t in search.include_any):
        return False, "none of include_any present"
    return True, "ok"


def matches(listing: Listing, search: SearchConfig) -> bool:
    return check(listing, search)[0]
