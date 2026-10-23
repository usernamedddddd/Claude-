# wheelbot — options wheel bot for Robinhood

Trades the **wheel**: sell cash-secured puts on stocks you'd be happy to own. If a put is
assigned, sell covered calls on the shares until they're called away, then start over.
**Runs in paper-trading mode by default** (real Robinhood market data, simulated fills).

> ⚠️ Options can lose money fast. The wheel's main risk is a stock falling hard: you're
> assigned at the strike and left holding shares worth far less, and the premium only
> cushions that. This bot follows rules and limits. It can't predict anything, and
> it guarantees no profit. Paper trade first, start with one contract, and only wheel
> stocks you'd hold through a 30–50% drop.

> ⚠️ Robinhood has **no official options API**. This uses the community
> [`robin_stocks`](https://github.com/jmfernandes/robin_stocks) library, which calls
> Robinhood's private endpoints. These can change or break without notice, and automated
> trading may conflict with Robinhood's Customer Agreement. You accept that risk.

## How it works

Every `poll_seconds` (default 5 min), during market hours (skipping the first 15 and last
10 minutes), the bot:

1. **Reconciles.** It notices short options that disappeared since the last cycle
   (expired, assigned or called away) and logs them.
2. **Manages open shorts.** It buys an option back when it hits:
   - **take profit**: 50% of the credit captured (configurable)
   - **stop loss**: option worth N× the credit (off by default, because the wheel
     normally accepts assignment)
   - **close at DTE**: optional, e.g. 7 days before expiry
3. **Sells covered calls** on every free 100 shares, at about 0.30 delta and 21–45 DTE,
   and **never below your cost basis**, so being called away never locks in a stock loss.
4. **Sells one cash-secured put per ticker** at about 0.25 delta and 21–45 DTE (closest
   to 35). The contract must pass these filters:
   - minimum annualized yield
   - minimum bid
   - minimum open interest
   - maximum bid/ask spread
   - **no earnings report before expiry**
5. **Applies risk limits**: per-ticker cap (put collateral + stock cost), total cap, a
   cash reserve, and a fixed number of contracts per trade. It never sells a naked call,
   and it never uses margin as collateral (it uses the smaller of buying power and
   withdrawable cash).
6. **Places limit orders at the mid** (rounded to a valid tick, never crossing the
   market), good for the day. An order that hasn't filled after `order_timeout_seconds` is
   cancelled and retried next cycle at the fresh mid.

The bot's trade ledger lives in `state.json`. In paper mode the simulated account lives
in `paper_account.json`. In live mode, Robinhood's actual positions are the source of
truth on every cycle, so restarts are safe.

## Quick start

```bash
cd options-wheel
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
cp config.example.yaml config.yaml          # set your tickers and limits

export RH_USERNAME=you@example.com
export RH_PASSWORD='...'
export RH_MFA_SECRET=BASE32SECRET            # optional: the TOTP secret from Robinhood's
                                             # "authenticator app" 2FA setup (lets the bot
                                             # log in unattended)

wheelbot login        # verify login and see your real account (no trading)
wheelbot scan         # contracts the bot would sell right now, with yield/delta
wheelbot run          # paper trade (Ctrl+C to stop); --once for a single cycle
wheelbot status       # positions, premium collected, recent trades
pytest                # run the tests (no network)
```

The login session is cached by robin_stocks in `~/.tokens/`. If Robinhood asks for
device approval in the app, approve it once, and later logins reuse the session.

Paper mode still needs a login, because option chains, greeks and quotes come from
Robinhood.

## Going live (only after paper results convince you)

1. Your account needs **options level 2** (cash-secured puts and covered calls).
2. Prefer a dedicated account, or tickers you don't trade by hand. **The bot manages
   any short option on a configured ticker, including ones you opened yourself.** Set
   `RH_ACCOUNT_NUMBER` to pick an account if you have several.
3. Set `execution.mode: live` in `config.yaml`.
4. `wheelbot run --live` and type the confirmation phrase.

Live mode requires both the config setting and the flag, so it can't start by accident.

## Choosing tickers

Wheel liquid, optionable stocks or ETFs that you would genuinely hold. One contract
controls 100 shares, so a $45 stock needs $4,500 of cash per put. Raise
`max_per_ticker_usd` / `max_total_collateral_usd` to fit your account. The example
tickers are placeholders, not recommendations.

## Layout

| File | Purpose |
|---|---|
| `wheelbot/strategy.py` | expiry/strike selection, filters, exit rules, tick rounding (pure functions, the place to tune) |
| `wheelbot/bot.py` | the wheel loop and risk limits |
| `wheelbot/broker.py` | `RobinhoodBroker`: market data, account and orders via robin_stocks |
| `wheelbot/paper.py` | `PaperBroker`: simulated account, fills, assignment and expiry |
| `wheelbot/ledger.py` | the bot's trade log, JSON persistence |
| `wheelbot/cli.py` | `login` / `scan` / `run` / `status` commands |

## Limitations

- **No rolling.** A tested put is held to expiry and assigned, unless a stop loss or
  `close_at_dte` closes it first. Rolling logic would go in `Bot.manage`.
- **Paper fills are optimistic.** Every order fills instantly at the mid. Real fills are
  often worse, and a mid-price order may not fill at all on illiquid contracts.
- **Paper settlement** uses the last stock price the bot saw on expiration day, and
  ignores early assignment, dividends and after-hours moves.
- **Early assignment** in live mode shows up as a `GONE` ledger entry, and the bot then
  starts selling calls on the shares.
- Ledger PnL counts option premium only. For full PnL including stock gains and losses,
  check Robinhood.
