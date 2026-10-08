# memebot — Solana memecoin scanner & trading bot

Finds momentum memecoins on Solana, screens them for rug risk, and trades them with
strict exits and risk limits. **Runs in paper-trading mode by default.**

> ⚠️ Most memecoins go to zero, and many are outright scams. This bot reduces some
> risks (honeypot-style mint/freeze authority, liquidity pulls, chasing pumps). It cannot
> remove them, and it guarantees no profit. Paper trade first, and use only money you
> can lose completely, in a dedicated hot wallet.

## How it works

Every `poll_seconds` the bot:

1. **Manages open positions.** It fetches fresh prices and sells on:
   - **liquidity collapse** (LP pulled ≥ 50% since entry → likely rug)
   - **stop loss** (−25%)
   - **trailing stop** (−20% from the peak, once the position has been up ≥ 30%)
   - **max hold time** (4h)
   - **take-profit tiers** (sell 50% at +50%, another 25% at +150%, then let the rest run)
2. **Finds new entries.** It pulls newly listed and boosted Solana tokens from
   [DexScreener](https://docs.dexscreener.com/api/reference), then filters on liquidity,
   market cap, age, 1h volume, 5m buy/sell pressure and price momentum, while skipping
   tokens that just went vertical. It ranks by volume turnover × buy pressure.
3. **Screens safety** with [RugCheck](https://api.rugcheck.xyz/swagger/index.html). It
   rejects tokens flagged `danger` (e.g. mint/freeze authority still enabled), tokens
   marked as rugged, and tokens with a high risk score.
4. **Applies risk limits**: fixed position size, max open positions, max total
   exposure, a daily loss limit that stops new entries, and a re-entry cooldown.
5. **Executes** through the paper simulator (slippage + fees modelled) or through
   real [Jupiter](https://dev.jup.ag/docs/swap-api) swaps signed locally.

State (positions, trade history) lives in `state.json`, so you can restart the bot safely.

## Quick start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
cp config.example.yaml config.yaml      # tune filters / exits / risk here

memebot scan                 # show current candidates + safety verdicts, no trading
memebot run                  # paper trade (Ctrl+C to stop)
memebot status               # open positions, win rate, PnL
pytest                       # run the tests
```

## Going live (only after paper results convince you)

1. `pip install -e '.[live]'`
2. Create a **new, dedicated wallet** and fund it with only what you're willing to lose.
3. Set `execution.mode: live` in `config.yaml`. Use a private RPC (Helius,
   QuickNode, Triton…), because the public endpoint is rate limited and slow.
4. `export SOLANA_PRIVATE_KEY=<base58 secret key>` (never commit it).
5. `memebot run --live` and type the confirmation phrase.

Live mode requires both the config setting and the flag, so it can't start by accident.

## Layout

| File | Purpose |
|---|---|
| `memebot/strategy.py` | entry filters, ranking, exit rules (pure functions, the place to tune) |
| `memebot/safety.py` | RugCheck screening |
| `memebot/dexscreener.py` | market data |
| `memebot/portfolio.py` | positions, PnL, risk limits, JSON persistence |
| `memebot/executors.py` | `PaperExecutor` and `JupiterExecutor` |
| `memebot/bot.py` | the trading loop |
| `memebot/cli.py` | `scan` / `run` / `status` commands |

## Limitations

- Paper PnL is measured in SOL and ignores SOL/USD moves during a hold. Paper fills
  use the DexScreener price, which lags real-time on-chain prices by seconds.
- Polling every ~30s cannot compete with sniper bots in a token's first seconds. This
  strategy deliberately waits ≥ 15 minutes after launch and trades momentum instead.
- Safety checks catch common contract-level scams. They miss coordinated dev/insider
  dumps and bundled launches.
