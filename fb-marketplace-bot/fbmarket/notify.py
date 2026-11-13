"""Alert channels: console, Telegram, Discord and ntfy (free phone push, no account needed)."""

from __future__ import annotations

import html
import logging
import os
from typing import Protocol

import httpx

from .config import NotifyConfig
from .models import Alert

log = logging.getLogger(__name__)


def headline(alert: Alert) -> str:
    li = alert.listing
    price = li.price_text or (f"{li.price:g}" if li.price is not None else "?")
    if alert.kind == "price_drop" and alert.old_price is not None:
        return f"Price drop: {li.title} — {price} (was {alert.old_price:g})"
    return f"{li.title} — {price}"


def details(alert: Alert) -> str:
    li = alert.listing
    parts = [f"Search: {li.search}"] if li.search else []
    if li.location:
        parts.append(f"Location: {li.location}")
    return "\n".join(parts)


class Notifier(Protocol):
    def send(self, alert: Alert) -> None: ...
    def send_text(self, text: str) -> None: ...


class ConsoleNotifier:
    def send(self, alert: Alert) -> None:
        print(f"[{alert.kind.upper()}] {headline(alert)}\n    {details(alert).replace(chr(10), ' | ')}\n    {alert.listing.url}")

    def send_text(self, text: str) -> None:
        print(text)


class TelegramNotifier:
    def __init__(self, token: str, chat_id: str, client: httpx.Client):
        self.base = f"https://api.telegram.org/bot{token}"
        self.chat_id = chat_id
        self.client = client

    def _post(self, method: str, payload: dict) -> None:
        r = self.client.post(f"{self.base}/{method}", json=payload)
        r.raise_for_status()

    def send(self, alert: Alert) -> None:
        li = alert.listing
        text = (f"<b>{html.escape(headline(alert))}</b>\n{html.escape(details(alert))}\n"
                f'<a href="{html.escape(li.url)}">Open listing</a>')
        if li.image_url:
            try:
                self._post("sendPhoto", {"chat_id": self.chat_id, "photo": li.image_url,
                                         "caption": text, "parse_mode": "HTML"})
                return
            except httpx.HTTPError:
                log.debug("Telegram sendPhoto failed; falling back to text", exc_info=True)
        self._post("sendMessage", {"chat_id": self.chat_id, "text": text, "parse_mode": "HTML"})

    def send_text(self, text: str) -> None:
        self._post("sendMessage", {"chat_id": self.chat_id, "text": text})


class DiscordNotifier:
    def __init__(self, webhook_url: str, client: httpx.Client):
        self.url = webhook_url
        self.client = client

    def send(self, alert: Alert) -> None:
        li = alert.listing
        embed = {"title": headline(alert)[:256], "url": li.url, "description": details(alert),
                 "color": 0xE67E22 if alert.kind == "price_drop" else 0x1877F2}
        if li.image_url:
            embed["thumbnail"] = {"url": li.image_url}
        self.client.post(self.url, json={"embeds": [embed]}).raise_for_status()

    def send_text(self, text: str) -> None:
        self.client.post(self.url, json={"content": text[:2000]}).raise_for_status()


class NtfyNotifier:
    def __init__(self, server: str, topic: str, client: httpx.Client):
        self.server = server.rstrip("/")
        self.topic = topic
        self.client = client

    def _publish(self, payload: dict) -> None:
        # JSON publishing avoids HTTP-header encoding problems with non-ASCII titles.
        self.client.post(self.server, json={"topic": self.topic, **payload}).raise_for_status()

    def send(self, alert: Alert) -> None:
        payload = {"title": headline(alert), "message": details(alert) or alert.listing.url,
                   "click": alert.listing.url,
                   "tags": ["chart_with_downwards_trend" if alert.kind == "price_drop" else "shopping_cart"]}
        if alert.listing.image_url:
            payload["attach"] = alert.listing.image_url
        self._publish(payload)

    def send_text(self, text: str) -> None:
        self._publish({"message": text})


class MultiNotifier:
    """Fans out to every channel; one failing channel never blocks the others."""

    def __init__(self, channels: list[Notifier]):
        self.channels = channels

    def _each(self, fn_name: str, arg) -> None:
        for ch in self.channels:
            try:
                getattr(ch, fn_name)(arg)
            except Exception as exc:  # noqa: BLE001 - a broken channel must not stop the watcher
                log.warning("%s failed: %s", type(ch).__name__, exc)

    def send(self, alert: Alert) -> None:
        self._each("send", alert)

    def send_text(self, text: str) -> None:
        self._each("send_text", text)


def build_notifier(cfg: NotifyConfig, client: httpx.Client | None = None,
                   env: dict[str, str] | None = None) -> MultiNotifier:
    env = os.environ if env is None else env
    client = client or httpx.Client(timeout=20)
    channels: list[Notifier] = []
    if cfg.console:
        channels.append(ConsoleNotifier())
    if cfg.telegram.enabled:
        token = env.get("TELEGRAM_BOT_TOKEN", "")
        chat_id = cfg.telegram.chat_id or env.get("TELEGRAM_CHAT_ID", "")
        if not token or not chat_id:
            raise ValueError("Telegram needs TELEGRAM_BOT_TOKEN and a chat id (config or TELEGRAM_CHAT_ID)")
        channels.append(TelegramNotifier(token, str(chat_id), client))
    if cfg.discord.enabled:
        url = env.get("DISCORD_WEBHOOK_URL", "")
        if not url:
            raise ValueError("Discord needs the DISCORD_WEBHOOK_URL environment variable")
        channels.append(DiscordNotifier(url, client))
    if cfg.ntfy.enabled:
        channels.append(NtfyNotifier(cfg.ntfy.server, cfg.ntfy.topic, client))
    return MultiNotifier(channels)
