import pytest

from wheelbot.config import load_config


def test_example_config_loads():
    cfg = load_config("config.example.yaml")
    assert cfg.tickers and cfg.execution.mode == "paper" and cfg.calls.target_delta == 0.30


def test_rejects_bad_config(tmp_path):
    p = tmp_path / "c.yaml"
    p.write_text("puts: {target_delta: 0.5, max_delta: 0.3}\n")
    with pytest.raises(ValueError, match="delta"):
        load_config(p)
    p.write_text("risk: {max_loss: 1}\n")
    with pytest.raises(ValueError, match="Unknown config key"):
        load_config(p)
