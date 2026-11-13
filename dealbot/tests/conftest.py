import json
from datetime import datetime, timezone

import pytest

NOW = datetime(2026, 11, 13, 12, 0, tzinfo=timezone.utc)


class FakeHttp:
    """Answers requests from a {url-prefix: response} map and records what was sent."""

    def __init__(self, routes):
        self.routes = routes
        self.sent = []

    def _route(self, url):
        for prefix, resp in self.routes.items():
            if url.startswith(prefix):
                if isinstance(resp, Exception):
                    raise resp
                return resp
        raise RuntimeError(f"no route for {url}")

    def get_json(self, url, params=None):
        self.sent.append(("GET", url, params))
        r = self._route(url)
        return json.loads(r) if isinstance(r, str) else r

    def get_text(self, url, params=None):
        self.sent.append(("GET", url, params))
        return self._route(url)

    def post_form(self, url, form):
        self.sent.append(("POST", url, form))
        return self._route(url)

    def post_text(self, url, text, headers=None):
        self.sent.append(("POST", url, text, headers))
        return b""

    def post_json(self, url, payload):
        self.sent.append(("POST", url, payload))
        return b""


@pytest.fixture
def fake_http():
    return FakeHttp
