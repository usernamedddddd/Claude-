from urllib.parse import parse_qs, urlparse

from fbmarket.config import SearchConfig
from fbmarket.scraper import _is_login_wall, search_url


def test_search_url_full():
    u = urlparse(search_url(SearchConfig(query="road bike", location="nyc", radius_km=40,
                                         min_price=100, max_price=599.9, days_since_listed=1)))
    assert u.path == "/marketplace/nyc/search/"
    q = parse_qs(u.query)
    assert q["query"] == ["road bike"] and q["minPrice"] == ["100"] and q["maxPrice"] == ["599"]
    assert q["daysSinceListed"] == ["1"] and q["radius"] == ["40"]
    assert q["sortBy"] == ["creation_time_descend"]


def test_search_url_minimal():
    u = urlparse(search_url(SearchConfig(query="desk", days_since_listed=None)))
    assert u.path == "/marketplace/search/"
    assert set(parse_qs(u.query)) == {"query", "sortBy", "exact"}


def test_login_wall_detection():
    assert _is_login_wall("https://www.facebook.com/login/?next=x")
    assert _is_login_wall("https://www.facebook.com/checkpoint/1501092823525282/")
    assert not _is_login_wall("https://www.facebook.com/marketplace/nyc/search/?query=x")
