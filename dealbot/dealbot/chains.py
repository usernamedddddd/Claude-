"""Store chains the bot knows about, and how to spot them in text and in map data."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Chain:
    key: str
    display: str
    aliases: tuple[str, ...]      # regexes matched case-insensitively against deal text
    osm_names: tuple[str, ...]    # brand/name values used in OpenStreetMap


CHAINS: dict[str, Chain] = {c.key: c for c in [
    Chain("dollar_general", "Dollar General", (r"dollar\s*general", r"\bDG\b(?!\s*\d)"), ("Dollar General",)),
    Chain("home_depot", "Home Depot", (r"home\s*depot", r"\bTHD\b"), ("The Home Depot", "Home Depot")),
    Chain("walmart", "Walmart", (r"wal-?\s?mart",), ("Walmart", "Walmart Supercenter", "Walmart Neighborhood Market")),
    Chain("target", "Target", (r"\btarget\b",), ("Target",)),
    Chain("costco", "Costco", (r"costco",), ("Costco", "Costco Wholesale")),
    Chain("lowes", "Lowe's", (r"\blowe'?s\b",), ("Lowe's", "Lowe's Home Improvement")),
    Chain("family_dollar", "Family Dollar", (r"family\s*dollar",), ("Family Dollar",)),
    Chain("dollar_tree", "Dollar Tree", (r"dollar\s*tree",), ("Dollar Tree",)),
    Chain("cvs", "CVS", (r"\bcvs\b",), ("CVS Pharmacy", "CVS")),
    Chain("walgreens", "Walgreens", (r"walgreens",), ("Walgreens",)),
]}

# "DG" must stay case-sensitive (upper case), everything else is case-insensitive.
_CASE_SENSITIVE = {r"\bDG\b(?!\s*\d)", r"\bTHD\b"}
_PATTERNS = {
    key: [re.compile(a, 0 if a in _CASE_SENSITIVE else re.IGNORECASE) for a in chain.aliases]
    for key, chain in CHAINS.items()
}


def detect_chains(text: str, enabled: list[str] | None = None) -> list[str]:
    """Chain keys mentioned in `text`, in CHAINS order."""
    keys = enabled or list(CHAINS)
    return [k for k in keys if k in _PATTERNS and any(p.search(text) for p in _PATTERNS[k])]


def chain_for_osm(tags: dict[str, str], enabled: list[str]) -> str | None:
    """Which enabled chain an OpenStreetMap element belongs to, if any."""
    for field in ("brand", "name", "operator"):
        value = (tags.get(field) or "").strip().lower()
        if not value:
            continue
        for key in enabled:
            chain = CHAINS.get(key)
            if chain and any(value == n.lower() or value.startswith(n.lower() + " ") for n in chain.osm_names):
                return key
    return None


def display(key: str) -> str:
    return CHAINS[key].display if key in CHAINS else key
