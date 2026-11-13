from datetime import timedelta

from dealbot import cli
from dealbot.config import Config, load_config
from dealbot.finder import DealFinder, rank_deals
from dealbot.models import Deal, Location, Store
from dealbot.notify import Notifier
from dealbot.state import State

from .conftest import NOW

LOC = Location(36.16, -86.78, "Nashville", "Nashville", "Tennessee")
STORES = [Store("dollar_general", "Dollar General", 36.17, -86.78, "12 Main St", 0.7),
          Store("home_depot", "The Home Depot", 36.3, -86.78, "", 9.0)]


def deal(i, title, text="", age_days=0):
    return Deal(str(i), title, f"https://x/{i}", "test", text, NOW - timedelta(days=age_days))


def test_rank_orders_and_filters():
    cfg = Config(min_score=0)
    deals = [
        deal(1, "Walmart 20% off coffee"),                       # no Walmart nearby -> dropped
        deal(2, "Dollar General penny list", "Tide 1¢ in Nashville"),
        deal(3, "Home Depot drill $49.03"),
        deal(4, "Dollar General penny list (old)", age_days=10),  # too old -> dropped
        deal(5, "Best penny stocks to buy"),                     # excluded keyword
    ]
    ranked = rank_deals(deals, cfg, LOC, STORES, NOW)
    assert [d.id for d in ranked] == ["2", "3"]
    assert ranked[0].nearest_store.address == "12 Main St"
    assert ranked[0].local_mention


def test_rank_without_store_lookup_keeps_all_chains():
    ranked = rank_deals([deal(1, "Walmart clearance 75% off")], Config(min_score=0), None, None, NOW)
    assert len(ranked) == 1 and ranked[0].nearest_store is None


def test_penny_only_and_keywords():
    deals = [deal(1, "DG penny list", "Tide"), deal(2, "Home Depot clearance 50% off", "Tide")]
    assert [d.id for d in rank_deals(deals, Config(min_score=0, penny_only=True), LOC, STORES, NOW)] == ["1"]
    deals = [deal(1, "DG penny list", "Tide"), deal(2, "DG penny list", "Lego")]
    assert [d.id for d in rank_deals(deals, Config(min_score=0, keywords=["lego"]), LOC, STORES, NOW)] == ["2"]


def test_recency_lowers_score():
    cfg = Config(min_score=0)
    fresh, old = rank_deals([deal(1, "DG penny list"), deal(2, "DG penny list", age_days=6)], cfg, LOC, STORES, NOW)
    assert fresh.id == "1" and fresh.score > old.score


def test_finder_end_to_end(tmp_path, fake_http):
    reddit = {"data": {"children": [{"data": {
        "id": "p1", "title": "Dollar General penny list this week", "selftext": "Christmas mugs 1¢",
        "permalink": "/r/x/p1", "subreddit": "x", "created_utc": NOW.timestamp()}}]}}
    http = fake_http({
        "https://nominatim": [{"lat": "36.16", "lon": "-86.78", "display_name": "Nashville, TN",
                               "address": {"city": "Nashville", "state": "Tennessee"}}],
        "https://overpass": {"elements": [{"lat": 36.17, "lon": -86.78, "tags": {"brand": "Dollar General"}}]},
        "https://www.reddit.com": reddit,
        "https://news.google.com": RuntimeError("offline"),     # a failing source is skipped
    })
    cfg = Config(location="37201", state_file=str(tmp_path / "s.json"), reddit_queries=["q"],
                 google_news_queries=["q"])
    f = DealFinder(cfg, http=http, state=State(cfg.state_file))
    deals, stores = f.find()
    assert len(stores) == 1 and [d.id for d in deals] == ["reddit:p1"]
    # store lookup is cached for the next run
    f2 = DealFinder(cfg, http=fake_http({}), state=State(cfg.state_file))
    f2._loc = f.locate()
    assert f2.stores()[0].chain == "dollar_general"


def test_notifier_sends(fake_http):
    http = fake_http({})
    d = deal(1, "DG penny list")
    d.kind, d.chains = "penny", ["dollar_general"]
    Notifier(http, Config(ntfy_topic="my-topic", discord_webhook="https://discord/x")).send(d)
    assert http.sent[0][1] == "https://ntfy.sh/my-topic" and http.sent[0][3]["Priority"] == "high"
    assert http.sent[1][1] == "https://discord/x"


def test_load_config(tmp_path):
    p = tmp_path / "c.toml"
    p.write_text('[location]\nlocation = "37201"\nradius_miles = 5\n[stores]\nchains = ["target"]\n')
    cfg = load_config(p)
    assert cfg.location == "37201" and cfg.radius_miles == 5 and cfg.chains == ["target"]
    p.write_text('[filters]\nmin_scor = 3\n')
    try:
        load_config(p)
        raise AssertionError("expected ValueError")
    except ValueError as e:
        assert "min_scor" in str(e)


