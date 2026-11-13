import pytest

from fbmarket.config import SearchConfig, parse_config
from fbmarket.filters import check, matches
from fbmarket.models import Listing


def li(title="Trek road bike 56cm", price=300.0):
    return Listing(id="1", title=title, price=price, price_text=f"${price}")


def test_price_bounds():
    s = SearchConfig(query="bike", min_price=100, max_price=500)
    assert matches(li(price=300), s)
    assert check(li(price=50), s) == (False, "price 50 < min 100")
    assert not matches(li(price=900), s)


def test_unknown_price_policy():
    assert not matches(li(price=None), SearchConfig(query="x"))
    assert matches(li(price=None), SearchConfig(query="x", allow_unknown_price=True))


def test_keywords_whole_word_case_insensitive():
    s = SearchConfig(query="tv", must_include=["tv"], exclude=["stand"])
    assert matches(li('Samsung 55" TV'), s)
    assert not matches(li("TV stand oak"), s)
    assert not matches(li("tvstand"), s)          # whole words only
    s2 = SearchConfig(query="tv", include_any=['55"', "65in"])
    assert matches(li('Sony 55" 4k'), s2)
    assert not matches(li("Sony 43in"), s2)
    assert not matches(li("Kids bike"), SearchConfig(query="b", exclude=["kids"]))
    assert matches(li("Kidsize"), SearchConfig(query="b", exclude=["kids"]))


def test_parse_config_defaults_and_coercion():
    cfg = parse_config({"searches": [{"query": "4k tv", "include_any": [55, "65in"], "exclude": "mount"}]})
    s = cfg.searches[0]
    assert s.name == "4k tv" and s.include_any == ["55", "65in"] and s.exclude == ["mount"]
    assert cfg.poll_minutes == 10 and cfg.browser.headless


@pytest.mark.parametrize("data,msg", [
    ({"searches": []}, "at least one"),
    ({"searches": [{"query": ""}]}, "query"),
    ({"poll_minutes": 1, "searches": [{"query": "a"}]}, "at least 5"),
    ({"searches": [{"query": "a"}, {"query": "a"}]}, "Duplicate"),
    ({"searches": [{"query": "a", "min_price": 9, "max_price": 1}]}, "min_price"),
    ({"searches": [{"query": "a", "days_since_listed": 3}]}, "days_since_listed"),
    ({"searches": [{"query": "a", "colour": "red"}]}, "searches[0].colour"),
    ({"browser": {"nope": 1}, "searches": [{"query": "a"}]}, "browser.nope"),
    ({"notify": {"ntfy": {"enabled": True}}, "searches": [{"query": "a"}]}, "topic"),
])
def test_config_validation(data, msg):
    with pytest.raises(ValueError, match=msg.replace("[", r"\[").replace("]", r"\]")):
        parse_config(data)


def test_example_config_loads():
    from pathlib import Path
    from fbmarket.config import load_config
    cfg = load_config(Path(__file__).parent.parent / "config.example.yaml")
    assert [s.name for s in cfg.searches] == ["road bike", "cheap 4k tv"]
