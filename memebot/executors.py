"""Order execution: a paper simulator and a live Jupiter swap executor."""

from __future__ import annotations

import base64
import logging
import time
from typing import Protocol

import httpx

from .config import ExecutionConfig
from .models import Fill, PairSnapshot, Position

log = logging.getLogger(__name__)

SOL_MINT = "So11111111111111111111111111111111111111112"
LAMPORTS_PER_SOL = 1_000_000_000


class Executor(Protocol):
    def buy(self, snap: PairSnapshot, sol_amount: float) -> Fill: ...
    def sell(self, pos: Position, snap: PairSnapshot, fraction: float) -> Fill: ...


class PaperExecutor:
    """Simulates fills at the DexScreener price, adjusted for slippage and fees.

    Token amounts are in proportional units (not real token counts), so PnL is
    measured in SOL and ignores SOL/USD moves during the hold.
    """

    def __init__(self, cfg: ExecutionConfig):
        self.slip = cfg.slippage_bps / 10_000
        self.fee = cfg.paper_fee_pct / 100

    def buy(self, snap: PairSnapshot, sol_amount: float) -> Fill:
        price = snap.price_usd * (1 + self.slip)
        tokens = sol_amount * (1 - self.fee) / price
        return Fill(price_usd=price, sol_amount=sol_amount, token_amount=tokens)

    def sell(self, pos: Position, snap: PairSnapshot, fraction: float) -> Fill:
        tokens = pos.token_amount * fraction
        price = snap.price_usd * (1 - self.slip)
        sol = tokens * price * (1 - self.fee)
        return Fill(price_usd=price, sol_amount=sol, token_amount=tokens)


class JupiterExecutor:
    """Real swaps through Jupiter, signed locally and sent to a Solana RPC.

    Requires `pip install -e .[live]`. Token amounts are raw (smallest-unit) integers.
    """

    def __init__(self, cfg: ExecutionConfig, private_key_b58: str, client: httpx.Client | None = None):
        from solders.keypair import Keypair  # optional dependency

        self.cfg = cfg
        self.keypair = Keypair.from_base58_string(private_key_b58)
        self.pubkey = str(self.keypair.pubkey())
        self.http = client or httpx.Client(timeout=30)

    # --- RPC helpers -------------------------------------------------------
    def _rpc(self, method: str, params: list) -> dict:
        resp = self.http.post(self.cfg.rpc_url, json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        resp.raise_for_status()
        body = resp.json()
        if "error" in body:
            raise RuntimeError(f"RPC {method} failed: {body['error']}")
        return body["result"]

    def sol_balance(self) -> float:
        return self._rpc("getBalance", [self.pubkey])["value"] / LAMPORTS_PER_SOL

    def token_balance_raw(self, mint: str) -> int:
        result = self._rpc(
            "getTokenAccountsByOwner",
            [self.pubkey, {"mint": mint}, {"encoding": "jsonParsed"}],
        )
        return sum(
            int(acc["account"]["data"]["parsed"]["info"]["tokenAmount"]["amount"])
            for acc in result["value"]
        )

    # --- swap --------------------------------------------------------------
    def _swap(self, input_mint: str, output_mint: str, amount_raw: int) -> tuple[str, int]:
        from solders.transaction import VersionedTransaction

        quote = self.http.get(
            f"{self.cfg.jupiter_base_url}/quote",
            params={
                "inputMint": input_mint,
                "outputMint": output_mint,
                "amount": str(amount_raw),
                "slippageBps": self.cfg.slippage_bps,
            },
        )
        quote.raise_for_status()
        quote_json = quote.json()
        swap = self.http.post(
            f"{self.cfg.jupiter_base_url}/swap",
            json={
                "quoteResponse": quote_json,
                "userPublicKey": self.pubkey,
                "wrapAndUnwrapSol": True,
                "dynamicComputeUnitLimit": True,
                "prioritizationFeeLamports": self.cfg.priority_fee_lamports,
            },
        )
        swap.raise_for_status()
        raw_tx = VersionedTransaction.from_bytes(base64.b64decode(swap.json()["swapTransaction"]))
        signed = VersionedTransaction(raw_tx.message, [self.keypair])
        sig = self._rpc(
            "sendTransaction",
            [base64.b64encode(bytes(signed)).decode(), {"encoding": "base64", "skipPreflight": False, "maxRetries": 3}],
        )
        self._confirm(sig)
        return sig, int(quote_json["outAmount"])

    def _confirm(self, sig: str, timeout_s: float = 60) -> None:
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            status = self._rpc("getSignatureStatuses", [[sig], {"searchTransactionHistory": True}])["value"][0]
            if status:
                if status.get("err"):
                    raise RuntimeError(f"transaction {sig} failed: {status['err']}")
                if status.get("confirmationStatus") in ("confirmed", "finalized"):
                    return
            time.sleep(2)
        raise TimeoutError(f"transaction {sig} not confirmed after {timeout_s}s")

    def buy(self, snap: PairSnapshot, sol_amount: float) -> Fill:
        lamports = int(sol_amount * LAMPORTS_PER_SOL)
        sig, quoted_out = self._swap(SOL_MINT, snap.mint, lamports)
        received = self.token_balance_raw(snap.mint) or quoted_out
        log.info("BUY %s: %.4f SOL -> %d raw tokens (%s)", snap.symbol, sol_amount, received, sig)
        return Fill(price_usd=snap.price_usd, sol_amount=sol_amount, token_amount=received, signature=sig)

    def sell(self, pos: Position, snap: PairSnapshot, fraction: float) -> Fill:
        held = self.token_balance_raw(pos.mint)
        amount = held if fraction >= 0.999 else min(held, int(pos.token_amount * fraction))
        if amount <= 0:
            raise RuntimeError(f"no {pos.symbol} balance to sell")
        before = self.sol_balance()
        sig, quoted_lamports = self._swap(pos.mint, SOL_MINT, amount)
        received = self.sol_balance() - before
        sol = received if received > 0 else quoted_lamports / LAMPORTS_PER_SOL
        log.info("SELL %s: %d raw tokens -> %.4f SOL (%s)", pos.symbol, amount, sol, sig)
        return Fill(price_usd=snap.price_usd, sol_amount=sol, token_amount=amount, signature=sig)
