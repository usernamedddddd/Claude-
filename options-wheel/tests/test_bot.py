"""End-to-end paper trading of the wheel against a fake market."""

from datetime import date, datetime, timedelta, timezone

from wheelbot.bot import Bot, put_rejection
from wheelbot.config import Config, RiskConfig
from wheelbot.ledger import Ledger
from wheelbot.models import AccountSnapshot, StockHolding
from wheelbot.paper import PaperBroker

from .conftest import EXP, NOW, make_quote, make_short


class FakeMarket:
    def __init__(self):
        self.spot = 50.0
        self.marks: dict[str, float] = {}       # instrument id -> mid override
        self.earnings: date | None = None
        self.open = True
        self.day = date(2026, 10, 14)

    def underlying_price(self, symbol):
        return self.spot

    def expirations(self, symbol):
        return [EXP - timedelta(days=28), EXP, EXP + timedelta(days=28)]

    def option_quotes(self, symbol, expiration, option_type, spot):
        return [make_quote(option_type, float(k), self.spot, expiration) for k in range(40, 61)]

    def option_quote(self, pos):
        q = make_quote(pos.option_type, pos.strike, self.spot, pos.expiration)
        mid = self.marks.get(q.instrument_id)
        return make_quote(pos.option_type, pos.strike, self.spot, pos.expiration, mid=mid) if mid else q

    def next_earnings(self, symbol, today):
        return self.earnings

    def market_hours(self):
        if not self.open:
            return None
        opens = datetime(self.day.year, self.day.month, self.day.day, 13, 30, tzinfo=timezone.utc)
        return opens, opens + timedelta(hours=6, minutes=30)


def make_bot(tmp_path, market, now=NOW, **risk):
    cfg = Config(tickers=["ABC"], state_file=str(tmp_path / "state.json"))
    cfg.execution.paper_state_file = str(tmp_path / "paper.json")
    cfg.risk = RiskConfig(**risk)
    clock = {"t": now.timestamp()}
    broker = PaperBroker(market, cfg.execution, clock=lambda: clock["t"])
    return Bot(cfg, broker, Ledger(cfg.state_file)), clock


def test_full_wheel_cycle(tmp_path):
    market = FakeMarket()
    bot, clock = make_bot(tmp_path, market)

    # 1. Sells one cash-secured put at the 0.25 delta strike.
    assert bot.cycle(NOW) is None
    acct = bot.broker.account()
    [put] = acct.short_options
    assert (put.option_type, put.strike, put.expiration) == ("put", 45.0, EXP)
    assert acct.cash == 10_000 + put.avg_credit * 100 - 0.05 - 4_500

    # 2. Doesn't stack a second put on the same ticker.
    bot.cycle(NOW + timedelta(minutes=5))
    assert len(bot.broker.account().short_options) == 1

    # 3. Put decays 60% -> buys it back, then sells a fresh one in the same cycle.
    market.marks[put.instrument_id] = put.avg_credit * 0.4
    bot.cycle(NOW + timedelta(minutes=10))
    assert [e.action for e in bot.ledger.entries] == ["STO", "BTC", "STO"]
    assert bot.ledger.net_premium() > put.avg_credit * 100

    # 4. Stock drops below the strike through expiry -> assigned 100 shares at 45.
    market.marks.clear()
    market.spot = 42.0
    clock["t"] = datetime(2026, 11, 20, 18, 0, tzinfo=timezone.utc).timestamp()
    bot.broker.underlying_price("ABC")      # price seen on expiration day
    market.spot = 41.0
    clock["t"] = datetime(2026, 11, 23, 15, 0, tzinfo=timezone.utc).timestamp()
    acct = bot.broker.account()
    assert acct.stocks["ABC"].quantity == 100 and acct.stocks["ABC"].avg_cost == 45.0
    assert bot.broker.events[-1]["event"] == "ASSIGNED" and bot.broker.events[-1]["stock_price"] == 42.0

    # 5. Next cycle sells a covered call, never below the $45 cost basis,
    #    and no new put: 4,500 of stock + another put would breach the $5,000 per-ticker cap.
    market.spot = 44.0
    market.day = date(2026, 11, 23)
    bot.cycle(datetime(2026, 11, 23, 15, 0, tzinfo=timezone.utc))
    shorts = bot.broker.account().short_options
    assert [o.option_type for o in shorts] == ["call"] and shorts[0].strike >= 45
    assert bot.ledger.entries[-2].action == "GONE"    # the assigned put, noticed by reconcile

    # 6. Called away above the strike -> shares gone, back to selling puts.
    call = shorts[0]
    market.spot = call.strike + 2
    clock["t"] = datetime.combine(call.expiration + timedelta(days=3), datetime.min.time(),
                                  tzinfo=timezone.utc).timestamp() + 15 * 3600
    acct = bot.broker.account()
    assert "ABC" not in acct.stocks and bot.broker.events[-1]["event"] == "CALLED_AWAY"


def test_never_sells_naked_calls_or_ignores_limits(tmp_path):
    market = FakeMarket()
    bot, _ = make_bot(tmp_path, market, max_total_collateral_usd=3_000)
    bot.cycle(NOW)
    assert bot.broker.account().short_options == []          # $4,500 put > $3,000 total cap
    q = make_quote("call", 55.0)
    assert bot.broker.sell_to_open(q, 1, 0.5).state == "rejected"   # no shares to cover it


def test_skips_puts_through_earnings_and_outside_window(tmp_path):
    market = FakeMarket()
    bot, _ = make_bot(tmp_path, market)
    market.earnings = EXP - timedelta(days=5)
    bot.cycle(NOW)
    assert bot.broker.account().short_options == []
    market.earnings = None
    assert "outside trading window" in bot.cycle(datetime(2026, 10, 14, 13, 35, tzinfo=timezone.utc))
    market.open = False
    assert bot.cycle(NOW) == "market closed today"
    assert bot.broker.account().short_options == []


def test_put_rejection_limits():
    risk = RiskConfig(max_per_ticker_usd=5_000, max_total_collateral_usd=7_500, min_cash_reserve_usd=500)
    acct = AccountSnapshot(cash=6_000, stocks={"XYZ": StockHolding("XYZ", 100, 30)})
    assert put_rejection(acct, risk, "ABC", 4_500) is None
    assert "per-ticker" in put_rejection(acct, risk, "ABC", 5_500)
    assert "total" in put_rejection(acct, risk, "ABC", 4_900)
    acct.cash = 4_800
    assert "cash" in put_rejection(acct, risk, "ABC", 4_500)


def test_state_survives_restart(tmp_path):
    market = FakeMarket()
    bot, _ = make_bot(tmp_path, market)
    bot.cycle(NOW)
    bot2, _ = make_bot(tmp_path, market)
    assert len(bot2.broker.account().short_options) == 1
    assert list(bot2.ledger.known_shorts) == [make_short().key]
    bot2.cycle(NOW + timedelta(minutes=5))
    assert [e.action for e in bot2.ledger.entries] == ["STO"]   # no phantom GONE after restart
