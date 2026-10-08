"""Command line: `memebot scan | run | status`."""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time

from .bot import Bot
from .config import load_config
from .dexscreener import DexScreener
from .executors import JupiterExecutor, PaperExecutor
from .portfolio import Portfolio
from .safety import RugCheck

LIVE_CONFIRMATION = "I accept I can lose all of this money"


def _build(cfg, live: bool) -> Bot:
    if live:
        key = os.environ.get("SOLANA_PRIVATE_KEY")
        if not key:
            sys.exit("SOLANA_PRIVATE_KEY is not set (base58 secret key of a dedicated hot wallet).")
        executor = JupiterExecutor(cfg.execution, key)
    else:
        executor = PaperExecutor(cfg.execution)
    return Bot(cfg, DexScreener(), RugCheck(cfg.safety), executor, Portfolio(cfg.state_file))


def cmd_scan(cfg, args) -> None:
    bot = _build(cfg, live=False)
    cands = bot.scan()
    if not cands:
        print("No candidates pass the entry filters right now.")
        return
    print(f"{'SYMBOL':<12}{'SCORE':>7}{'LIQ $':>12}{'MCAP $':>13}{'VOL 1h $':>12}{'5m B/S':>9}{'1h %':>8}  SAFETY")
    for c in cands[: args.top]:
        s = c.snap
        verdict = bot.safety.check(s.mint) if args.safety else None
        safety = ("OK " if verdict.ok else "NO ") + verdict.reason if verdict else "-"
        print(f"{s.symbol[:11]:<12}{c.score:>7.2f}{s.liquidity_usd:>12,.0f}{s.market_cap_usd:>13,.0f}"
              f"{s.volume_h1_usd:>12,.0f}{f'{s.buys_m5}/{s.sells_m5}':>9}{s.price_change_h1_pct:>+8.1f}  {safety}")
        print(f"{'':12}{s.mint}  {s.url}")


def cmd_run(cfg, args) -> None:
    live = cfg.execution.mode == "live"
    if live != args.live:
        sys.exit("Live trading needs BOTH `execution.mode: live` in the config AND the --live flag.")
    if live:
        print(f"LIVE MODE: real swaps of up to {cfg.risk.max_total_exposure_sol} SOL total.")
        if input(f'Type "{LIVE_CONFIRMATION}" to continue: ').strip() != LIVE_CONFIRMATION:
            sys.exit("Aborted.")
    bot = _build(cfg, live)
    if args.once:
        bot.cycle()
    else:
        bot.run_forever()


def cmd_status(cfg, args) -> None:
    pf = Portfolio(cfg.state_file)
    now = time.time()
    print(f"Open positions: {len(pf.positions)}  exposure: {pf.exposure_sol:.4f} SOL")
    for p in pf.positions.values():
        held_min = (now - p.opened_at) / 60
        print(f"  {p.symbol:<10} entry ${p.entry_price_usd:.8g}  cost {p.cost_sol:.4f} SOL  "
              f"left {p.remaining_fraction:.0%}  held {held_min:.0f}m  {p.mint}")
    wins = [t for t in pf.closed if t.pnl_sol > 0]
    print(f"Closed trades: {len(pf.closed)}  win rate: {len(wins) / len(pf.closed):.0%}" if pf.closed else "Closed trades: 0")
    print(f"Realized PnL today: {pf.realized_pnl_today():+.4f} SOL  all time: {pf.total_realized_pnl():+.4f} SOL")
    for t in pf.closed[-args.last:]:
        print(f"  {t.symbol:<10} {t.pnl_sol:+.4f} SOL ({t.pnl_sol / t.cost_sol:+.0%})  {t.reason}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="memebot", description="Solana memecoin scanner / trading bot")
    parser.add_argument("-c", "--config", default="config.yaml" if os.path.exists("config.yaml") else None)
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("scan", help="show tokens that pass the entry filters (no trading)")
    p.add_argument("--top", type=int, default=10)
    p.add_argument("--no-safety", dest="safety", action="store_false", help="skip RugCheck lookups")
    p.set_defaults(func=cmd_scan)

    p = sub.add_parser("run", help="run the trading loop (paper unless --live)")
    p.add_argument("--live", action="store_true", help="trade real funds (also needs execution.mode: live)")
    p.add_argument("--once", action="store_true", help="run a single cycle and exit")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("status", help="show positions and PnL")
    p.add_argument("--last", type=int, default=10)
    p.set_defaults(func=cmd_status)

    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args.func(load_config(args.config), args)


if __name__ == "__main__":
    main()
