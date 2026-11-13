"""Where you are and which stores are near you, using OpenStreetMap (free, no API key)."""

from __future__ import annotations

import math

from .chains import CHAINS, chain_for_osm
from .http import Http
from .models import Location, Store

NOMINATIM = "https://nominatim.openstreetmap.org/search"
OVERPASS = "https://overpass-api.de/api/interpreter"
METERS_PER_MILE = 1609.344


def haversine_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 3958.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def geocode(http: Http, query: str) -> Location:
    """Address, city or ZIP code → coordinates (OpenStreetMap Nominatim)."""
    params = {"format": "jsonv2", "limit": 1, "addressdetails": 1, "countrycodes": "us"}
    if query.strip().isdigit() and len(query.strip()) == 5:
        params["postalcode"] = query.strip()
    else:
        params["q"] = query
    results = http.get_json(NOMINATIM, params)
    if not results:
        raise ValueError(f"Couldn't find a location for {query!r}. Try 'City, State' or a ZIP code.")
    r = results[0]
    addr = r.get("address") or {}
    city = addr.get("city") or addr.get("town") or addr.get("village") or addr.get("hamlet") or ""
    return Location(float(r["lat"]), float(r["lon"]), r.get("display_name", query), city, addr.get("state", ""))


def overpass_query(lat: float, lon: float, radius_miles: float, chains: list[str]) -> str:
    names = sorted({n for k in chains if k in CHAINS for n in CHAINS[k].osm_names})
    alt = "|".join(n.replace("'", "'?") for n in names)
    radius = int(radius_miles * METERS_PER_MILE)
    return (
        "[out:json][timeout:25];("
        f'nwr["shop"]["brand"~"^({alt})$",i](around:{radius},{lat},{lon});'
        f'nwr["shop"]["name"~"^({alt})",i](around:{radius},{lat},{lon});'
        ");out center tags;"
    )


def parse_overpass(payload: dict, origin: Location, chains: list[str]) -> list[Store]:
    stores: dict[str, Store] = {}
    for el in payload.get("elements", []):
        tags = el.get("tags") or {}
        chain = chain_for_osm(tags, chains)
        if not chain:
            continue
        lat = el.get("lat") or (el.get("center") or {}).get("lat")
        lon = el.get("lon") or (el.get("center") or {}).get("lon")
        if lat is None or lon is None:
            continue
        street = " ".join(x for x in (tags.get("addr:housenumber"), tags.get("addr:street")) if x)
        address = ", ".join(x for x in (street, tags.get("addr:city")) if x)
        key = f"{chain}:{round(lat, 4)}:{round(lon, 4)}"
        stores[key] = Store(chain, tags.get("name") or CHAINS[chain].display, lat, lon, address,
                            haversine_miles(origin.lat, origin.lon, lat, lon))
    return sorted(stores.values(), key=lambda s: s.distance_miles)


def find_stores(http: Http, origin: Location, radius_miles: float, chains: list[str]) -> list[Store]:
    payload = http.post_form(OVERPASS, {"data": overpass_query(origin.lat, origin.lon, radius_miles, chains)})
    return parse_overpass(payload, origin, chains)
