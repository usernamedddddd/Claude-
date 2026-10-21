# Wheel watch — paper journal

Paper trading only: no real orders. Watchlist: F, SOFI, T, PFE, NU.
Rules: options-wheel/config.example.yaml (puts 0.15–0.30Δ, 21–45 DTE, yield ≥ 12%/yr,
OI ≥ 100, spread ≤ 15%, no earnings before expiry; close at 50% of credit).
Test window: 2026-10-19 → 2026-11-13, one run per trading day at ~10:22 ET.

## Open paper positions

| Contract | Opened | Credit | Collateral |
|---|---|---|---|
| _none_ | | | |

## Totals

- Realized premium: $0.00
- Collateral in use: $0
- Trades closed: 0

## Log

### 2026-10-19 (Mon) 10:22 ET

Prices: F 12.38 · SOFI 14.41 · T 23.29 · PFE 29.51 · NU 14.47

No trades: earnings fall before every 21–45 DTE expiry (earliest is Nov 9) on all five tickers.

| Ticker | Earnings | Eligible from |
|---|---|---|
| T | Oct 21 (am) | Oct 21, after the report |
| SOFI | Oct 27 (am) | Oct 27, after the report |
| F | Oct 28 (pm) | Oct 29 |
| PFE | Nov 3 (am) | Nov 3, after the report |
| NU | Nov 12 (pm) | Nov 13 |

Open positions: none · Realized premium: $0 · Collateral needed: $0

### 2026-10-20 (Tue) 10:22 ET

Prices: F 12.16 · SOFI 14.71 · T 23.58 · PFE 29.99 · NU 15.16

No trades: all five still have earnings before every eligible expiry (T reports tomorrow, Oct 21 am).

Open positions: none · Realized premium: $0 · Collateral needed: $0

### 2026-10-21 (Wed) 10:22 ET

Prices: F 11.93 · SOFI 14.80 · T 22.04 (−5.9% after earnings) · PFE 29.86 · NU 15.14

T is eligible now that its earnings are out. Rules picked the 2026-11-27 expiry (37 DTE, nearest to 35).
No T put passed the filters:

| Strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|
| 20.5P | 0.17 | 0.06/0.29 | 3 | OI, spread 131% |
| 21P | 0.26 | 0.24/0.40 | 76 | OI < 100, spread 50% |
| 21.5P | 0.35 | 0.34/0.56 | 2365 | delta > 0.30 |

Spreads are wide right after the earnings move, and Nov 27 is a thin holiday-week expiry.
Observation for tuning: preferring standard monthly expiries (Nov 20, Dec 18) would likely find better liquidity.

Others still blocked by earnings: SOFI (Oct 27), F (Oct 28 pm), PFE (Nov 3), NU (Nov 12 pm).

Open positions: none · Realized premium: $0 · Collateral needed: $0
