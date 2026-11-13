# fbmarket: Facebook Marketplace deal watcher

Watches Facebook Marketplace searches and alerts you (Telegram, Discord, ntfy push, or
console) when a **new listing matches**, or when a listing you've already seen **drops in
price**. Good deals on Marketplace go in minutes; this gets you there first.

> ⚠️ **Read before using.** Meta has no public Marketplace API, and its terms prohibit
> automated access. This bot drives a real browser logged in as you, so Facebook may
> rate-limit, checkpoint or restrict your account. Keep it personal and low-volume: a few
> searches, polling every 10+ minutes (5 is the enforced minimum). Don't resell or republish
> the data. You use it at your own risk.

## How it works

Every `poll_minutes` (± random jitter) the bot, for each search:

1. Opens the Marketplace search URL in headless Chromium, using your saved login and
   sorting by newest. Your location, radius, price range and "listed in the last N days"
   are passed as Facebook's own filters.
2. Collects listings from three sources: JSON embedded in the page, GraphQL responses
   loaded while it scrolls, and the visible result cards as a fallback. This keeps it
   working when Facebook changes one of them.
3. Re-checks every listing against your rules (price bounds, `must_include`,
   `include_any`, `exclude`; whole-word, case-insensitive), because Facebook's
   filters are loose.
4. Compares against `seen.json`. A new ID sends a **new** alert, and a lower price on a known
   ID sends a **price drop** alert. The first pass of each search only records what already
   exists, so you aren't flooded with old listings (`alert_on_first_run: true` changes this).

## Quick start

```bash
cd fb-marketplace-bot
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
playwright install chromium

cp config.example.yaml config.yaml     # edit your searches and alert channels
fbmarket login                         # opens a browser window; log in once (2FA ok)
fbmarket check -v                      # one dry pass: prints matches and why others were skipped
fbmarket test-notify                   # confirm your alert channels work
fbmarket run                           # watch continuously (Ctrl+C to stop)
```

Run `fbmarket login` on a machine with a screen. The session is saved in `.fb-profile/`.
You can copy that folder to a server and run headless there, but treat it like a password.
If Facebook logs you out, the bot sends a "watcher stopped" alert and exits. Run
`fbmarket login` again.

For cron instead of a long-running process: `*/15 * * * * cd /path && .venv/bin/fbmarket run --once`.

## Alert channels

| Channel | Setup |
|---|---|
| Telegram | Create a bot with @BotFather and send it a message. `export TELEGRAM_BOT_TOKEN=...`, then set `notify.telegram.chat_id` (find it via `https://api.telegram.org/bot<token>/getUpdates`). |
| Discord | Channel settings → Integrations → Webhooks. `export DISCORD_WEBHOOK_URL=...` |
| ntfy | Install the ntfy app, subscribe to a long random topic, and put the same topic in `notify.ntfy.topic`. No account needed. |

Secrets come from environment variables only, never from the config file.

## Finding your `location`

Open Marketplace in a browser and pick a city. The URL becomes
`facebook.com/marketplace/<slug>/...`. Put `<slug>` (e.g. `nyc`, `la`, or a numeric
id) in `location`. Leave it out to use the location saved on your account.

## Layout

| File | Purpose |
|---|---|
| `fbmarket/scraper.py` | Playwright session, search URL builder, login detection |
| `fbmarket/parse.py` | JSON / GraphQL / DOM-card → `Listing`, price parsing (many currencies) |
| `fbmarket/filters.py` | per-search match rules |
| `fbmarket/store.py` | seen listings + prices (`seen.json`), pruned after 30 days |
| `fbmarket/notify.py` | console, Telegram, Discord, ntfy |
| `fbmarket/watcher.py` | the polling loop |
| `fbmarket/cli.py` | `login` / `check` / `run` / `test-notify` |

Run `pytest` for the tests. They cover parsing, filters, config validation, state, alerting
logic and notifier payloads, with no network or Facebook account needed.

## Limitations

- Facebook changes its markup often. If `check` starts finding 0 listings, run it with
  `--debug` and look at `parse.py`. The JSON walker keys on `marketplace_listing_title`,
  the field that has stayed the most stable.
- Results reflect what Facebook shows *your* account, including its location and ranking.
  Listings that Facebook doesn't surface in the first few scrolls are missed. Raise
  `browser.scrolls` to go deeper, at the cost of more page loads.
- No auto-messaging sellers. That's the fastest way to get an account restricted.
