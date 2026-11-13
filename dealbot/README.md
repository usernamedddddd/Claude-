# dealbot: find penny items and clearance deals near you

`dealbot` finds the stores near you, then reads the places deal hunters post penny lists
and clearance finds. It keeps deals for stores you can actually reach, ranks them, and can
alert your phone when a new one appears. It also decodes clearance price tags
(for example, a Home Depot price ending in `.03` is a final markdown).

Uses only the Python standard library. You need no API keys or accounts.

## On your phone (iPhone or Android)

`web/` is a phone app version that runs in your browser. It uses your phone's GPS
to find nearby stores, then shows ranked deals with directions. It also has the
price-tag checker and the tips. Nothing to install, and no account needed.

**One-time setup (about 2 minutes, on a computer or in the GitHub app):**

1. On GitHub, open this repository → **Settings** → **Pages**. Under
   **Build and deployment → Source**, choose **GitHub Actions**.
2. Open **Actions** → **Deploy deal finder app** → **Run workflow**.
   If it fails with "Branch … is not allowed to deploy", go to **Settings → Environments →
   github-pages**, add this branch under deployment branches, and run it again. Merging into
   the default branch also works.
3. Your app is then live at **`https://<your-username>.github.io/<repo-name>/`**.
   The workflow run's summary shows the exact link.

**Add it to your home screen** so it opens like a regular app:
- **iPhone (Safari):** open the link → Share button → **Add to Home Screen**.
- **Android (Chrome):** open the link → ⋮ menu → **Add to Home screen** / **Install app**.

When you first open it, tap **Use my current location** and allow location access.
You can also type a ZIP code instead. Pick the stores you shop at, and you're done.
Tap ↻ to refresh, use the 🪙 Penny filter, and tap a UPC to copy it for scanning
in the store's app. The second row of chips filters by **category**: Holiday, Toys, Home,
Cleaning, Beauty, Health, Food, Baby, Pet, Clothing, Electronics, Tools & Garden, or Other.
Each chip shows how many current deals it has. Tap a chip again to clear it, and the app
remembers your choice.

**Where the phone app's deals come from:** every hour, the GitHub job collects deals from
Google News, Bing News, Slickdeals, deal blogs (Hip2Save, The Freebie Guy, Money Saving
Mom) and Reddit. It publishes them as `deals.json` next
to the app. Your phone combines that feed with its own live Reddit search, then keeps only
deals for stores near you. Phone browsers can't read those other sites directly, which is
why the hourly job exists. The feed is the same for everyone and holds no location. Your
settings stay on your phone. The status line shows how many sources answered.

### Hourly alerts on your phone, with no computer running

`.github/workflows/dealbot-alerts.yml` runs the bot on GitHub every hour for free and
sends each new deal to your phone.

1. Install the free **ntfy** app (App Store / Google Play). Tap **+** and subscribe to a
   topic with a long, hard-to-guess name, e.g. `penny-hunt-7f3kq9x2`. Anyone who knows the
   name can read your alerts.
2. On GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Add:
   - `DEALBOT_LOCATION`: your ZIP code or `City, ST`
   - `NTFY_TOPIC`: the topic name from step 1
3. Optional: on the **Variables** tab of the same page, add `DEALBOT_RADIUS_MILES` (default 10),
   `DEALBOT_CHAINS` (e.g. `dollar_general,home_depot,target`), or `DEALBOT_ALERT_MIN_SCORE`
   (default 50; lower means more alerts), or `DEALBOT_CATEGORIES` (e.g. `toys,holiday`) to
   only be alerted about those categories.
4. Merge this branch into the default branch. GitHub only runs scheduled jobs from there.
5. Test it: **Actions → Deal alerts → Run workflow**, tick **Just send a test notification**.
   Your phone should buzz within a minute.

The first check only alerts penny items, so a backlog of older posts doesn't flood you.
After that you get every new deal scoring above `DEALBOT_ALERT_MIN_SCORE`. The repo is
public, so the job never prints deals, your location or nearby stores in its logs. Your
location stays in the secret. GitHub pauses scheduled jobs after 60 days with no repository
activity. If alerts stop, re-enable the job on the Actions page.

