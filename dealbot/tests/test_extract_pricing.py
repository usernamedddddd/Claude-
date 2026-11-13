from dealbot.chains import chain_for_osm, detect_chains
from dealbot.extract import enrich, find_prices, mentions_location
from dealbot.models import Deal, Location
from dealbot.pricing import decode_price

ALL = ["dollar_general", "home_depot", "walmart", "target", "costco", "lowes"]


def test_detect_chains():
    assert detect_chains("Found this at Dollar General today", ALL) == ["dollar_general"]
    assert detect_chains("DG penny list for 11/11", ALL) == ["dollar_general"]
    assert detect_chains("dg is lowercase noise", ALL) == []
    assert detect_chains("Home Depot and Lowes clearance", ALL) == ["home_depot", "lowes"]
    assert detect_chains("Walmart and Target", ["target"]) == ["target"]


def test_chain_for_osm():
    assert chain_for_osm({"brand": "The Home Depot"}, ALL) == "home_depot"
    assert chain_for_osm({"name": "Walmart Supercenter"}, ALL) == "walmart"
    assert chain_for_osm({"name": "Targeted Fitness"}, ALL) is None


def test_find_prices():
    assert find_prices("was $12.97 now $3.03, also 1¢ and $1,200") == [12.97, 3.03, 1200.0, 0.01]
    assert find_prices("no money here 12.03") == []


def test_decode_prices():
    assert decode_price("dollar_general", 0.01)[0].kind == "penny"
    assert decode_price("home_depot", 12.03)[0].kind == "final_markdown"
    assert decode_price("home_depot", 24.06)[0].kind == "markdown"
    assert decode_price("home_depot", 24.98) == []
    t = decode_price("target", 7.04)[0]
    assert t.est_pct_off == 70 and t.kind == "final_markdown"
    assert decode_price("target", 7.08)[0].est_pct_off == 30
    assert decode_price("target", 7.99)[0].kind == "regular"
    assert decode_price("costco", 9.97)[0].kind == "final_markdown"
    assert decode_price("walmart", 4.50)[0].kind == "clearance"
    assert decode_price("walmart", 4.97) == []


def test_mentions_location():
    loc = Location(36.1, -86.7, city="Nashville", state="Tennessee")
    assert mentions_location("found in nashville today", loc)
    assert mentions_location("Murfreesboro, TN store", loc)
    assert mentions_location("anyone in Tennessee?", loc)
    assert not mentions_location("TN is just letters here", loc)
    assert not mentions_location("Ohio finds", loc)


def test_enrich_penny():
    d = enrich(Deal("1", "DG penny list 11/11", "u", "r/x",
                    text="Christmas decor and Tide pods 037000123456 ring up 1¢"), ALL)
    assert d.kind == "penny"
    assert d.chains == ["dollar_general"]
    assert d.upcs == ["037000123456"]
    assert 0.01 in d.prices


def test_enrich_clearance_from_price_code():
    d = enrich(Deal("2", "Drill kit at Home Depot for $49.03", "u", "r/x"), ALL)
    assert d.kind == "clearance"
    assert any("final clearance" in n for n in d.price_notes)


def test_enrich_percent():
    d = enrich(Deal("3", "Target toys 70% off this week", "u", "r/x"), ALL)
    assert d.percent_off == 70 and d.kind == "clearance"
    d = enrich(Deal("4", "Walmart 20% off coffee", "u", "r/x"), ALL)
    assert d.kind == "sale"
