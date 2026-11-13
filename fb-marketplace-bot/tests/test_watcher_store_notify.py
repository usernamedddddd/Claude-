import json

import httpx
import pytest

from fbmarket.config import parse_config
from fbmarket.models import Alert, Listing
from fbmarket.notify import build_notifier, headline
from fbmarket.scraper import LoginRequired
from fbmarket.store import SeenStore
from fbmarket.watcher import Watcher


def L(id_, price, title="Trek road bike"):
    return Listing(id=id_, title=title, price=price, price_text=f"${price:g}")


class FakeScraper:
    def __init__(self, results):
        self.results = results           # {search name: [listings]} — mutate between cycles
        self.calls = []

    def search(self, s):
        self.calls.append(s.name)
        r = self.results[s.name]
        if isinstance(r, Exception):
            raise r
        return [Listing(**{**li.__dict__, "search": s.name}) for li in r]


class Recorder:
    def __init__(self):
        self.alerts, self.texts = [], []

    def send(self, a):
        self.alerts.append(a)

    def send_text(self, t):
        self.texts.append(t)


def make(tmp_path, results, **cfg_over):
    cfg = parse_config({"searches": [{"name": "bike", "query": "bike", "max_price": 500,
                                      "exclude": ["kids"]}], **cfg_over})
    store = SeenStore(tmp_path / "seen.json", clock=lambda: 1_000_000.0)
    rec = Recorder()
    w = Watcher(cfg, FakeScraper(results), store, rec, sleep=lambda s: None)
    return w, rec


def test_first_pass_is_silent_then_new_listings_alert(tmp_path):
    results = {"bike": [L("1", 300), L("2", 900), L("3", 100, "Kids bike")]}
    w, rec = make(tmp_path, results)
    assert w.cycle() == [] and rec.alerts == []
    results["bike"] = [L("1", 300), L("4", 450)]
    alerts = w.cycle()
    assert [(a.listing.id, a.kind) for a in alerts] == [("4", "new")]
    assert rec.alerts == alerts
    assert w.cycle() == []                      # no repeats


def test_alert_on_first_run_and_price_drop(tmp_path):
    results = {"bike": [L("1", 400)]}
    w, rec = make(tmp_path, results, alert_on_first_run=True)
    assert [a.kind for a in w.cycle()] == ["new"]
    results["bike"] = [L("1", 350)]
    (a,) = w.cycle()
    assert (a.kind, a.old_price, a.listing.price) == ("price_drop", 400, 350)
    results["bike"] = [L("1", 380)]             # price going up: no alert
    assert w.cycle() == []


def test_price_drop_alerts_can_be_disabled(tmp_path):
    results = {"bike": [L("1", 400)]}
    w, _ = make(tmp_path, results, alert_price_drops=False)
    w.cycle()
    results["bike"] = [L("1", 200)]
    assert w.cycle() == []


def test_state_persists_across_restarts(tmp_path):
    results = {"bike": [L("1", 300)]}
    w, _ = make(tmp_path, results)
    w.cycle()
    data = json.loads((tmp_path / "seen.json").read_text())
    assert data["seeded"] == ["bike"] and "1" in data["listings"]
    w2, _ = make(tmp_path, {"bike": [L("1", 300), L("2", 250)]})
    assert [a.listing.id for a in w2.cycle()] == ["2"]


def test_failed_search_does_not_stop_others_but_login_does(tmp_path):
    cfg = parse_config({"searches": [{"query": "a"}, {"query": "b"}], "alert_on_first_run": True})
    rec = Recorder()
    sleeps = []
    w = Watcher(cfg, FakeScraper({"a": RuntimeError("timeout"), "b": [L("1", 5)]}),
                SeenStore(tmp_path / "s.json"), rec, sleep=sleeps.append)
    assert [a.listing.id for a in w.cycle()] == ["1"]
    assert len(sleeps) == 1 and 8 <= sleeps[0] <= 20
    w.scraper = FakeScraper({"a": LoginRequired("log in"), "b": []})
    w.sleep = lambda s: None
    with pytest.raises(LoginRequired):
        w.run_forever()
    assert rec.texts and "log in" in rec.texts[0]


def test_prune_forgets_old_listings(tmp_path):
    now = [0.0]
    store = SeenStore(tmp_path / "s.json", clock=lambda: now[0])
    store.observe(L("1", 1))
    now[0] = 40 * 86400
    store.observe(L("2", 1))
    assert store.prune(30) == 1 and set(store.listings) == {"2"}


def test_next_wait_has_jitter(tmp_path):
    w, _ = make(tmp_path, {"bike": []})
    waits = {w.next_wait_s() for _ in range(20)}
    assert all(420 <= x <= 780 for x in waits) and len(waits) > 1


def test_notifiers_send_expected_requests():
    sent = []

    def handler(req):
        sent.append((str(req.url), json.loads(req.content)))
        if "sendPhoto" in str(req.url):
            return httpx.Response(400)          # force the text fallback
        return httpx.Response(200, json={"ok": True})

    cfg = parse_config({"searches": [{"query": "a"}], "notify": {
        "console": False, "telegram": {"enabled": True, "chat_id": "42"},
        "discord": {"enabled": True}, "ntfy": {"enabled": True, "topic": "t1"}}})
    n = build_notifier(cfg.notify, client=httpx.Client(transport=httpx.MockTransport(handler)),
                       env={"TELEGRAM_BOT_TOKEN": "TOK", "DISCORD_WEBHOOK_URL": "https://discord.test/hook"})
    li = Listing(id="9", title="Desk <oak>", price=50, price_text="$50", location="Austin",
                 image_url="https://img/9.jpg", search="desk")
    n.send(Alert(li, "price_drop", old_price=80))
    urls = [u for u, _ in sent]
    assert urls == ["https://api.telegram.org/botTOK/sendPhoto", "https://api.telegram.org/botTOK/sendMessage",
                    "https://discord.test/hook", "https://ntfy.sh"]
    tg = sent[1][1]
    assert tg["chat_id"] == "42" and "Desk &lt;oak&gt;" in tg["text"] and "marketplace/item/9" in tg["text"]
    assert sent[2][1]["embeds"][0]["thumbnail"]["url"] == "https://img/9.jpg"
    assert sent[3][1]["topic"] == "t1" and sent[3][1]["click"].endswith("/item/9/")
    assert headline(Alert(li, "price_drop", 80)) == "Price drop: Desk <oak> — $50 (was 80)"


def test_one_broken_channel_does_not_block_others():
    calls = []

    def handler(req):
        calls.append(str(req.url))
        return httpx.Response(500) if "discord" in str(req.url) else httpx.Response(200)

    cfg = parse_config({"searches": [{"query": "a"}], "notify": {
        "console": False, "discord": {"enabled": True}, "ntfy": {"enabled": True, "topic": "t"}}})
    n = build_notifier(cfg.notify, client=httpx.Client(transport=httpx.MockTransport(handler)),
                       env={"DISCORD_WEBHOOK_URL": "https://discord.test/h"})
    n.send_text("hi")
    assert calls == ["https://discord.test/h", "https://ntfy.sh"]


def test_missing_secrets_are_reported():
    cfg = parse_config({"searches": [{"query": "a"}], "notify": {"telegram": {"enabled": True}}})
    with pytest.raises(ValueError, match="TELEGRAM_BOT_TOKEN"):
        build_notifier(cfg.notify, env={})
