from dealbot.geo import geocode, haversine_miles, overpass_query, parse_overpass
from dealbot.models import Location
from dealbot.sources import parse_feed, parse_reddit

RSS = """<?xml version="1.0"?><rss version="2.0"><channel>
<item><title>Dollar General penny list: 50 items &amp; more</title>
<link>https://example.com/a</link><pubDate>Tue, 10 Nov 2026 08:00:00 GMT</pubDate>
<description>&lt;p&gt;Items going to 1&#162;&lt;/p&gt;</description>
<source url="https://example.com">Example News</source></item>
</channel></rss>"""

ATOM = """<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>Target 70% off toys</title><link href="https://blog.example/t"/>
<updated>2026-11-12T10:00:00Z</updated><summary>Clearance endcaps</summary></entry></feed>"""


def test_parse_rss():
    [d] = parse_feed(RSS, "feed")
    assert d.title == "Dollar General penny list: 50 items & more"
    assert d.source == "Example News"
    assert "1¢" in d.text
    assert d.published.day == 10


def test_parse_atom():
    [d] = parse_feed(ATOM, "blog.example")
    assert d.url == "https://blog.example/t" and d.published.hour == 10


def test_parse_reddit():
    payload = {"data": {"children": [
        {"data": {"id": "abc", "title": "HD penny finds", "selftext": "pic", "permalink": "/r/x/abc",
                  "subreddit": "x", "created_utc": 1794700000}},
        {"data": {"id": "nsfw", "title": "t", "over_18": True}},
    ]}}
    [d] = parse_reddit(payload)
    assert d.id == "reddit:abc" and d.url == "https://www.reddit.com/r/x/abc" and d.source == "r/x"


def test_haversine():
    # Nashville -> Memphis is about 197 miles as the crow flies
    assert 190 < haversine_miles(36.1627, -86.7816, 35.1495, -90.0490) < 205


def test_geocode_zip(fake_http):
    http = fake_http({"https://nominatim": [{"lat": "36.16", "lon": "-86.78", "display_name": "Nashville",
                                            "address": {"city": "Nashville", "state": "Tennessee"}}]})
    loc = geocode(http, "37201")
    assert loc.city == "Nashville" and loc.state == "Tennessee"
    assert http.sent[0][2]["postalcode"] == "37201"


def test_overpass_query_and_parse():
    q = overpass_query(36.16, -86.78, 5, ["dollar_general", "lowes"])
    assert "around:8046,36.16,-86.78" in q and "Dollar General" in q and "Lowe'?s" in q
    origin = Location(36.16, -86.78)
    payload = {"elements": [
        {"type": "node", "lat": 36.17, "lon": -86.78, "tags": {"shop": "variety_store", "brand": "Dollar General",
                                                                "addr:housenumber": "12", "addr:street": "Main St"}},
        {"type": "way", "center": {"lat": 36.20, "lon": -86.78}, "tags": {"shop": "doityourself", "name": "Lowe's"}},
        {"type": "node", "lat": 36.17, "lon": -86.78, "tags": {"shop": "x", "name": "Bob's Hardware"}},
    ]}
    stores = parse_overpass(payload, origin, ["dollar_general", "lowes"])
    assert [s.chain for s in stores] == ["dollar_general", "lowes"]
    assert stores[0].address == "12 Main St"
    assert stores[0].distance_miles < stores[1].distance_miles
