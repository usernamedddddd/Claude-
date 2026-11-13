from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Location:
    lat: float
    lon: float
    label: str = ""
    city: str = ""
    state: str = ""       # full state name, e.g. "Tennessee"


@dataclass
class Store:
    chain: str
    name: str
    lat: float
    lon: float
    address: str = ""
    distance_miles: float = 0.0


@dataclass
class Deal:
    id: str
    title: str
    url: str
    source: str
    text: str = ""
    published: datetime | None = None
    chains: list[str] = field(default_factory=list)
    kind: str = "other"                  # penny | clearance | sale | other
    prices: list[float] = field(default_factory=list)
    percent_off: float | None = None
    upcs: list[str] = field(default_factory=list)
    price_notes: list[str] = field(default_factory=list)
    categories: list[str] = field(default_factory=list)
    local_mention: bool = False
    nearest_store: Store | None = None
    score: float = 0.0
