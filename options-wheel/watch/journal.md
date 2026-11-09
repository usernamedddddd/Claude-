# Wheel watch — paper journal

Paper trading only: no real orders. Watchlist: F, SOFI, T, PFE, NU.
Rules: options-wheel/config.example.yaml (puts 0.15–0.30Δ, 21–45 DTE, yield ≥ 12%/yr,
OI ≥ 100, spread ≤ 15%, no earnings before expiry; close at 50% of credit).
Test window: 2026-10-19 → 2026-11-13, one run per trading day at ~10:22 ET.

## Open paper positions

| Contract | Opened | Credit | Collateral | 50% target |
|---|---|---|---|---|
| SOFI 2026-12-04 16P ×1 (id 74f5e363-2b13-435a-97fd-fce993b0aebe) | 2026-10-29 @ 0.39 | $39 | $1,600 | buy back ≤ 0.19 |

## Totals

- Realized premium: $20.00 gross / $19.90 after fees
- Collateral in use: $1,600 (peak so far: $1,600)
- Trades opened: 2 · closed: 1 (1 win, 0 losses)

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

### 2026-10-22 (Thu) 10:25 ET

Prices: F 12.01 · SOFI 14.96 · T 22.60 (+3% rebound) · PFE 30.25 · NU 14.76

T, 2026-11-27 expiry (36 DTE): no put passed again.

| Strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|
| 21P | 0.24 | 0.14/0.70 | 77 | OI, spread 133% |
| 21.5P | 0.26 | 0.24/0.40 | 2368 | spread 50% |
| 22P | 0.34 | 0.33/0.51 | 420 | delta > 0.30 |

Observation: the 21.5P was otherwise a fit (Δ 0.26, OI 2368, ~15%/yr at the 0.32 mid), but the
15%-of-mid spread limit is very hard to meet on cheap options: a $0.32 option needs a ≤ $0.05 spread.
A cap like "15% of mid or $0.10, whichever is larger" would suit $10–30 stocks better.
Not changed; the user decides.

Others still blocked by earnings: SOFI (Oct 27), F (Oct 28 pm), PFE (Nov 3), NU (Nov 12 pm).

Open positions: none · Realized premium: $0 · Collateral needed: $0

### 2026-10-23 (Fri) 10:22 ET

Prices: F 11.46 · SOFI 14.41 · T 21.57 (−5%) · PFE 29.86 · NU 14.61

T, 2026-11-27 expiry (35 DTE): no put passed.

| Strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|
| 20P | 0.20 | 0.15/0.35 | 272 | spread 80% |
| 20.5P | 0.26 | 0.22/0.40 | 51 | OI, spread 58% |
| 21P | 0.36 | 0.35/0.66 | 98 | delta > 0.30 |

Others still blocked by earnings: SOFI (Oct 27), F (Oct 28 pm), PFE (Nov 3), NU (Nov 12 pm).

Open positions: none · Realized premium: $0 · Collateral needed: $0

#### Week 1 summary (Oct 19–23)

- Premium: $0. Trades opened: 0, closed: 0. Open risk: none.
- Why: earnings season blocked 4 of 5 tickers all week. T was eligible from Oct 21, but the
  spread filter rejected every candidate on all 3 days (50–133% vs the 15% max).
- Notable: T swung −6%, +3%, −5% after earnings. Had the 21P been sold on Oct 21 at its 0.32 mid,
  it would now be marked at 0.51, about a $19 paper loss, so the filters kept us out of a losing entry.
- Main finding: as written, the spread rule effectively blocks options under ~$1 on these
  stocks. Unless it's loosened (e.g. 15% of mid or $0.10, whichever is larger), the test may
  produce few or no trades. Week 2 opens up SOFI (Oct 27) and F (Oct 29).

### 2026-10-26 (Mon) 10:24 ET

Prices: F 11.69 · SOFI 14.60 · T 21.02 · PFE 30.06 · **NU 12.07 (−20.4%)**

T, 2026-11-27 expiry (32 DTE; Dec 4 at 39 DTE is further from 35): no put passed.

| Strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|
| 19.5P | 0.16 | 0.04/0.28 | 249 | bid < 0.10, spread 150% |
| 20P | 0.25 | 0.15/0.40 | 281 | spread 91% |
| 20.5P | 0.34 | 0.21/0.50 | 57 | delta > 0.30 |

