"""Turn the free text of a post or article into structured deal facts."""

from __future__ import annotations

import html
import re

from .chains import detect_chains
from .models import Deal, Location
from .pricing import decode_price

PRICE_RE = re.compile(r"(?<![\w.])\$\s?(\d{1,4}(?:,\d{3})*(?:\.\d{1,2})?)(?!\d)")
CENTS_RE = re.compile(r"(?<![\w.$])(\d{1,2})\s?(?:¢|cents?\b)", re.IGNORECASE)
PENNY_RE = re.compile(
    r"\bpenn(?:y|ies)\s*(?:list|item|items|find|finds|deal|deals|shopping|haul|day)\b"
    r"|\$0?\.01\b|(?<!\d)1\s?¢|\bone[\s-]cent\b|\bpenny(?:'d|ed)\b|\bwent to (?:a )?penny\b",
    re.IGNORECASE,
)
PCT_RE = re.compile(r"(\d{1,2}(?:\.\d)?)\s?%\s?off", re.IGNORECASE)
CLEARANCE_RE = re.compile(
    r"\bclearance\b|\bmark(?:ed)?\s*down\b|\bmarkdowns?\b|\bhidden clearance\b|\bliquidat\w+|\bclose[\s-]?out\b",
    re.IGNORECASE,
)
UPC_RE = re.compile(r"(?<!\d)(\d{12})(?!\d)")
TAG_RE = re.compile(r"<[^>]+>")

US_STATES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
    "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
    "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
    "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
    "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
    "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
    "DC": "District of Columbia",
}
STATE_ABBR = {v.lower(): k for k, v in US_STATES.items()}


# Product categories (keyword lists); a deal can be in several. Keep in step with web/logic.js.
CATEGORIES: list[tuple[str, str, str, list[str]]] = [
    ("holiday", "Holiday", "🎄", [r"christmas", r"xmas", r"halloween", r"thanksgiving", r"easter", r"valentine", r"valentines", r"holiday", r"ornaments?", r"wreaths?", r"inflatables?", r"seasonal", r"stocking stuffers?", r"gift sets?"]),
    ("toys", "Toys", "🧸", [r"toys?", r"lego", r"barbie", r"hot wheels", r"dolls?", r"puzzles?", r"nerf", r"play-?doh", r"board games?", r"plush", r"squishmallows?", r"action figures?"]),
    ("home", "Home", "🏠", [r"home decor", r"decor", r"kitchen", r"bedding", r"towels?", r"pillows?", r"curtains?", r"rugs?", r"candles?", r"furniture", r"cookware", r"dishes", r"storage", r"vases?", r"blankets?", r"mugs?", r"frames?"]),
    ("cleaning", "Cleaning", "🧼", [r"cleaning", r"cleaners?", r"detergent", r"tide", r"bleach", r"clorox", r"lysol", r"dish soap", r"paper towels?", r"toilet paper", r"trash bags?", r"dawn", r"swiffer", r"febreze", r"laundry"]),
    ("beauty", "Beauty", "💄", [r"beauty", r"makeup", r"cosmetics?", r"lipstick", r"mascara", r"skincare", r"skin care", r"lotion", r"shampoo", r"conditioner", r"nail polish", r"perfume", r"fragrance", r"body wash", r"deodorant", r"hair care"]),
    ("health", "Health", "💊", [r"vitamins?", r"medicine", r"pain relief", r"tylenol", r"advil", r"first aid", r"toothpaste", r"toothbrush(es)?", r"razors?", r"allergy", r"cold & flu", r"supplements?"]),
    ("food", "Food", "🍫", [r"groceries?", r"snacks?", r"candy", r"chocolate", r"cereal", r"coffee", r"soda", r"drinks?", r"chips", r"cookies", r"pasta", r"frozen food"]),
    ("baby", "Baby", "👶", [r"baby", r"diapers?", r"wipes", r"formula", r"toddlers?", r"infant", r"pampers", r"huggies"]),
    ("pet", "Pet", "🐶", [r"pets?", r"dogs?", r"cats?", r"puppy", r"kitten", r"litter", r"pet treats?", r"dog food", r"cat food"]),
    ("clothing", "Clothing", "👕", [r"clothing", r"clothes", r"shirts?", r"shoes", r"socks", r"jackets?", r"jeans", r"apparel", r"pajamas?", r"hoodies?", r"dresses", r"boots"]),
    ("electronics", "Electronics", "🔌", [r"electronics", r"tvs?", r"headphones", r"earbuds", r"chargers?", r"phones?", r"tablets?", r"laptops?", r"speakers?", r"bluetooth", r"batteries", r"airpods", r"smart watch", r"video games?", r"nintendo", r"playstation", r"xbox"]),
    ("tools", "Tools & Garden", "🔨", [r"tools?", r"drills?", r"saws?", r"wrench(es)?", r"dewalt", r"milwaukee", r"ryobi", r"craftsman", r"hardware", r"ladders?", r"lumber", r"paint", r"garden", r"lawn", r"mowers?", r"plants?", r"light bulbs?", r"outdoor"]),
]
_CATEGORY_RES = [(key, re.compile(r"\b(?:" + "|".join(words) + r")\b", re.IGNORECASE))
                 for key, _label, _icon, words in CATEGORIES]