def test_example_config_loads():
    from pathlib import Path
    load_config(Path(__file__).parent.parent / "config.example.toml")


def test_cli_decode(capsys):
    cli.main(["decode", "home depot", "$12.03"])
    assert "final markdown" in capsys.readouterr().out
    cli.main(["decode", "Lowe's", "5.50"])
    assert "clearance" in capsys.readouterr().out
    cli.main(["tips", "target"])
    assert "30%" in capsys.readouterr().out


def test_env_overrides(tmp_path):
    cfg = load_config(None, env={"DEALBOT_LOCATION": "37201", "DEALBOT_NTFY_TOPIC": "t",
                                 "DEALBOT_CHAINS": "target, walmart", "DEALBOT_RADIUS_MILES": "15",
                                 "DEALBOT_STORE_CACHE_DAYS": "0"})
    assert (cfg.location, cfg.ntfy_topic, cfg.chains, cfg.radius_miles, cfg.store_cache_days) == \
        ("37201", "t", ["target", "walmart"], 15.0, 0)
    try:
        load_config(None, env={"DEALBOT_RADIUS_MILES": "far"})
        raise AssertionError("expected ValueError")
    except ValueError as e:
        assert "DEALBOT_RADIUS_MILES" in str(e)


def _watch_env(tmp_path, monkeypatch, fake_http, posts):
    reddit = {"data": {"children": [{"data": {
        "id": pid, "title": title, "selftext": "", "permalink": f"/r/x/{pid}", "subreddit": "x",
        "created_utc": __import__("time").time()}} for pid, title in posts]}}
    http = fake_http({"https://nominatim": [{"lat": "36.16", "lon": "-86.78", "display_name": "Secretville",
                                             "address": {"city": "Secretville", "state": "Tennessee"}}],
                      "https://overpass": {"elements": [
                          {"lat": 36.17, "lon": -86.78, "tags": {"brand": "Dollar General", "addr:street": "Hidden Rd"}},
                          {"lat": 36.17, "lon": -86.78, "tags": {"brand": "Target"}}]},
                      "https://www.reddit.com": reddit, "https://news.google.com": RuntimeError("off")})
    monkeypatch.setattr("dealbot.cli.DealFinder", lambda cfg: DealFinder(cfg, http=http, state=State(cfg.state_file)))
    monkeypatch.setenv("DEALBOT_STATE_FILE", str(tmp_path / "s.json"))
    monkeypatch.setenv("DEALBOT_LOCATION", "Secretville, TN")
    monkeypatch.setenv("DEALBOT_NTFY_TOPIC", "topic")
    monkeypatch.setenv("DEALBOT_STORE_CACHE_DAYS", "0")
    monkeypatch.chdir(tmp_path)
    return http


def test_watch_once_across_runs(tmp_path, monkeypatch, fake_http, capsys):
    http = _watch_env(tmp_path, monkeypatch, fake_http,
                      [("a", "Dollar General penny list"), ("b", "Target toys 70% off clearance")])
    cli.main(["watch", "--once", "--quiet"])
    alerts = [s for s in http.sent if s[1] == "https://ntfy.sh/topic"]
    assert len(alerts) == 1                      # first run: penny only, no backlog flood
    out = capsys.readouterr()
    assert "Secretville" not in out.out + out.err and "Hidden Rd" not in out.out + out.err
    assert "store_cache" not in (tmp_path / "s.json").read_text() or '"store_cache": {}' in (tmp_path / "s.json").read_text()

    http2 = _watch_env(tmp_path, monkeypatch, fake_http,
                       [("a", "Dollar General penny list"), ("b", "Target toys 70% off clearance"),
                        ("c", "Target clearance 70% off lego")])
    cli.main(["watch", "--once", "--quiet"])
    alerts = [s for s in http2.sent if s[1] == "https://ntfy.sh/topic"]
    assert len(alerts) == 1 and "lego" in alerts[0][2]   # later runs: only the new deal, any kind


def test_watch_quiet_hides_location_in_errors(tmp_path, monkeypatch, fake_http, capsys, caplog):
    http = _watch_env(tmp_path, monkeypatch, fake_http, [])
    http.routes["https://nominatim"] = []                 # location not found
    cli.main(["watch", "--once", "--quiet"])
    logged = capsys.readouterr().err + caplog.text
    assert "Secretville" not in logged and "DEALBOT_LOCATION" in logged


def test_test_alert(tmp_path, monkeypatch, fake_http, capsys):
    http = _watch_env(tmp_path, monkeypatch, fake_http, [])
    cli.main(["test-alert"])
    assert http.sent[-1][1] == "https://ntfy.sh/topic"
