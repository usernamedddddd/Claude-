"""Command line: `dealbot stores | deals | watch | decode | tips`."""

from __future__ import annotations

import argparse
import logging
import sys
import textwrap
import time
from pathlib import Path

from .chains import CHAINS, display
from .config import load_config
from .finder import DealFinder
from .http import HttpError
from .notify import Notifier, format_deal
from .pricing import TIPS, decode_price


def _resolve_chain(name: str) -> str:
    key = name.lower().replace("'", "").replace("-", " ").strip()
    for k, c in CHAINS.items():
        if key in (k, k.replace("_", " "), c.display.lower().replace("'", ""), c.display.lower()):
            return k
    sys.exit(f"Unknown store {name!r}. Choose from: {', '.join(CHAINS)}")


def _finder(args) -> DealFinder:
    path = args.config or ("config.toml" if Path("config.toml").exists() else None)
    cfg = load_config(path)
    if args.location:
        cfg.location, cfg.lat, cfg.lon = args.location, None, None
    if args.radius:
        cfg.radius_miles = args.radius
    if getattr(args, "penny_only", False):
        cfg.penny_only = True
    if getattr(args, "keyword", None):
        cfg.keywords = args.keyword
    if getattr(args, "min_score", None) is not None:
        cfg.min_score = args.min_score
    return DealFinder(cfg)


def cmd_stores(args) -> None:
    f = _finder(args)
    loc = f.locate()
    if not loc:
        sys.exit("Set a location: --location 'Nashville, TN' (or a ZIP), or `location` in config.toml.")
    stores = f.stores()
    if stores is None:
        sys.exit("Store lookup failed; check your connection and try again.")
    print(f"Stores within {f.cfg.radius_miles:g} mi of {loc.label}:\n")
    if not stores:
        print("  none found; try a bigger --radius")
    for s in stores:
        print(f"  {s.distance_miles:5.1f} mi  {display(s.chain):<15} {s.name}  {s.address}")


def cmd_deals(args) -> None:
    f = _finder(args)
    deals, stores = f.find()
    loc = f.locate()
    if loc and stores is not None:
        chains = sorted({s.chain for s in stores}, key=list(CHAINS).index)
        print(f"Near {loc.label}: {len(stores)} stores ({', '.join(display(c) for c in chains) or 'none'})\n")
    if not deals:
        print("No deals matched right now. Try --min-score 0, a bigger --radius, or check back later.")
        return
    for i, d in enumerate(deals[: args.top], 1):
        body = format_deal(d)
        print(f"{i:>2}. " + textwrap.indent(body, "    ").lstrip())
        print()


def cmd_watch(args) -> None:
    f = _finder(args)
    notifier = Notifier(f.http, f.cfg)
    if not notifier.enabled:
        print("No ntfy_topic or discord_webhook set; new deals will only be printed here.")
    interval = args.interval or f.cfg.watch_interval_minutes
    first = True
    while True:
        try:
            deals, _ = f.find()
            fresh = [d for d in deals if f.state.is_new(d.id)]
            for d in fresh:
                f.state.mark_seen(d.id)
                if d.score >= f.cfg.alert_min_score:
                    # On the first run, only alert penny items so you aren't flooded with old posts.
                    if not first or d.kind == "penny" or args.alert_backlog:
                        print(format_deal(d), end="\n\n", flush=True)
                        notifier.send(d)
            f.state.save()
            logging.info("checked %d deals, %d new", len(deals), len(fresh))
        except Exception as e:
            logging.warning("check failed: %s", e)
        first = False
        if args.once:
            return
        time.sleep(interval * 60)


def cmd_decode(args) -> None:
    chain = _resolve_chain(args.store)
    try:
        price = float(args.price.lstrip("$"))
    except ValueError:
        sys.exit(f"Not a price: {args.price}")
    signals = decode_price(chain, price)
    print(f"{display(chain)} ${price:.2f}:")
    if not signals:
        print("  No known clearance code for this price. Scan it in the store's app to check.")
    for s in signals:
        pct = f" (~{s.est_pct_off:g}% off)" if s.est_pct_off and s.kind != "penny" else ""
        print(f"  {s.kind.replace('_', ' ')}{pct}: {s.note}")


def cmd_tips(args) -> None:
    keys = [_resolve_chain(args.store)] if args.store else list(TIPS)
    for k in keys:
        print(f"{display(k)}:")
        for t in TIPS.get(k, ["No tips yet for this store."]):
            print(f"  • {t}")
        print()


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="dealbot", description="Find penny items and clearance deals near you.")
    p.add_argument("-c", "--config", help="TOML config file (default: ./config.toml if present)")
    p.add_argument("-v", "--verbose", action="store_true")
    sub = p.add_subparsers(dest="cmd", required=True)

    def loc_args(sp):
        sp.add_argument("-l", "--location", help="'City, ST', address or ZIP (overrides config)")
        sp.add_argument("-r", "--radius", type=float, help="search radius in miles")

    sp = sub.add_parser("stores", help="list stores near you")
    loc_args(sp)
    sp.set_defaults(fn=cmd_stores)

    for name, fn, helptext in (("deals", cmd_deals, "show the best current deals near you"),
                               ("watch", cmd_watch, "keep checking and alert on new deals")):
        sp = sub.add_parser(name, help=helptext)
        loc_args(sp)
        sp.add_argument("--penny-only", action="store_true", help="only penny items")
        sp.add_argument("-k", "--keyword", action="append", help="only deals mentioning this (repeatable)")
        sp.add_argument("--min-score", type=float)
        if name == "deals":
            sp.add_argument("-n", "--top", type=int, default=15)
        else:
            sp.add_argument("--interval", type=int, help="minutes between checks")
            sp.add_argument("--once", action="store_true", help="check once and exit (for cron)")
            sp.add_argument("--alert-backlog", action="store_true",
                            help="on the first check, alert every match, not just penny items")
        sp.set_defaults(fn=fn)

    sp = sub.add_parser("decode", help="what does this price tag mean? e.g. decode 'home depot' 12.03")
    sp.add_argument("store")
    sp.add_argument("price")
    sp.set_defaults(fn=cmd_decode)

    sp = sub.add_parser("tips", help="penny and clearance hunting tips")
    sp.add_argument("store", nargs="?")
    sp.set_defaults(fn=cmd_tips)

    args = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO if args.verbose else logging.WARNING,
                        format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    try:
        args.fn(args)
    except KeyboardInterrupt:
        pass
    except (ValueError, FileNotFoundError) as e:
        sys.exit(str(e))
    except HttpError as e:
        sys.exit(f"Network error: {e}\nCheck your internet connection and try again.")


if __name__ == "__main__":
    main()
