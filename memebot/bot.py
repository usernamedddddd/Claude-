"""The trading loop: manage open positions, then look for new entries."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from .config import Config
from .dexscreener import DexScreener
from .executors import Executor
from .models import ClosedTrade, PairSnapshot, Position
from .portfolio import Portfolio, open_rejection
from .safety import RugCheck
from .strategy import entry_rejection, exit_signal, momentum_score

log = logging.getLogger(__name__)


@dataclass
class Candidate:
    snap: PairSnapshot
    score: float


class Bot:
    def __init__(self, cfg: Config, dex: DexScreener, safety: RugCheck, executor: Executor, portfolio: Portfolio):
        self.cfg = cfg
        self.dex = dex
        self.safety = safety
        self.executor = executor
        self.pf = portfolio

    # --- scanning ----------------------------------------------------------
    def scan(self, now_s: float | None = None) -> list[Candidate]:
        """Candidates that pass the entry filters, best first (no safety check yet)."""
        now_s = now_s or time.time()
        mints = self.dex.discover_mints(self.cfg.chain, self.cfg.max_candidates_per_cycle)
        snaps = self.dex.best_pairs(self.cfg.chain, mints) if mints else {}
        out = []
        for snap in snaps.values():
            reason = entry_rejection(snap, self.cfg.entry, int(now_s * 1000))
            if reason:
                log.debug("skip %s: %s", snap.symbol, reason)
                continue
            out.append(Candidate(snap, momentum_score(snap)))
        return sorted(out, key=lambda c: c.score, reverse=True)

    # --- position management ----------------------------------------------
    def manage_positions(self, now_s: float) -> None:
        if not self.pf.positions:
            return
        snaps = self.dex.best_pairs(self.cfg.chain, list(self.pf.positions))
        for mint, pos in list(self.pf.positions.items()):
            snap = snaps.get(mint)
            if snap is None or snap.price_usd <= 0:
                log.warning("no market data for %s; holding", pos.symbol)
                continue
            signal = exit_signal(pos, snap, self.cfg.exit, now_s)
            pos.peak_price_usd = max(pos.peak_price_usd, snap.price_usd)
            if signal is None:
                continue
            try:
                fill = self.executor.sell(pos, snap, signal.fraction)
            except Exception:
                log.exception("sell failed for %s (%s)", pos.symbol, signal.reason)
                continue
            pos.token_amount = max(0.0, pos.token_amount - fill.token_amount)
            pos.realized_sol += fill.sol_amount
            if signal.tier_index is not None:
                pos.tiers_hit.append(signal.tier_index)
            log.info("SELL %.0f%% of %s @ $%.8g: %s (+%.4f SOL)",
                     signal.fraction * 100, pos.symbol, fill.price_usd, signal.reason, fill.sol_amount)
            if signal.fraction >= 0.999 or pos.remaining_fraction < 0.01:
                self._close(pos, now_s, signal.reason)
            self.pf.save()

    def _close(self, pos: Position, now_s: float, reason: str) -> None:
        trade = ClosedTrade(pos.mint, pos.symbol, pos.opened_at, now_s, pos.cost_sol, pos.realized_sol, reason)
        self.pf.closed.append(trade)
        self.pf.last_exit_at[pos.mint] = now_s
        del self.pf.positions[pos.mint]
        log.info("CLOSED %s: PnL %+.4f SOL (%+.1f%%) — %s",
                 pos.symbol, trade.pnl_sol, trade.pnl_sol / trade.cost_sol * 100, reason)

    # --- entries -----------------------------------------------------------
    def open_new_positions(self, now_s: float) -> None:
        risk = self.cfg.risk
        for cand in self.scan(now_s):
            snap = cand.snap
            blocked = open_rejection(self.pf, risk, snap.mint, now_s)
            if blocked in ("max open positions", "max total exposure", "daily loss limit hit"):
                log.info("not opening more positions: %s", blocked)
                return
            if blocked:
                continue
            verdict = self.safety.check(snap.mint)
            if not verdict.ok:
                log.info("reject %s: %s", snap.symbol, verdict.reason)
                continue
            try:
                fill = self.executor.buy(snap, risk.position_size_sol)
            except Exception:
                log.exception("buy failed for %s", snap.symbol)
                continue
            self.pf.positions[snap.mint] = Position(
                mint=snap.mint, symbol=snap.symbol, pair_address=snap.pair_address,
                entry_price_usd=fill.price_usd, entry_liquidity_usd=snap.liquidity_usd,
                cost_sol=fill.sol_amount, token_amount=fill.token_amount,
                initial_token_amount=fill.token_amount, opened_at=now_s, peak_price_usd=fill.price_usd,
            )
            self.pf.save()
            log.info("BUY %s @ $%.8g for %.4f SOL (score %.2f, %s) %s",
                     snap.symbol, fill.price_usd, fill.sol_amount, cand.score, verdict.reason, snap.url)

    def cycle(self, now_s: float | None = None) -> None:
        now_s = now_s or time.time()
        self.manage_positions(now_s)
        self.open_new_positions(now_s)

    def run_forever(self) -> None:
        log.info("bot started in %s mode", self.cfg.execution.mode.upper())
        while True:
            try:
                self.cycle()
            except Exception:
                log.exception("cycle failed; retrying next poll")
            time.sleep(self.cfg.poll_seconds)
