"""Token safety screening via RugCheck (mint/freeze authority, LP, holder concentration...)."""

from __future__ import annotations

from dataclasses import dataclass

import httpx

from .config import SafetyConfig

BASE_URL = "https://api.rugcheck.xyz/v1"


@dataclass
class SafetyVerdict:
    ok: bool
    reason: str


class RugCheck:
    def __init__(self, cfg: SafetyConfig, client: httpx.Client | None = None, base_url: str = BASE_URL):
        self.cfg = cfg
        self.http = client or httpx.Client(timeout=15)
        self.base_url = base_url
        self._cache: dict[str, SafetyVerdict] = {}

    def check(self, mint: str) -> SafetyVerdict:
        if not self.cfg.enabled:
            return SafetyVerdict(True, "safety checks disabled")
        if mint in self._cache:
            return self._cache[mint]
        try:
            resp = self.http.get(f"{self.base_url}/tokens/{mint}/report/summary")
            resp.raise_for_status()
            report = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            # Transient failures aren't cached so the token can be retried next cycle.
            if self.cfg.reject_if_unavailable:
                return SafetyVerdict(False, f"rugcheck unavailable: {exc}")
            return SafetyVerdict(True, "rugcheck unavailable (allowed by config)")
        verdict = evaluate_report(report, self.cfg)
        self._cache[mint] = verdict
        return verdict


def evaluate_report(report: dict, cfg: SafetyConfig) -> SafetyVerdict:
    if report.get("rugged"):
        return SafetyVerdict(False, "flagged as rugged")
    risks = report.get("risks") or []
    if cfg.reject_on_danger:
        dangers = [r.get("name", "?") for r in risks if r.get("level") == "danger"]
        if dangers:
            return SafetyVerdict(False, "danger: " + ", ".join(dangers))
    score = report.get("score")
    if score is None:
        return SafetyVerdict(not cfg.reject_if_unavailable, "no risk score in report")
    if score > cfg.max_risk_score:
        return SafetyVerdict(False, f"risk score {score} > {cfg.max_risk_score}")
    return SafetyVerdict(True, f"risk score {score}")
