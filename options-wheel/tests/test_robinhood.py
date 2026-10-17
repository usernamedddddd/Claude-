"""RobinhoodBroker against a fake robin_stocks module (response shapes from the real API)."""

from datetime import date
from types import SimpleNamespace

from wheelbot.broker import RobinhoodBroker
from wheelbot.models import ShortOption

INST = {"id": "i45", "url": "https://api.robinhood.com/options/instruments/i45/", "chain_symbol": "ABC",
        "type": "put", "strike_price": "45.0000", "expiration_date": "2026-11-20", "tradability": "tradable",
        "min_ticks": {"above_tick": "0.05", "below_tick": "0.01", "cutoff_price": "3.00"}}
FAR = {**INST, "id": "i10", "url": "https://api.robinhood.com/options/instruments/i10/", "strike_price": "10.0000"}
MD = {"instrument": INST["url"], "bid_price": "0.60", "ask_price": "0.64", "delta": "-0.2512",
      "implied_volatility": "0.41", "open_interest": 812, "volume": 33}


def fake_rh(order_states):
    calls = SimpleNamespace(orders=[], cancelled=[], md_requests=[])
    states = iter(order_states)

    def request_get(url, data_type, payload):
        calls.md_requests.append(payload["instruments"])
        return [MD]

    def order_info(order_id):
        state = next(states, "cancelled")
        return {"id": order_id, "state": state, "price": "0.62",
                "processed_quantity": "1.00000" if state == "filled" else "0.00000"}

    rh = SimpleNamespace(
        urls=SimpleNamespace(marketdata_options_url=lambda: "https://api.robinhood.com/marketdata/options/"),
        helper=SimpleNamespace(request_get=request_get),
        stocks=SimpleNamespace(get_latest_price=lambda s, includeExtendedHours: ["50.1200"],
                               get_symbol_by_url=lambda url: "ABC",
                               get_earnings=lambda s: [{"report": {"date": "2026-07-30"}},
                                                       {"report": {"date": "2027-01-28"}}, {"report": None}]),
        options=SimpleNamespace(
            get_chains=lambda s: {"expiration_dates": ["2026-11-20", "2026-10-23"]},
            find_tradable_options=lambda s, exp, optionType: [INST, FAR],
            get_option_instrument_data_by_id=lambda i: INST,
            get_option_market_data_by_id=lambda i: [MD],
            get_open_option_positions=lambda account_number: [
                {"chain_symbol": "ABC", "type": "short", "quantity": "2.0000", "average_price": "-61.0000",
                 "option_id": "i45"},
                {"chain_symbol": "ABC", "type": "long", "quantity": "1.0000", "average_price": "20.0000",
                 "option_id": "i45"}]),
        account=SimpleNamespace(get_open_stock_positions=lambda account_number: [
            {"instrument": "u", "quantity": "100.00000", "average_buy_price": "44.5000"}]),
        profiles=SimpleNamespace(load_account_profile=lambda account_number: {
            "buying_power": "25000.00", "cash_available_for_withdrawal": "3200.50"}),
        markets=SimpleNamespace(get_market_today_hours=lambda m: {
            "is_open": True, "opens_at": "2026-10-14T13:30:00Z", "closes_at": "2026-10-14T20:00:00Z"}),
        orders=SimpleNamespace(
            order_sell_option_limit=lambda *a, **kw: calls.orders.append((a, kw)) or {"id": "o1", "state": "queued"},
            order_buy_option_limit=lambda *a, **kw: calls.orders.append((a, kw)) or {"detail": "not enough"},
            get_option_order_info=order_info,
            cancel_option_order=lambda i: calls.cancelled.append(i)),
    )
    return rh, calls


def test_market_data_parsing():
    rh, calls = fake_rh([])
    b = RobinhoodBroker(rh, sleep=lambda s: None)
    assert b.underlying_price("ABC") == 50.12
    assert b.expirations("ABC") == [date(2026, 10, 23), date(2026, 11, 20)]
    assert b.next_earnings("ABC", date(2026, 10, 14)) == date(2027, 1, 28)
    assert b.market_hours()[0].hour == 13

    [q] = b.option_quotes("ABC", date(2026, 11, 20), "put", 50.12)   # the $10 strike is out of band
    assert calls.md_requests == [INST["url"]]
    assert (q.strike, q.bid, q.ask, q.delta, q.open_interest, q.tick_above) == (45.0, 0.60, 0.64, -0.2512, 812, 0.05)


def test_account_parsing_ignores_long_options_and_margin():
    rh, _ = fake_rh([])
    acct = RobinhoodBroker(rh).account()
    assert acct.cash == 3200.50                      # not the $25k margin buying power
    assert acct.stocks["ABC"].quantity == 100 and acct.stocks["ABC"].avg_cost == 44.5
    [o] = acct.short_options
    assert (o.option_type, o.strike, o.quantity, o.avg_credit) == ("put", 45.0, 2, 0.61)


def test_orders_fill_cancel_and_reject():
    rh, calls = fake_rh(["queued", "confirmed", "filled"])
    b = RobinhoodBroker(rh, order_timeout_s=60, sleep=lambda s: None)
    q = b.option_quotes("ABC", date(2026, 11, 20), "put", 50.0)[0]
    res = b.sell_to_open(q, 1, 0.62)
    assert res.filled and res.filled_quantity == 1
    args, kw = calls.orders[0]
    assert args == ("open", "credit", 0.62, "ABC", 1, "2026-11-20", 45.0)
    assert kw["optionType"] == "put" and kw["timeInForce"] == "gfd"

    rh, calls = fake_rh(["queued"] * 3)
    b = RobinhoodBroker(rh, order_timeout_s=0, sleep=lambda s: None)
    res = b.sell_to_open(q, 1, 0.62)
    assert not res.filled and calls.cancelled == ["o1"]

    pos = ShortOption("ABC", "put", 45.0, date(2026, 11, 20), 1, 0.61, "i45")
    try:
        b.buy_to_close(pos, q, 1, 0.30)
        raise AssertionError("expected rejection")
    except RuntimeError as e:
        assert "rejected" in str(e)
