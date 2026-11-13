"""Decode clearance price tags.

Many chains encode markdown stages in the cents of a price. These rules are
widely shared by deal hunters, but they are not official and stores change them,
so treat every result as a hint to go check, not a promise.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PriceSignal:
    kind: str            # "penny" | "final_markdown" | "clearance" | "markdown" | "regular"
    note: str
    est_pct_off: float | None = None
    strength: int = 0    # 0-3, how strongly this suggests a great deal


def _cents(price: float) -> int:
    return round(price * 100) % 100


def decode_price(chain: str, price: float) -> list[PriceSignal]:
    if price <= 0:
        return []
    if round(price * 100) == 1:
        return [PriceSignal("penny", "Rings up at $0.01: a penny item.", 99.9, 3)]

    c = _cents(price)
    last = c % 10
    out: list[PriceSignal] = []

    if chain == "home_depot":
        if last == 3:
            out.append(PriceSignal("final_markdown", "Ends in 3: final clearance markdown. "
                                   "Often the last price before it goes to a penny.", None, 2))
        elif last == 6:
            out.append(PriceSignal("markdown", "Ends in 6: first clearance markdown; "
                                   "expect another drop to a price ending in 3.", None, 1))
    elif chain == "target":
        pct = {8: 30, 6: 50, 4: 70}.get(last)
        if pct:
            out.append(PriceSignal("final_markdown" if pct == 70 else "clearance",
                                   f"Ends in {last}: about {pct}% off clearance."
                                   + (" Usually the final markdown." if pct == 70 else ""), pct, 2 if pct >= 50 else 1))
        elif last == 9:
            out.append(PriceSignal("regular", "Ends in 9: regular price."))
    elif chain == "walmart":
        if last == 0 and c != 0:
            out.append(PriceSignal("clearance", "Ends in 0: probably clearance (rollbacks don't).", None, 1))
        elif c == 0 and price < 10:
            out.append(PriceSignal("clearance", "Whole-dollar price under $10: possible clearance.", None, 1))
    elif chain == "costco":
        if c == 97:
            out.append(PriceSignal("final_markdown", "Ends in .97: clearance markdown; check for an asterisk "
                                   "on the tag, which means discontinued.", None, 2))
        elif c in (0, 88):
            out.append(PriceSignal("markdown", f"Ends in .{c:02d}: manager markdown on this store's stock.", None, 2))
        elif c == 49 or c == 79:
            out.append(PriceSignal("markdown", f"Ends in .{c}: manufacturer deal price.", None, 1))
    elif chain == "lowes":
        if last == 0 and c != 0:
            out.append(PriceSignal("clearance", "Ends in 0 on a yellow tag: probably clearance.", None, 1))
    return out


TIPS: dict[str, list[str]] = {
    "dollar_general": [
        "The community penny list usually takes effect early Tuesday morning; stores pull the items that day.",
        "Penny items aren't tagged. Scan barcodes in the DG app or at a price checker to confirm $0.01.",
        "Stores may refuse to sell penny items. Ask politely and accept a no.",
    ],
    "home_depot": [
        "Clearance prices ending in .06 drop to .03, then to $0.01, which means the item gets pulled.",
        "The Home Depot app's in-store price can be lower than the shelf tag. Scan first.",
    ],
    "target": [
        "Clearance stickers usually step 30% → 50% → 70% off, shown by prices ending in 8, 6, 4.",
        "Each department marks down on its own weekday; ask a team member which day yours is.",
    ],
    "walmart": [
        "Clearance prices often end in 0. The yellow tag's date shows when it was marked down.",
        "Scan items in the Walmart app; hidden clearance often rings up below the shelf price.",
    ],
    "costco": [
        "Prices ending .97 are clearance. An asterisk (*) in the tag's corner means it won't be restocked.",
        "Prices ending .00 or .88 are manager markdowns at that one warehouse.",
    ],
}
