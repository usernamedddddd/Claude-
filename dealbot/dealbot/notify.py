"""Push alerts to your phone (ntfy) or a Discord channel."""

from __future__ import annotations

import logging

from .chains import display
from .http import Http
from .models import Deal

log = logging.getLogger(__name__)


def format_deal(d: Deal) -> str:
    where = ", ".join(display(c) for c in d.chains) or "store not stated"
    lines = [f"[{d.kind.upper()} · score {d.score:.0f}] {d.title}", f"Store: {where}"]
    if d.nearest_store:
        s = d.nearest_store
        lines.append(f"Nearest: {s.name} {s.address} ({s.distance_miles:.1f} mi)".replace("  ", " "))
    if d.categories:
        lines.append("Category: " + ", ".join(c.replace("_", " ").title() for c in d.categories))
    if d.upcs:
        lines.append("UPC: " + ", ".join(d.upcs[:5]))
    lines += d.price_notes[:2]
    lines.append(d.url)
    return "\n".join(lines)


class Notifier:
    def __init__(self, http: Http, cfg):
        self.http = http
        self.cfg = cfg

    @property
    def enabled(self) -> bool:
        return bool(self.cfg.ntfy_topic or self.cfg.discord_webhook)

    def send(self, deal: Deal) -> None:
        body = format_deal(deal)
        if self.cfg.ntfy_topic:
            try:
                title = f"{deal.kind.title()} deal: {', '.join(display(c) for c in deal.chains) or 'nearby'}"
                self.http.post_text(f"{self.cfg.ntfy_server.rstrip('/')}/{self.cfg.ntfy_topic}", body,
                                    headers={"Title": title.encode("ascii", "ignore").decode(),
                                             "Click": deal.url, "Tags": "moneybag",
                                             "Priority": "high" if deal.kind == "penny" else "default"})
            except Exception as e:
                log.warning("ntfy alert failed: %s", e)
        if self.cfg.discord_webhook:
            try:
                self.http.post_json(self.cfg.discord_webhook, {"content": body[:1900]})
            except Exception as e:
                log.warning("Discord alert failed: %s", e)
