"""Plain data types shared by the scraper, filters, store and notifiers."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Listing:
    id: str
    title: str
    price: float | None          # None when the price couldn't be read
    price_text: str              # as shown on Facebook, e.g. "$1,200" or "Free"
    location: str = ""
    image_url: str | None = None
    search: str = ""             # name of the search that found it

    @property
    def url(self) -> str:
        return f"https://www.facebook.com/marketplace/item/{self.id}/"


@dataclass
class Alert:
    listing: Listing
    kind: str                    # "new" or "price_drop"
    old_price: float | None = None
