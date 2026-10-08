from memebot.config import EntryConfig, ExitConfig
from memebot.models import Position
from memebot.strategy import entry_rejection, exit_signal, momentum_score

from .conftest import NOW, make_snap

NOW_MS = int(NOW * 1000)


def test_good_pair_passes(snap):
    assert entry_rejection(snap, EntryConfig(), NOW_MS) is None


def test_entry_filters_reject():
    cfg = EntryConfig()
    cases = {
        "liquidity": make_snap(liquidity_usd=5_000),
        "market cap": make_snap(market_cap_usd=10_000),
        "age": make_snap(created_at_ms=NOW_MS - 5 * 60_000),
        "unknown age": make_snap(created_at_ms=None),
        "volume": make_snap(volume_h1_usd=1_000),
        "txns": make_snap(buys_m5=5, sells_m5=5),
        "ratio": make_snap(buys_m5=30, sells_m5=60),
        "1h change": make_snap(price_change_h1_pct=-10),
        "5m change": make_snap(price_change_m5_pct=80),
        "quote": make_snap(quote_symbol="BONK"),
        "price": make_snap(price_usd=0),
    }
    for name, s in cases.items():
        assert entry_rejection(s, cfg, NOW_MS) is not None, name


def test_momentum_ranks_turnover_and_buy_pressure():
    hot = make_snap(volume_h1_usd=300_000, buys_m5=90, sells_m5=30)
    cold = make_snap(volume_h1_usd=50_000, buys_m5=40, sells_m5=30)
    assert momentum_score(hot) > momentum_score(cold)


def pos(**kw):
    d = dict(mint="MINT1", symbol="DOGE2", pair_address="PAIR1", entry_price_usd=0.001,
             entry_liquidity_usd=80_000, cost_sol=0.1, token_amount=100.0,
             initial_token_amount=100.0, opened_at=NOW, peak_price_usd=0.001)
    d.update(kw)
    return Position(**d)


def test_hold_when_nothing_triggers():
    assert exit_signal(pos(), make_snap(price_usd=0.00105), ExitConfig(), NOW + 60) is None


def test_stop_loss():
    sig = exit_signal(pos(), make_snap(price_usd=0.0007), ExitConfig(), NOW + 60)
    assert sig.fraction == 1.0 and "stop loss" in sig.reason


def test_liquidity_collapse_exits_first():
    sig = exit_signal(pos(), make_snap(price_usd=0.002, liquidity_usd=10_000), ExitConfig(), NOW + 60)
    assert sig.fraction == 1.0 and "liquidity" in sig.reason


def test_take_profit_tiers_are_fractions_of_original():
    cfg = ExitConfig()
    sig = exit_signal(pos(), make_snap(price_usd=0.0016), cfg, NOW + 60)
    assert sig.tier_index == 0 and sig.fraction == 0.5
    # After tier 1, 50 tokens remain; tier 2 sells 25% of the original = 50% of what's left.
    p = pos(token_amount=50.0, tiers_hit=[0], peak_price_usd=0.0026)
    sig = exit_signal(p, make_snap(price_usd=0.0026), cfg, NOW + 60)
    assert sig.tier_index == 1 and abs(sig.fraction - 0.5) < 1e-9


def test_trailing_stop_after_activation():
    p = pos(peak_price_usd=0.0014)  # was +40%, armed
    sig = exit_signal(p, make_snap(price_usd=0.0011), ExitConfig(), NOW + 60)
    assert sig.fraction == 1.0 and "trailing" in sig.reason


def test_trailing_stop_not_armed_below_activation():
    p = pos(peak_price_usd=0.00125)  # peak only +25%
    assert exit_signal(p, make_snap(price_usd=0.00095), ExitConfig(), NOW + 60) is None


def test_max_hold_time():
    sig = exit_signal(pos(), make_snap(price_usd=0.001), ExitConfig(max_hold_minutes=60), NOW + 3601)
    assert sig.fraction == 1.0 and "max hold" in sig.reason
