"""DexScreener public API client (no key needed, ~60-300 req/min limits)."""

from __future__ import annotations

import logging

import httpx

from .models import PairSnapshot

BASE_URL = "https://api.dexscreener.com"

log = logging.getLogger(__name__)


class DexScreener:
    def __init__(self, client: httpx.Client | None = None, base_url: str = BASE_URL):
        self.http = client or httpx.Client(timeout=15)
        self.base_url = base_url

    def _get(self, path: str):
        resp = self.http.get(f"{self.base_url}{path}")
        resp.raise_for_status()
        return resp.json()

    def discover_mints(self, chain: str, limit: int) -> list[str]:
        """Recently listed and recently boosted tokens on `chain`, newest first."""
        mints: list[str] = []
        for path in ("/token-profiles/latest/v1", "/token-boosts/latest/v1", "/token-boosts/top/v1"):
            try:
                items = self._get(path)
            except httpx.HTTPError as exc:
                log.warning("DexScreener %s failed: %s", path, exc)
                continue
            for item in items or []:
                mint = item.get("tokenAddress")
                if item.get("chainId") == chain and mint and mint not in mints:
                    mints.append(mint)
        return mints[:limit]

    def best_pairs(self, chain: str, mints: list[str]) -> dict[str, PairSnapshot]:
        """Most liquid pair for each mint. Batches 30 addresses per request."""
        best: dict[str, PairSnapshot] = {}
        for i in range(0, len(mints), 30):
            batch = ",".join(mints[i : i + 30])
            for raw in self._get(f"/tokens/v1/{chain}/{batch}") or []:
                snap = PairSnapshot.from_dexscreener(raw)
                if snap.mint not in mints:
                    continue  # the token appeared as the quote side
                current = best.get(snap.mint)
                if current is None or snap.liquidity_usd > current.liquidity_usd:
                    best[snap.mint] = snap
        return best
