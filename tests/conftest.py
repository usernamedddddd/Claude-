import time

import pytest

from memebot.models import PairSnapshot

NOW = 1_760_000_000.0


def make_snap(**overrides) -> PairSnapshot:
    base = dict(
        chain="solana", dex="raydium", pair_address="PAIR1", mint="MINT1", symbol="DOGE2",
        name="Doge Two", quote_symbol="SOL", price_usd=0.001, liquidity_usd=80_000,
        market_cap_usd=900_000, volume_h1_usd=120_000, volume_h24_usd=900_000,
        buys_m5=60, sells_m5=30, price_change_m5_pct=4, price_change_h1_pct=35,
        created_at_ms=int((NOW - 3 * 3600) * 1000),
    )
    base.update(overrides)
    return PairSnapshot(**base)


@pytest.fixture
def snap():
    return make_snap()
