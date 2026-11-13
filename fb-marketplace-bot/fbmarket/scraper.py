"""Drives a real Chromium session (logged in as you) to run Marketplace searches."""

from __future__ import annotations

import logging
import random
from urllib.parse import quote, urlencode

from .config import BrowserConfig, SearchConfig
from .models import Listing
from .parse import listing_from_card, listings_from_html, listings_from_json, parse_json_payload

log = logging.getLogger(__name__)

BASE = "https://www.facebook.com/marketplace"

_CARDS_JS = """
els => els.map(a => ({
  href: a.getAttribute('href') || '',
  text: a.innerText || '',
  img: (a.querySelector('img') || {}).src || null,
}))
"""


class LoginRequired(RuntimeError):
    pass


def search_url(s: SearchConfig) -> str:
    params: dict[str, str | int] = {"query": s.query, "sortBy": "creation_time_descend", "exact": "false"}
    if s.min_price is not None:
        params["minPrice"] = int(s.min_price)
    if s.max_price is not None:
        params["maxPrice"] = int(s.max_price)
    if s.days_since_listed:
        params["daysSinceListed"] = s.days_since_listed
    if s.radius_km:
        params["radius"] = s.radius_km
    loc = f"/{quote(s.location.strip('/'))}" if s.location else ""
    return f"{BASE}{loc}/search/?{urlencode(params)}"


def _is_login_wall(url: str) -> bool:
    return any(p in url for p in ("/login", "/checkpoint", "/two_step_verification"))


class MarketplaceScraper:
    """Use as a context manager: `with MarketplaceScraper(cfg) as s: s.search(...)`."""

    def __init__(self, cfg: BrowserConfig, headless: bool | None = None):
        self.cfg = cfg
        self.headless = cfg.headless if headless is None else headless
        self._pw = None
        self.context = None

    def __enter__(self) -> "MarketplaceScraper":
        from playwright.sync_api import sync_playwright

        self._pw = sync_playwright().start()
        kwargs = dict(
            user_data_dir=self.cfg.user_data_dir,
            headless=self.headless,
            viewport={"width": 1280, "height": 900},
        )
        if self.cfg.executable_path:
            kwargs["executable_path"] = self.cfg.executable_path
        self.context = self._pw.chromium.launch_persistent_context(**kwargs)
        self.context.set_default_timeout(self.cfg.page_timeout_s * 1000)
        return self

    def __exit__(self, *exc) -> None:
        if self.context:
            self.context.close()
        if self._pw:
            self._pw.stop()

    def interactive_login(self) -> None:
        page = self.context.pages[0] if self.context.pages else self.context.new_page()
        page.goto("https://www.facebook.com/login")
        input("Log in to Facebook in the browser window (finish any 2FA), then press Enter here... ")
        page.goto(f"{BASE}/")
        page.wait_for_timeout(3000)
        if _is_login_wall(page.url):
            raise LoginRequired("Still not logged in; run `fbmarket login` again.")

    def logged_in(self) -> bool:
        cookies = self.context.cookies("https://www.facebook.com")
        return any(c["name"] == "c_user" for c in cookies)

    def search(self, s: SearchConfig) -> list[Listing]:
        page = self.context.new_page()
        found: dict[str, Listing] = {}

        def on_response(resp) -> None:
            if "/api/graphql" not in resp.url:
                return
            try:
                body = resp.text()
            except Exception:  # noqa: BLE001 - body may be gone after navigation
                return
            if "marketplace_listing_title" not in body:
                return
            for doc in parse_json_payload(body):
                for li in listings_from_json(doc):
                    found.setdefault(li.id, li)

        page.on("response", on_response)
        try:
            url = search_url(s)
            log.debug("Opening %s", url)
            page.goto(url, wait_until="domcontentloaded")
            if _is_login_wall(page.url):
                raise LoginRequired("Facebook asked for a login. Run `fbmarket login`.")
            try:
                page.wait_for_selector('a[href*="/marketplace/item/"]', timeout=15_000)
            except Exception:  # noqa: BLE001 - no results is a valid outcome
                log.info("[%s] no result cards appeared", s.name)
            for li in listings_from_html(page.content()):
                found.setdefault(li.id, li)
            for _ in range(max(0, self.cfg.scrolls)):
                page.mouse.wheel(0, random.randint(1800, 3200))
                page.wait_for_timeout(random.randint(1500, 3500))
            # DOM fallback for anything the JSON paths missed.
            for card in page.eval_on_selector_all('a[href*="/marketplace/item/"]', _CARDS_JS):
                li = listing_from_card(card["href"], card["text"], card["img"])
                if not li:
                    continue
                known = found.setdefault(li.id, li)
                known.image_url = known.image_url or li.image_url
                known.location = known.location or li.location
        finally:
            page.close()
        for li in found.values():
            li.search = s.name
        return list(found.values())
