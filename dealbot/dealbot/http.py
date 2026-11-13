"""Tiny HTTP client on the standard library, easy to swap for a fake in tests."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

USER_AGENT = "dealbot/0.1 (personal in-store deal finder)"


class HttpError(RuntimeError):
    pass


class Http:
    def __init__(self, timeout: float = 20, retries: int = 2):
        self.timeout = timeout
        self.retries = retries

    def request(self, url: str, params: dict[str, Any] | None = None, data: bytes | None = None,
                headers: dict[str, str] | None = None) -> bytes:
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        hdrs = {"User-Agent": USER_AGENT, "Accept": "*/*", **(headers or {})}
        last: Exception | None = None
        for attempt in range(self.retries + 1):
            try:
                req = urllib.request.Request(url, data=data, headers=hdrs)
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    return resp.read()
            except urllib.error.HTTPError as e:
                last = e
                if e.code not in (429, 500, 502, 503, 504):
                    break
            except (urllib.error.URLError, TimeoutError) as e:
                last = e
            time.sleep(1.5 * (attempt + 1))
        raise HttpError(f"{url.split('?')[0]}: {last}")

    def get_text(self, url: str, params: dict[str, Any] | None = None) -> str:
        return self.request(url, params).decode("utf-8", errors="replace")

    def get_json(self, url: str, params: dict[str, Any] | None = None) -> Any:
        return json.loads(self.request(url, params, headers={"Accept": "application/json"}))

    def post_form(self, url: str, form: dict[str, str]) -> Any:
        body = urllib.parse.urlencode(form).encode()
        return json.loads(self.request(url, data=body, headers={"Accept": "application/json"}))

    def post_json(self, url: str, payload: Any) -> bytes:
        return self.request(url, data=json.dumps(payload).encode(),
                            headers={"Content-Type": "application/json"})

    def post_text(self, url: str, text: str, headers: dict[str, str] | None = None) -> bytes:
        return self.request(url, data=text.encode("utf-8"), headers=headers)
