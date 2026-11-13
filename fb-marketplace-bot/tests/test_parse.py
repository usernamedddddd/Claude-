import json

import pytest

from fbmarket.parse import (listing_from_card, listings_from_html, listings_from_json,
                            parse_json_payload, parse_price)


@pytest.mark.parametrize("text,expected", [
    ("$1,200", 1200), ("$45", 45), ("€12,50", 12.5), ("1.234,50 €", 1234.5),
    ("CA$300", 300), ("₹5,000", 5000), ("Free", 0), ("$1,200,000", 1_200_000),
    ("1 200 kr", 1200), ("$12.99", 12.99), ("", None), ("Contact seller", None),
])
def test_parse_price(text, expected):
    assert parse_price(text) == expected


def node(id_="123", title="Trek road bike", amount="350.00", fmt="$350", **extra):
    n = {
        "id": id_, "marketplace_listing_title": title,
        "listing_price": {"amount": amount, "formatted_amount": fmt},
        "location": {"reverse_geocode": {"city": "Brooklyn", "state": "NY"}},
        "primary_listing_photo": {"image": {"uri": "https://img/1.jpg"}},
    }
    n.update(extra)
    return n


def graphql_doc(*nodes):
    return {"data": {"marketplace_search": {"feed_units": {"edges": [
        {"node": {"listing": n}} for n in nodes]}}}}


def test_listings_from_json_finds_nested_nodes():
    out = listings_from_json(graphql_doc(node(), node("456", "Giant bike", "200", "$200")))
    by_id = {li.id: li for li in out}
    assert set(by_id) == {"123", "456"}
    li = by_id["123"]
    assert (li.title, li.price, li.price_text, li.location, li.image_url) == (
        "Trek road bike", 350.0, "$350", "Brooklyn, NY", "https://img/1.jpg")
    assert li.url == "https://www.facebook.com/marketplace/item/123/"


def test_listings_from_json_skips_sold_and_bad_ids():
    out = listings_from_json(graphql_doc(node(is_sold=True), node(id_="abc"), node("9")))
    assert [li.id for li in out] == ["9"]


def test_city_page_display_name_preferred_and_price_fallback():
    n = node(amount=None, fmt="$1,050")
    n["location"]["reverse_geocode"]["city_page"] = {"display_name": "New York, New York"}
    (li,) = listings_from_json(graphql_doc(n))
    assert li.price == 1050 and li.location == "New York, New York"


def test_parse_json_payload_handles_prefix_and_multiline():
    a, b = graphql_doc(node("1")), graphql_doc(node("2"))
    body = "for (;;);" + json.dumps(a) + "\n" + json.dumps(b) + "\n"
    docs = parse_json_payload(body)
    assert len(docs) == 2
    assert parse_json_payload("not json") == []


def test_listings_from_html_reads_script_blobs():
    html = ('<html><script type="application/json" data-sjs>' + json.dumps(graphql_doc(node("77")))
            + '</script><script type="application/json">{"other": 1}</script>'
            + '<script type="application/json">{broken marketplace_listing_title</script></html>')
    assert [li.id for li in listings_from_html(html)] == ["77"]


def test_listing_from_card_with_discount_line():
    li = listing_from_card("/marketplace/item/555/?ref=search", "$120\n$150\nIKEA desk\nQueens, NY", "https://i")
    assert (li.id, li.title, li.price, li.price_text, li.location, li.image_url) == (
        "555", "IKEA desk", 120, "$120", "Queens, NY", "https://i")


def test_listing_from_card_free_and_garbage():
    li = listing_from_card("https://www.facebook.com/marketplace/item/9/", "Free\nCouch\nBronx")
    assert li.price == 0 and li.title == "Couch"
    assert listing_from_card("/marketplace/category/x", "$5\nThing") is None
    assert listing_from_card("/marketplace/item/1/", "$5") is None
