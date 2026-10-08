"""End-to-end paper trading against mocked DexScreener / RugCheck HTTP APIs."""

import httpx

from memebot.bot import Bot
from memebot.config import Config
from memebot.dexscreener import DexScreener
from memebot.executors import PaperExecutor
from memebot.portfolio import Portfolio
from memebot.safety import RugCheck

from .conftest import NOW


def raw_pair(mint, price, liquidity=80_000, symbol=None):
    return {
        "chainId": "solana", "dexId": "raydium", "pairAddress": f"pair-{mint}",
        "baseToken": {"address": mint, "symbol": symbol or mint, "name": mint},
        "quoteToken": {"symbol": "SOL"}, "priceUsd": str(price),
        "txns": {"m5": {"buys": 60, "sells": 30}},
        "volume": {"h1": 150_000, "h24": 1_000_000}, "priceChange": {"m5": 3, "h1": 40},
        "liquidity": {"usd": liquidity}, "marketCap": 900_000,
        "pairCreatedAt": int((NOW - 2 * 3600) * 1000),
    }


class Market:
    def __init__(self):
        self.prices = {"GOOD": 0.001, "RUG": 0.002}
        self.liquidity = {"GOOD": 80_000, "RUG": 80_000}

    def handler(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.startswith("/token-"):
            return httpx.Response(200, json=[
                {"chainId": "solana", "tokenAddress": "GOOD"},
                {"chainId": "solana", "tokenAddress": "RUG"},
                {"chainId": "ethereum", "tokenAddress": "0xabc"},
            ])
        if path.startswith("/tokens/v1/solana/"):
            mints = path.rsplit("/", 1)[1].split(",")
            return httpx.Response(200, json=[raw_pair(m, self.prices[m], self.liquidity[m]) for m in mints])
        if path.endswith("/report/summary"):
            mint = path.split("/")[-3]
            risks = [{"name": "Freeze Authority still enabled", "level": "danger"}] if mint == "RUG" else []
            return httpx.Response(200, json={"score": 100, "risks": risks})
        return httpx.Response(404)


def make_bot(tmp_path, market):
    client = httpx.Client(transport=httpx.MockTransport(market.handler))
    cfg = Config(state_file=str(tmp_path / "state.json"))
    return Bot(cfg, DexScreener(client), RugCheck(cfg.safety, client), PaperExecutor(cfg.execution),
               Portfolio(cfg.state_file))


def test_buys_safe_token_skips_unsafe_and_takes_profit(tmp_path):
    market = Market()
    bot = make_bot(tmp_path, market)

    bot.cycle(NOW)
    assert list(bot.pf.positions) == ["GOOD"]  # RUG rejected by safety check

    market.prices["GOOD"] = 0.0016  # +60% → first take-profit tier sells half
    bot.cycle(NOW + 60)
    pos = bot.pf.positions["GOOD"]
    assert pos.tiers_hit == [0] and abs(pos.remaining_fraction - 0.5) < 1e-9

    market.prices["GOOD"] = 0.0012  # 25% off the peak → trailing stop closes the rest
    bot.cycle(NOW + 120)
    assert "GOOD" not in bot.pf.positions
    trade = bot.pf.closed[-1]
    assert "trailing" in trade.reason and trade.pnl_sol > 0

    # Cooldown prevents immediately re-buying the same token.
    bot.cycle(NOW + 180)
    assert "GOOD" not in bot.pf.positions

    # State survives a restart.
    assert len(Portfolio(bot.cfg.state_file).closed) == 1


def test_liquidity_pull_triggers_exit(tmp_path):
    market = Market()
    bot = make_bot(tmp_path, market)
    bot.cycle(NOW)
    market.liquidity["GOOD"] = 5_000
    bot.cycle(NOW + 60)
    assert bot.pf.closed[-1].reason.startswith("liquidity collapsed")
