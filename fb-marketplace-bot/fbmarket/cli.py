"""Command line: `fbmarket login | check | run | test-notify`."""

from __future__ import annotations

import argparse
import logging
import sys

from .config import Config, load_config
from .filters import check
from .models import Alert, Listing
from .notify import build_notifier
from .scraper import LoginRequired, MarketplaceScraper
from .store import SeenStore
from .watcher import Watcher


def cmd_login(cfg: Config, args) -> None:
    with MarketplaceScraper(cfg.browser, headless=False) as s:
        s.interactive_login()
    print(f"Logged in. Session saved in {cfg.browser.user_data_dir}/ (keep that folder private).")


def cmd_check(cfg: Config, args) -> None:
    """Run searches once and print what matches. Sends nothing and records nothing."""
    searches = [s for s in cfg.searches if not args.search or s.name == args.search]
    if not searches:
        sys.exit(f"No search named {args.search!r}")
    with MarketplaceScraper(cfg.browser) as scraper:
        if not scraper.logged_in():
            print("Warning: not logged in, so results may be limited. Run `fbmarket login`.")
        for s in searches:
            listings = scraper.search(s)
            print(f"\n== {s.name}: {len(listings)} listings scraped ==")
            for li in sorted(listings, key=lambda x: (x.price is None, x.price or 0)):
                ok, reason = check(li, s)
                if ok or args.verbose:
                    mark = "MATCH" if ok else f"skip ({reason})"
                    print(f"  {li.price_text or '?':>10}  {li.title[:60]:<60}  {li.location[:25]:<25}  {mark}")
                    if ok:
                        print(f"  {'':10}  {li.url}")


def cmd_run(cfg: Config, args) -> None:
    notifier = build_notifier(cfg.notify)
    store = SeenStore(cfg.state_file)
    with MarketplaceScraper(cfg.browser) as scraper:
        if not scraper.logged_in():
            sys.exit("Not logged in. Run `fbmarket login` first.")
        watcher = Watcher(cfg, scraper, store, notifier)
        try:
            if args.once:
                alerts = watcher.cycle()
                print(f"{len(alerts)} alert(s) sent.")
            else:
                print(f"Watching {len(cfg.searches)} search(es) every ~{cfg.poll_minutes:g} min. Ctrl+C to stop.")
                watcher.run_forever()
        except LoginRequired as exc:
            sys.exit(str(exc))
        except KeyboardInterrupt:
            store.save()
            print("\nStopped.")


def cmd_test_notify(cfg: Config, args) -> None:
    notifier = build_notifier(cfg.notify)
    sample = Listing(id="0", title="Test listing: alerts are working", price=42.0,
                     price_text="$42", location="Your city", search="test")
    notifier.send(Alert(sample, "new"))
    print(f"Sent a test alert to {len(notifier.channels)} channel(s). Check them.")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="fbmarket", description="Facebook Marketplace deal watcher")
    p.add_argument("-c", "--config", default="config.yaml")
    p.add_argument("--debug", action="store_true")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("login", help="open a browser window to log in to Facebook once")
    c = sub.add_parser("check", help="run searches once and print matches (no alerts)")
    c.add_argument("--search", help="only this search name")
    c.add_argument("-v", "--verbose", action="store_true", help="also show rejected listings and why")
    r = sub.add_parser("run", help="watch continuously and send alerts")
    r.add_argument("--once", action="store_true", help="one pass, then exit (for cron)")
    sub.add_parser("test-notify", help="send a sample alert to every enabled channel")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    try:
        cfg = load_config(args.config)
    except FileNotFoundError:
        sys.exit(f"{args.config} not found. Copy config.example.yaml to config.yaml and edit it.")
    except ValueError as exc:
        sys.exit(f"Config error: {exc}")
    {"login": cmd_login, "check": cmd_check, "run": cmd_run, "test-notify": cmd_test_notify}[args.cmd](cfg, args)


if __name__ == "__main__":
    main()
