from datetime import timedelta

from wheelbot.config import ContractRules, ManageConfig
from wheelbot.strategy import (buy_price, close_signal, contract_rejection, pick_contract, pick_expiration,
                               round_to_tick, sell_price)

from .conftest import EXP, TODAY, make_quote, make_short


def test_pick_expiration_closest_to_target_within_range():
    rules = ContractRules(min_dte=21, target_dte=35, max_dte=45)
    exps = [TODAY + timedelta(days=d) for d in (3, 10, 24, 31, 38, 52)]
    assert pick_expiration(exps, TODAY, rules) == TODAY + timedelta(days=38)  # 3 days off beats 4
    assert pick_expiration([TODAY + timedelta(days=60)], TODAY, rules) is None


def test_pick_contract_targets_delta():
    quotes = [make_quote(strike=s) for s in range(40, 51)]  # put deltas 0.00 .. 0.50
    q = pick_contract(quotes, TODAY, ContractRules(target_delta=0.25))
    assert q.strike == 45 and abs(q.delta) == 0.25


def test_contract_rejections():
    rules = ContractRules()
    assert "delta" in contract_rejection(make_quote(strike=49), TODAY, rules)
    assert "OI" in contract_rejection(make_quote(open_interest=5), TODAY, rules)
    assert "spread" in contract_rejection(make_quote(spread=0.40), TODAY, rules)
    assert "bid" in contract_rejection(make_quote(mid=0.06), TODAY, rules)
    assert "yield" in contract_rejection(make_quote(mid=0.30), TODAY, rules)
    assert "floor" in contract_rejection(make_quote("call", strike=55), TODAY, rules, min_strike=56)
    assert contract_rejection(make_quote(), TODAY, rules) is None


def test_tick_rounding_and_limit_prices():
    q = make_quote(bid=0.61, ask=0.66)
    assert sell_price(q) == 0.63 and buy_price(q) == 0.64    # mid 0.635
    q = make_quote(bid=3.10, ask=3.40)                        # above $3: nickel ticks
    assert sell_price(q) == 3.25 and buy_price(q) == 3.25
    assert round_to_tick(3.27, q, up=False) == 3.25 and round_to_tick(3.27, q, up=True) == 3.30
    q = make_quote(bid=3.10, ask=3.12)
    assert sell_price(q) >= 3.10 and buy_price(q) <= 3.12      # never cross the market


def test_close_signal():
    pos = make_short(avg_credit=1.00)
    cfg = ManageConfig(take_profit_pct=50, stop_loss_multiple=3, close_at_dte=7)
    assert close_signal(pos, 0.70, TODAY, cfg) is None
    assert close_signal(pos, 0.50, TODAY, cfg).startswith("take profit")
    assert close_signal(pos, 3.10, TODAY, cfg).startswith("stop loss")
    assert close_signal(pos, 0.80, EXP - timedelta(days=5), cfg).startswith("close at 5 DTE")
    assert close_signal(pos, 3.10, TODAY, ManageConfig()) is None   # defaults: no stop loss