Notable: NU gapped down 20% before its earnings date. It wasn't eligible (earnings Nov 12), so there
was no paper position. Had a ~0.25Δ put been sold at about 14 strike, it would be ~$190 in the money
per contract right now. That is the wheel's main risk: one bad gap wipes out many months of premium.

Others still blocked by earnings: SOFI (tomorrow am), F (Oct 28 pm), PFE (Nov 3), NU (Nov 12 pm).

Open positions: none · Realized premium: $0 · Collateral needed: $0

### 2026-10-27 (Tue) 10:50 ET

Prices: F 11.78 · **SOFI 16.49 (+14% after earnings)** · T 21.08 · PFE 29.83 · NU 12.48

Expiry picked: 2026-12-04 (38 DTE; nearer to 35 than Nov 27 at 31).

**PAPER STO: SOFI 2026-12-04 15P ×1 @ 0.39** (mid of 0.37/0.41): Δ 0.24, OI 340, spread 10%,
~25%/yr on $1,500 collateral. Credit $39 (≈ $38.95 after the $0.05 fee). Breakeven $14.61, 11% below the stock.

| SOFI strike | Δ | Bid/Ask | OI | Result |
|---|---|---|---|---|
| 14.5P | 0.18 | 0.26/0.29 | 283 | passes (18%/yr) |
| **15P** | **0.24** | **0.37/0.41** | **340** | **passes, closest to 0.25Δ → sold** |
| 15.5P | 0.31 | 0.51/0.55 | 77 | delta > 0.30 |

T, 2026-12-04: no put passed (20P Δ0.25 spread 52%; 19.5P OI 17; 20.5P Δ0.34).
Still blocked by earnings: F (tomorrow pm), PFE (Nov 3), NU (Nov 12 pm).

Open: SOFI 15P (mark 0.39, unrealized $0) · Realized premium: $0 · Collateral needed: $1,500

### 2026-10-28 (Wed) 10:29 ET

Prices: F 11.75 · SOFI 16.88 · T 20.84 · PFE 29.60 · NU 12.10

Manage: SOFI 12-04 15P marks at 0.285 (0.27/0.30) against 0.39 sold, so 27% of the credit is
captured (+$10.50 unrealized). Below the 50% target, so hold.

T, 2026-12-04 (37 DTE): no put passed (19.5P OI 20; 20P Δ0.28 spread 65%; 20.5P Δ0.37).
Still blocked by earnings: F (reports tonight), PFE (Nov 3), NU (Nov 12 pm).

Open: SOFI 15P (+$10.50) · Realized premium: $0 · Collateral needed: $1,500

### 2026-10-29 (Thu) 10:33 ET

Prices: F 12.22 (+2% after earnings) · SOFI 17.43 · T 21.32 · PFE 29.76 · NU 12.05

**PAPER BTC: SOFI 2026-12-04 15P ×1 @ 0.19** (mid of 0.18/0.20). Sold at 0.39 two days ago, so 51% of the
credit was captured and the 50% rule hit. **Realized +$20.00** (+$19.90 after $0.10 fees), on $1,500 for 2 days.

**PAPER STO: SOFI 2026-12-04 16P ×1 @ 0.39** (mid of 0.37/0.41): Δ 0.25, OI 785, spread 10%, ~25%/yr
on $1,600. Breakeven $15.61, 10% below the stock.

| SOFI strike | Δ | Bid/Ask | OI | Result |
|---|---|---|---|---|
| 15.5P | 0.18 | 0.26/0.28 | 236 | passes (18%/yr) |
| **16P** | **0.25** | **0.37/0.41** | **785** | **passes, closest to 0.25Δ → sold** |
| 16.5P | 0.32 | 0.52/0.56 | 666 | delta > 0.30 |

F is now eligible, 2026-12-04 (36 DTE): no put passed.

| F strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|
| 10.5P | 0.12 | 0.06/0.16 | 89 | delta, bid, OI |
| 11P | 0.17 | 0.09/0.20 | 81 | bid, OI, spread 76% |
| 11.5P | 0.28 | 0.25/0.28 | 54 | OI 54 < 100 (otherwise a fit) |
| 12P | 0.41 | 0.43/0.68 | 156 | delta > 0.30 |

T, 2026-12-04: no put passed (20P Δ0.27 spread 174%; 20.5P Δ0.31; 21P Δ0.40).
Still blocked by earnings: PFE (Nov 3), NU (Nov 12 pm).

Open: SOFI 16P (mark 0.39, $0) · Realized premium: +$20.00 · Collateral needed: $1,600

