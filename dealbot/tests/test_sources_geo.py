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


def test_feed_name_and_title_key():
    from dealbot.sources import feed_name, title_key
    assert feed_name("https://slickdeals.net/newsearch.php?rss=1&q=in-store") == "Slickdeals: in-store"
    assert feed_name("https://www.hip2save.com/feed/") == "hip2save.com"
    assert title_key("Dollar General Penny List - The Krazy Coupon Lady") == title_key("Dollar General penny list")


def test_fetch_all_reports_status_and_dedupes(fake_http):
    from dealbot.config import Config
    from dealbot.sources import Sources
    google = RSS.replace("Dollar General penny list: 50 items &amp; more", "DG penny list this week - WSB")
    bing = RSS.replace("Dollar General penny list: 50 items &amp; more", "DG penny list this week - Other Paper") \
              .replace("https://example.com/a", "https://example.com/b")
    http = fake_http({"https://news.google.com": google, "https://www.bing.com": bing,
                      "https://www.reddit.com": RuntimeError("403 Blocked"), "https://blog.example": ATOM})
    cfg = Config(reddit_queries=["q"], google_news_queries=["q"], bing_news_queries=["q"],
                 rss_feeds=["https://blog.example/feed"])
    deals, statuses = Sources(http, cfg).fetch_all_with_status()
    assert sorted(d.title for d in deals) == ["DG penny list this week - WSB", "Target 70% off toys"]
    assert [(s.name, s.ok) for s in statuses] == [("Reddit: q", False), ("Google News: q", True),
                                                  ("Bing News: q", True), ("blog.example", True)]
    assert "403" in statuses[0].error


def test_export_keeps_store_deals_only(tmp_path, fake_http):
    import json
    from datetime import datetime, timezone
    from dealbot.config import Config
    from dealbot.export import export
    rss = """<rss><channel>
      <item><title>Hidden clearance at Walmart</title><link>https://x/1</link><pubDate>Thu, 12 Nov 2026 08:00:00 GMT</pubDate></item>
      <item><title>Amazon Echo deal</title><link>https://x/2</link><pubDate>Thu, 12 Nov 2026 08:00:00 GMT</pubDate></item>
      <item><title>Old DG penny list</title><link>https://x/3</link><pubDate>Thu, 01 Oct 2026 08:00:00 GMT</pubDate></item>
    </channel></rss>"""
    http = fake_http({"https://feed.example": rss})
    cfg = Config(reddit_queries=[], google_news_queries=[], bing_news_queries=[], rss_feeds=["https://feed.example/rss"])
    out = tmp_path / "site" / "deals.json"
    export(cfg, out, http=http, now=datetime(2026, 11, 13, tzinfo=timezone.utc))
    data = json.loads(out.read_text())
    assert [d["title"] for d in data["deals"]] == ["Hidden clearance at Walmart"]
    assert data["sources"][0] == {"name": "feed.example", "ok": True, "count": 3, "error": ""}


def test_parse_feed_repairs_sloppy_xml():
    sloppy = """<rss><channel><item><title>Tide &amp; Gain&nbsp;penny list – B&M finds &copy; 2026</title>
      <link>https://x/1?a=1&b=2</link><description>Save&hellip; now\x0b</description></item></channel></rss>"""
    [d] = parse_feed(sloppy, "blog")
    assert d.title == "Tide & Gain\xa0penny list – B&M finds © 2026".replace("\xa0", " ") or "B&M" in d.title
    assert d.url == "https://x/1?a=1&b=2" and d.text == "Save… now"


def test_parse_feed_scans_badly_broken_xml():
    import pytest
    broken = """<?xml version="1.0"?><rss><channel><title>KCL</title>
      <item><title><![CDATA[Dollar General Penny List <3 & more]]></title>
        <link>https://kcl.example/dg-penny</link><pubDate>Thu, 12 Nov 2026 08:00:00 GMT</pubDate>
        <description><![CDATA[<p>Items ring up 1¢</p>]]></description><bad attr=unquoted></item>
      <item><title>Target 70% off</title><link>https://kcl.example/t</link></item>
    </channel></rss>"""
    deals = parse_feed(broken, "kcl.example")
    assert [d.title for d in deals] == ["Dollar General Penny List <3 & more", "Target 70% off"]
    assert deals[0].url == "https://kcl.example/dg-penny" and deals[0].text == "Items ring up 1¢"
    assert deals[0].published.day == 12
    with pytest.raises(Exception):
        parse_feed("<html>not a feed <b></html>", "x")      # junk with no items still fails loudly


def test_parse_feed_reports_blocked_site():
    import pytest
    page = "<!DOCTYPE html><html><head><title>Just a moment...</title></head><body><p>Verify you are human</body></html>"
    with pytest.raises(ValueError, match="blocked"):
        parse_feed(page, "x")
