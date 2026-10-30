"""Command line: `wheelbot login | scan | run | status`."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime

from .bot import NY, Bot
from .broker import RobinhoodBroker, login
from .config import load_config
from .ledger import Ledger
from .paper import PaperBroker
from .strategy import annualized_yield_pct, dte, sell_price

LIVE_CONFIRMATION = "I understand I can be assigned and lose money"


def _robinhood(cfg) -> RobinhoodBroker:
    import robin_stocks.robinhood as rh

    login(rh, os.environ.get("RH_USERNAME"), os.environ.get("RH_PASSWORD"), os.environ.get("RH_MFA_SECRET"))
    return RobinhoodBroker(rh, os.environ.get("RH_ACCOUNT_NUMBER"), cfg.execution.order_timeout_seconds)


def _build(cfg, live: bool) -> Bot:
    if not cfg.tickers:
        sys.exit("No tickers configured. Set `tickers:` in config.yaml (stocks you'd be happy to own).")
    rh = _robinhood(cfg)
    broker = rh if live else PaperBroker(rh, cfg.execution)
    return Bot(cfg, broker, Ledger(cfg.state_file))


def _print_account(bot: Bot) -> None:
    acct = bot.broker.account()
    print(f"Free cash: ${acct.cash:,.2f}   committed (put collateral + stock cost): ${acct.committed():,.2f}")
    for h in acct.stocks.values():
        tag = "" if h.symbol in bot.cfg.tickers else "  (not in tickers, ignored)"
        print(f"  {h.symbol:<6} {h.quantity:>8g} sh @ ${h.avg_cost:,.2f}{tag}")
    for o in acct.short_options:
        tag = "" if o.symbol in bot.cfg.tickers else "  (not in tickers, ignored)"
        print(f"  short {o.key} x{o.quantity} sold @ ${o.avg_credit:.2f}{tag}")


def cmd_login(cfg, args) -> None:
    bot = Bot(cfg, _robinhood(cfg), Ledger(cfg.state_file))
    print("Logged in to Robinhood. Live account:")
    _print_account(bot)


def cmd_scan(cfg, args) -> None:
    bot = _build(cfg, live=cfg.execution.mode == "live")  # read-only: scan never places orders
    today = datetime.now(NY).date()
    print(f"{'TICKER':<7}{'TYPE':<6}{'EXPIRY':<12}{'STRIKE':>8}{'BID':>7}{'ASK':>7}{'DELTA':>7}{'OI':>7}"
          f"{'YIELD/YR':>10}{'COLLATERAL':>12}")
    for idea in bot.ideas(today):
        q = idea.quote
        if q is None:
            print(f"{idea.symbol:<7}{idea.option_type:<6}-- {idea.note}")
            continue
        price = sell_price(q)
        coll = f"${q.strike * 100:,.0f}" if q.option_type == "put" else "shares"
        print(f"{q.symbol:<7}{q.option_type:<6}{q.expiration.isoformat():<12}{q.strike:>8g}{q.bid:>7.2f}{q.ask:>7.2f}"
              f"{abs(q.delta or 0):>7.2f}{q.open_interest:>7}"
              f"{annualized_yield_pct(price, q.strike, dte(q.expiration, today)):>9.1f}%{coll:>12}")


def cmd_run(cfg, args) -> None:
    live = cfg.execution.mode == "live"
    if live != args.live:
        sys.exit("Live trading needs BOTH `execution.mode: live` in the config AND the --live flag.")
    if live:
        print(f"LIVE MODE: real orders on {', '.join(cfg.tickers)}, up to "
              f"${cfg.risk.max_total_collateral_usd:,.0f} committed.")
        print("The bot will also manage any short options you already hold on these tickers.")
        if input(f'Type "{LIVE_CONFIRMATION}" to continue: ').strip() != LIVE_CONFIRMATION:
            sys.exit("Aborted.")
    bot = _build(cfg, live)
    if args.once:
        skipped = bot.cycle()
        if skipped:
            print(f"Did not trade: {skipped}")
    else:
        bot.run_forever()


def cmd_status(cfg, args) -> None:
    bot = _build(cfg, live=cfg.execution.mode == "live")
    print(f"Mode: {cfg.execution.mode.upper()}")
    _print_account(bot)
    led = bot.ledger
    print(f"Net option premium: today ${led.net_premium(today_only=True):+,.2f}   "
          f"all time ${led.net_premium():+,.2f}   ({len(led.entries)} ledger entries)")
    for e in led.entries[-args.last:]:
        when = datetime.fromtimestamp(e.at, NY).strftime("%Y-%m-%d %H:%M")
        print(f"  {when} {e.action:<4} {e.symbol} {e.expiration} {e.strike:g}{e.option_type[0].upper()} "
              f"x{e.quantity} @ {e.price:.2f}  {e.reason}")
    if isinstance(bot.broker, PaperBroker):
        for ev in bot.broker.events[-args.last:]:
            print(f"  paper {ev['event']:<12} {ev['contract']} x{ev['quantity']}  stock ${ev['stock_price']:.2f}  {ev['note']}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="wheelbot", description="Options wheel bot for Robinhood")
    parser.add_argument("-c", "--config", default="config.yaml" if os.path.exists("config.yaml") else None)
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login", help="log in (handles MFA) and show the live account").set_defaults(func=cmd_login)

    sub.add_parser("scan", help="show the contracts the bot would sell now (no trading)").set_defaults(func=cmd_scan)

    p = sub.add_parser("run", help="run the trading loop (paper unless --live)")
    p.add_argument("--live", action="store_true", help="place real orders (also needs execution.mode: live)")
    p.add_argument("--once", action="store_true", help="run a single cycle and exit")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("status", help="show positions and premium collected")
    p.add_argument("--last", type=int, default=10)
    p.set_defaults(func=cmd_status)

    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
    )
    args.func(load_config(args.config), args)


if __name__ == "__main__":
    main()