### 2026-10-30 (Fri) 10:40 ET

Prices: F 12.24 · SOFI 16.94 (−3.8%) · T 21.38 · PFE 30.18 · NU 11.78

Manage: SOFI 12-04 16P marks at 0.53 (0.52/0.54), against 0.39 sold, so **−$14 unrealized**. Δ is now 0.31.
No stop loss in the rules, so hold. The stock is still 6% above the $16 strike.

Dec 4 expiry (35 DTE), no new puts passed:
- F: 11P Δ0.15 bid 0.09 < 0.10; 11.5P Δ0.26 OI 53 and spread 23%; 12P Δ0.40.
- T: 20P Δ0.19 spread 124%; 20.5P Δ0.29 spread 148%; 21P Δ0.38.
Still blocked by earnings: PFE (Nov 3), NU (Nov 12 pm).

Open: SOFI 16P (−$14) · Realized premium: +$20.00 · Collateral needed: $1,600

#### Week 2 summary (Oct 26–30)

- Premium: +$20.00 realized (1 trade closed, 1 win: SOFI 15P, 0.39 → 0.19 in 2 days).
- Open risk: 1 SOFI 16P Dec 4, $1,600 collateral, −$14 unrealized (worst drawdown so far).
- Trades found: SOFI was the only ticker whose options passed the filters (tight 0.02–0.04 spreads,
  OI in the hundreds). F and T failed every day on spread or open interest.
- Notable: NU fell 20% on Oct 26 with no position. SOFI rose 14% on earnings, and the filters
  only let us in after the move.
- Takeaway so far: these rules really only trade SOFI. To get more trades without loosening risk,
  swap F/T for tickers with tighter option markets, or relax the spread rule (still your call).

### 2026-11-02 (Mon) 10:36 ET

Prices: F 12.43 · SOFI 17.45 (+4%) · T 21.47 · PFE 30.28 · NU 11.92

Manage: SOFI 12-04 16P marks at 0.38 (0.37/0.39) against 0.39 sold, so +$1 unrealized (recovered from −$14). Hold.

Dec 4 expiry (32 DTE), no new puts passed:
- F: 11P Δ0.12; 11.5P Δ0.22 OI 60, spread 21%; 12P Δ0.35.
- T: 20P Δ0.19 spread 29% (closest yet); 20.5P Δ0.28 spread 68%; 21P Δ0.36.
Still blocked by earnings: PFE (reports tomorrow am), NU (Nov 12 pm).

Open: SOFI 16P (+$1) · Realized premium: +$20.00 · Collateral needed: $1,600

### 2026-11-03 (Tue) 10:23 ET

Prices: F 12.36 · SOFI 16.60 (−4.8%) · T 21.21 · PFE 30.59 (after earnings, flat) · NU 11.56

Manage: SOFI 12-04 16P marks at 0.67 (0.65/0.69) against 0.39 sold, so **−$28 unrealized** (worst so far). Δ 0.37.
Hold: there's no stop loss, and the stock is still 3.8% above the strike. Assignment would mean buying
100 SOFI at $16 (net $15.61 after premium).

PFE is eligible now that its earnings are out. Expiry picked: 2026-12-11 (38 DTE; nearer to 35 than Dec 4 at 31).
New weekly expiries have thin open interest, so no new puts passed:

| Ticker | Strike | Δ | Bid/Ask | OI | Fails |
|---|---|---|---|---|---|
| PFE | 28P | 0.16 | 0.21/0.32 | 5 | OI, spread 42% |
| PFE | 29P | 0.27 | 0.43/0.58 | 20 | OI, spread 30% |
| F | 11.5P | 0.25 | 0.20/0.29 | 20 | OI, spread 37% |
| T | 20P | 0.24 | 0.26/0.35 | 25 | OI, spread 30% |

Observation: always taking the expiry closest to 35 DTE lands on newly listed weeklies with almost no
open interest. Restricting to monthly expiries (3rd Friday, e.g. Dec 18) would likely find more liquid contracts.

Still blocked by earnings: NU (Nov 12 pm).

Open: SOFI 16P (−$28) · Realized premium: +$20.00 · Collateral needed: $1,600

### 2026-11-04 (Wed) 10:22 ET

Prices: F 12.58 · SOFI 17.52 (+4.4%) · T 21.94 · PFE 30.15 · NU 12.09

Manage: SOFI 12-04 16P marks at 0.345 (0.33/0.36) against 0.39 sold, so +$4.50 (12% captured). It swung from −$28 back to green
in one day. Hold.

