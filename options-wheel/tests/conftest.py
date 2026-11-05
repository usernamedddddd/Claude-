from datetime import date, datetime, timedelta, timezone

from wheelbot.models import OptionQuote, ShortOption

# Wednesday 2026-10-14, 11:00 ET (15:00 UTC): inside the trading window.
NOW = datetime(2026, 10, 14, 15, 0, tzinfo=timezone.utc)
TODAY = date(2026, 10, 14)
EXP = TODAY + timedelta(days=37)   # 2026-11-20, a Friday


def delta_for(option_type: str, strike: float, spot: float) -> float:
    d = max(0.01, min(0.99, 0.5 - (strike - spot) * 0.05 if option_type == "call" else 0.5 - (spot - strike) * 0.05))
    return d if option_type == "call" else -d


def make_quote(option_type="put", strike=45.0, spot=50.0, expiration=EXP, mid=None, spread=0.04, **kw) -> OptionQuote:
    delta = delta_for(option_type, strike, spot)
    mid = 2.5 * abs(delta) if mid is None else mid
    base = dict(symbol="ABC", option_type=option_type, strike=strike, expiration=expiration,
                bid=round(mid - spread / 2, 2), ask=round(mid + spread / 2, 2), delta=delta,
                open_interest=500, volume=50, instrument_id=f"{option_type}-{strike:g}-{expiration}")
    base.update(kw)
    return OptionQuote(**base)


def make_short(option_type="put", strike=45.0, expiration=EXP, quantity=1, avg_credit=0.62) -> ShortOption:
    return ShortOption("ABC", option_type, strike, expiration, quantity, avg_credit, f"{option_type}-{strike:g}-{expiration}")