CATEGORY_KEYS = [c[0] for c in CATEGORIES]


def categorize(text: str) -> list[str]:
    return [key for key, rx in _CATEGORY_RES if rx.search(text)]


def clean_text(raw: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(TAG_RE.sub(" ", raw or ""))).strip()


def find_prices(text: str) -> list[float]:
    prices = [float(m.replace(",", "")) for m in PRICE_RE.findall(text)]
    prices += [int(c) / 100 for c in CENTS_RE.findall(text)]
    seen, out = set(), []
    for p in prices:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def mentions_location(text: str, loc: Location | None) -> bool:
    """True if the text names the user's city or state (e.g. "Nashville", "Tennessee", ", TN")."""
    if not loc:
        return False
    if loc.city and re.search(rf"\b{re.escape(loc.city)}\b", text, re.IGNORECASE):
        return True
    if loc.state:
        if re.search(rf"\b{re.escape(loc.state)}\b", text, re.IGNORECASE):
            return True
        abbr = STATE_ABBR.get(loc.state.lower())
        # Only match abbreviations in address-like form (", TN" or "TN 37201") to avoid "OR"/"IN" noise.
        if abbr and re.search(rf",\s*{abbr}\b|\b{abbr}\s+\d{{5}}\b", text):
            return True
    return False


def enrich(deal: Deal, enabled_chains: list[str], loc: Location | None = None) -> Deal:
    """Fill in chains, kind, prices, % off, UPCs and price-tag hints from the deal's text."""
    blob = f"{deal.title} {deal.text}"
    deal.chains = detect_chains(blob, enabled_chains)
    deal.prices = find_prices(blob)
    pcts = [float(p) for p in PCT_RE.findall(blob) if 0 < float(p) < 100]
    deal.percent_off = max(pcts) if pcts else None
    deal.upcs = sorted(set(UPC_RE.findall(blob)))
    deal.local_mention = mentions_location(blob, loc)
    deal.categories = categorize(blob)

    notes, strongest = [], 0
    for chain in deal.chains:
        for price in deal.prices:
            for sig in decode_price(chain, price):
                if sig.kind == "regular":
                    continue
                notes.append(f"${price:.2f} at {chain}: {sig.note}")
                strongest = max(strongest, sig.strength)
    deal.price_notes = notes

    if PENNY_RE.search(blob) or 0.01 in deal.prices:
        deal.kind = "penny"
    elif CLEARANCE_RE.search(blob) or (deal.percent_off or 0) >= 50 or strongest >= 2:
        deal.kind = "clearance"
    elif deal.percent_off or notes:
        deal.kind = "sale"
    else:
        deal.kind = "other"
    return deal