Dec 11 expiry (37 DTE), no new puts passed:
- PFE: 29P Δ0.30 OI 34, spread 64%; 30P Δ0.44.
- F: 11.5P Δ0.19 OI 40; 12P Δ0.31 (just over 0.30; OI 1676, spread 20%).
- T: 20.5P Δ0.21 OI 18; 21P Δ0.30 OI 13, spread 156%.
Still blocked by earnings: NU (Nov 12 pm).

Open: SOFI 16P (+$4.50) · Realized premium: +$20.00 · Collateral needed: $1,600

### 2026-11-05 (Thu) 10:22 ET

Prices: F 12.62 · **SOFI 15.96 (−8.2%)** · T 22.06 · PFE 31.30 · NU 11.51

Manage: SOFI dropped below the $16 strike. The 12-04 16P marks at 0.945 (0.92/0.97) against 0.39 sold:
**−$55.50 unrealized** (new worst). Δ 0.47, 29 DTE. No stop loss in the rules, so hold. If SOFI is still below $16
on Dec 4, the paper account takes 100 shares at $16 (net cost $15.61 after the premium) and starts covered calls.

Dec 11 expiry (36 DTE), no new puts passed:
- PFE: 29P Δ0.19 OI 64, spread 39%; 30P Δ0.30 OI 32.
- F: 11.5P Δ0.19 OI 43, spread 35%; 12P Δ0.30 (0.304, just over).
- T: 20.5P Δ0.23 OI 18; 21P Δ0.25 OI 14, spread 125%.
Still blocked by earnings: NU (Nov 12 pm).

Open: SOFI 16P (−$55.50) · Realized premium: +$20.00 · Collateral needed: $1,600

### 2026-11-06 (Fri) 10:22 ET

Prices: F 12.67 · SOFI 16.36 (+2%) · T 21.84 · PFE 29.20 (ex-dividend today; adjusted change −0.9%) · NU 12.19

Manage: SOFI 12-04 16P marks at 0.76 (0.73/0.79) against 0.39 sold, so −$37 unrealized (from −$55.50). SOFI is back above
the strike by 2%. Hold.

Dec 11 expiry (35 DTE), no new puts passed:
- PFE: 27P Δ0.15 spread 190%; 28P Δ0.29 OI 255, spread 30%; 29P Δ0.44.
- F: 11.5P Δ0.21 spread 96%; 12P Δ0.31.
- T: 20.5P Δ0.24 OI 21; 21P Δ0.32.
Still blocked by earnings: NU (Nov 12 pm).

Open: SOFI 16P (−$37) · Realized premium: +$20.00 · Collateral needed: $1,600

#### Week 3 summary (Nov 2–6)

- Premium: +$20.00 realized all test (no trades closed this week). Trades opened this week: 0.
- Open risk: SOFI 16P Dec 4, $1,600 collateral. It swung +$1 → −$28 → +$4.50 → −$55.50 → −$37 as SOFI moved
  ±4–8% a day. Worst unrealized drawdown so far: −$55.50 (Nov 5). Net test PnL today: +$20 − $37 = −$17.
- Notable: SOFI traded below the strike on Nov 5. This is the first real test of the wheel's "accept assignment"
  path; the Dec 4 expiry falls after the test ends, so the final review will show it still open.
- The rules found nothing new all week: weekly expiries (Dec 11) have very low open interest, and F/T/PFE spreads
  stay wide. Over 3 weeks only SOFI has passed the filters, so the test is running on one ticker.

### 2026-11-09 (Mon) 10:23 ET

Prices: F 12.49 · SOFI 16.69 (+3%) · T 21.61 · PFE 29.16 · NU 12.21

Manage: SOFI 12-04 16P marks at 0.58 (0.56/0.60) against 0.39 sold, so −$19 unrealized (25 DTE). Hold.

Dec 11 expiry (32 DTE; Dec 18 at 39 is further from 35), no new puts passed:
- PFE: 27P Δ0.17 OI 56; 28P Δ0.28 OI 449, spread 43%.
- F: 11.5P Δ0.21 OI 124, spread 24% (closest F has come); 12P Δ0.33.
- T: 20.5P Δ0.28 OI 24, spread 84%; 21P Δ0.34.
Still blocked by earnings: NU (reports Thu Nov 12 pm).

Open: SOFI 16P (−$19) · Realized premium: +$20.00 · Collateral needed: $1,600