**Run the full Python bot on Android instead:** install [Termux](https://termux.dev)
from F-Droid, then run `pkg install python git`, `git clone` this repo, and
`cd dealbot && pip install -e .`. All the `dealbot` commands below then work on your phone.

## Quick start (computer)

```bash
cd dealbot
pip install -e '.[dev]'               # Python 3.11+
cp config.example.toml config.toml    # set your location and stores

dealbot stores -l "Nashville, TN"     # which stores are within 10 miles
dealbot deals  -l 37201               # best current deals near a ZIP code
dealbot deals --penny-only            # penny items only
dealbot deals -k tide -k lego         # only deals mentioning these words
dealbot deals --category toys         # only one category (repeat for more)
dealbot decode "home depot" 12.03     # what does this price tag mean?
dealbot tips dollar_general           # how penny shopping works at a chain
dealbot watch                         # check every hour, alert on new deals
pytest                                # run the tests
```

Example output:

```
 1. [PENNY · score 92] Dollar General penny list 11/17 – 60+ items
    Store: Dollar General
    Nearest: Dollar General 12 Main St (0.7 mi)
    UPC: 037000123456
    https://www.reddit.com/r/...
```

## Alerts on your phone

1. Install the free [ntfy](https://ntfy.sh) app and subscribe to a hard-to-guess topic,
   e.g. `penny-hunt-x7k2q`. Anyone who knows the name can read the topic.
2. Put that name in `config.toml` under `[alerts] ntfy_topic`. You can also, or instead,
   set `discord_webhook` to a Discord channel webhook URL.
3. Run `dealbot watch`, or schedule `dealbot watch --once` with cron:
   `0 * * * * cd /path/to/dealbot && dealbot watch --once`

On its first check, `watch` alerts only penny items so old posts don't flood you.
Pass `--alert-backlog` to get everything.

## How it works

1. **Location.** `dealbot` geocodes your city, address or ZIP with OpenStreetMap
   Nominatim. You can also set `lat`/`lon` directly.
2. **Nearby stores.** It queries OpenStreetMap's Overpass API for your chains within
   `radius_miles` and caches the result for a week.
3. **Deals.** Stores don't publish penny lists, so `dealbot` reads where shoppers and deal
   sites share them: Reddit, Google News, Bing News, Slickdeals and deal blogs, all in
   parallel. Add any RSS/Atom feed under `rss_feeds`. `dealbot export` writes them all to one
   JSON file, which the phone app uses.
4. **Extraction.** From each post it pulls out the store, prices, % off and UPCs, and
   decides whether the deal is a penny item, clearance or a sale.
   Prices are decoded with each chain's clearance code.
5. **Ranking.** Penny items rank above deep clearance, and deep clearance ranks above sales.
   Points are added for a known price code, a UPC you can scan, a post that names your
   city or state, and a nearby store. Points are taken off as a post ages. Deals for
   chains with no store in your radius are dropped.

## Price-tag cheat sheet (`dealbot decode`)

| Store | Price ends in | Meaning |
|---|---|---|
| Any | $0.01 | Penny item |
| Home Depot | 6 | First clearance markdown |
| Home Depot | 3 | Final markdown, often next is a penny |
| Target | 8 / 6 / 4 | ~30% / 50% / 70% off |
| Walmart | 0 (e.g. $4.50) | Likely clearance |
| Costco | .97 | Clearance (asterisk on the tag = discontinued) |
| Costco | .00 / .88 | Manager markdown |

These codes are shared by deal hunters. Stores don't publish them, and they change.

## Things to know

- **Penny items aren't guaranteed.** Stores are told to pull them, so they may be gone,
  and staff can refuse to sell them. Scan items with the store's app before you go.
- **Posts aren't verified.** Penny lists are community-made. A UPC lets you check each item.
- **Reddit may block requests** from some networks, such as VPNs or cloud servers.
  If that happens, `dealbot` skips Reddit and uses the other sources. Run with `-v` to see
  which sources worked.
- **Be polite to the free services.** Don't set `watch_interval_minutes` below 30.
  Nominatim and Overpass are community-run.
- **Store coverage depends on OpenStreetMap.** A missing store can be added at openstreetmap.org.

## Layout

| File | Purpose |
|---|---|
| `dealbot/chains.py` | supported chains and how to spot them in text/map data |
| `dealbot/pricing.py` | clearance price-code decoder and tips |
| `dealbot/extract.py` | pulls store, prices, % off, UPCs, locality out of post text |
| `dealbot/sources.py` | Reddit, Google News and RSS/Atom readers |
| `dealbot/geo.py` | geocoding and nearby-store lookup (OpenStreetMap) |
| `dealbot/finder.py` | scoring, filtering and ranking |
| `dealbot/notify.py` | ntfy and Discord alerts |
| `dealbot/cli.py` | the `dealbot` command |
| `web/` | phone app (`logic.js` mirrors the Python logic; tests: `node --test web/tests/*.test.mjs`) |
| `../.github/workflows/dealbot-pages.yml` | tests and publishes the phone app to GitHub Pages |
