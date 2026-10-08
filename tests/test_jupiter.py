"""Live executor against mocked Jupiter + RPC (skipped if the `live` extra isn't installed)."""

import base64
import json

import httpx
import pytest

solders = pytest.importorskip("solders")
from solders.hash import Hash  # noqa: E402
from solders.keypair import Keypair  # noqa: E402
from solders.message import MessageV0  # noqa: E402
from solders.null_signer import NullSigner  # noqa: E402
from solders.system_program import TransferParams, transfer  # noqa: E402
from solders.transaction import VersionedTransaction  # noqa: E402

from memebot.config import ExecutionConfig  # noqa: E402
from memebot.executors import JupiterExecutor  # noqa: E402

from .conftest import make_snap  # noqa: E402


def test_buy_signs_and_sends(monkeypatch):
    kp = Keypair()
    ix = transfer(TransferParams(from_pubkey=kp.pubkey(), to_pubkey=Keypair().pubkey(), lamports=1))
    msg = MessageV0.try_compile(kp.pubkey(), [ix], [], Hash.default())
    unsigned = VersionedTransaction(msg, [NullSigner(kp.pubkey())])
    sent = {}

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.path.endswith("/quote"):
            return httpx.Response(200, json={"outAmount": "123456"})
        if req.url.path.endswith("/swap"):
            return httpx.Response(200, json={"swapTransaction": base64.b64encode(bytes(unsigned)).decode()})
        body = json.loads(req.content)
        method = body["method"]
        if method == "sendTransaction":
            sent["tx"] = VersionedTransaction.from_bytes(base64.b64decode(body["params"][0]))
            return httpx.Response(200, json={"result": "SIG"})
        if method == "getSignatureStatuses":
            return httpx.Response(200, json={"result": {"value": [{"confirmationStatus": "confirmed", "err": None}]}})
        if method == "getTokenAccountsByOwner":
            acc = {"account": {"data": {"parsed": {"info": {"tokenAmount": {"amount": "123000"}}}}}}
            return httpx.Response(200, json={"result": {"value": [acc]}})
        return httpx.Response(400)

    ex = JupiterExecutor(ExecutionConfig(mode="live"), str(kp), httpx.Client(transport=httpx.MockTransport(handler)))
    fill = ex.buy(make_snap(), 0.1)
    assert fill.signature == "SIG" and fill.token_amount == 123000
    tx = sent["tx"]
    assert tx.verify_with_results() == [True]  # really signed by our key
