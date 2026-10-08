from memebot.config import RiskConfig, SafetyConfig
from memebot.models import ClosedTrade, Position
from memebot.portfolio import Portfolio, open_rejection
from memebot.safety import evaluate_report

from .conftest import NOW


def _pos(mint):
    return Position(mint, mint, "P", 1.0, 1.0, 0.1, 10, 10, NOW, 1.0)


def test_risk_limits(tmp_path):
    pf = Portfolio(tmp_path / "s.json")
    cfg = RiskConfig(position_size_sol=0.1, max_open_positions=2, max_total_exposure_sol=0.5)
    assert open_rejection(pf, cfg, "A", NOW) is None
    pf.positions["A"] = _pos("A")
    assert open_rejection(pf, cfg, "A", NOW) == "already holding"
    pf.positions["B"] = _pos("B")
    assert open_rejection(pf, cfg, "C", NOW) == "max open positions"


def test_exposure_limit(tmp_path):
    pf = Portfolio(tmp_path / "s.json")
    pf.positions["A"] = _pos("A")
    cfg = RiskConfig(position_size_sol=0.1, max_total_exposure_sol=0.15)
    assert open_rejection(pf, cfg, "B", NOW) == "max total exposure"


def test_cooldown_blacklist_and_daily_loss(tmp_path):
    pf = Portfolio(tmp_path / "s.json")
    cfg = RiskConfig(daily_loss_limit_sol=0.1, blacklist=["BAD"])
    assert open_rejection(pf, cfg, "BAD", NOW) == "blacklisted"
    pf.last_exit_at["X"] = NOW - 60
    assert open_rejection(pf, cfg, "X", NOW) == "re-entry cooldown"
    pf.closed.append(ClosedTrade("Y", "Y", NOW - 100, NOW - 50, 0.2, 0.05, "stop loss"))
    assert open_rejection(pf, cfg, "Z", NOW) == "daily loss limit hit"


def test_state_round_trip(tmp_path):
    path = tmp_path / "s.json"
    pf = Portfolio(path)
    pf.positions["A"] = _pos("A")
    pf.closed.append(ClosedTrade("B", "B", NOW, NOW + 1, 0.1, 0.2, "tp"))
    pf.save()
    again = Portfolio(path)
    assert again.positions["A"] == pf.positions["A"]
    assert again.closed[0].pnl_sol == pf.closed[0].pnl_sol


def test_safety_verdicts():
    cfg = SafetyConfig(max_risk_score=1000)
    assert evaluate_report({"score": 200, "risks": []}, cfg).ok
    assert not evaluate_report({"score": 200, "risks": [{"name": "Mint Authority still enabled", "level": "danger"}]}, cfg).ok
    assert not evaluate_report({"score": 5000, "risks": []}, cfg).ok
    assert not evaluate_report({"score": 1, "rugged": True}, cfg).ok
    assert not evaluate_report({}, cfg).ok
