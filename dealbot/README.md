# dealbot: find penny items and clearance deals near you

`dealbot` finds the stores near you, then reads the places deal hunters post penny lists
and clearance finds. It keeps deals for stores you can actually reach, ranks them, and can
alert your phone when a new one appears. It also decodes clearance price tags
(for example, a Home Depot price ending in `.03` is a final markdown).

Uses only the Python standard library. You need no API keys or accounts.

## Quick start

```bash
cd dealbot
pip install -e '.[dev]'               # Python 3.11+
cp config.example.toml config.toml    # set your location and stores

dealbot stores -l "Nashville, TN"     # which stores are within 10 miles
dealbot deals  -l 37201               # best current deals near a ZIP code
dealbot deals --penny-only            # penny items only
dealbot deals -k tide -k lego         # only deals mentioning these words
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
3. **Deals.** Stores don't publish penny lists, so `dealbot` reads where shoppers share them:
   Reddit search, Google News and any RSS/Atom feeds you add.
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
