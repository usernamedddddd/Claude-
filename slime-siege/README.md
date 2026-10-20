# Slime Siege

Co-op (1–4 players) tower defense for Roblox. Layered slimes walk the path through **Candy Garden**. Each pop strips a layer, so one big slime turns into a chain of smaller ones. There are six towers, each with two 3-tier upgrade paths. Each player has their own cash and the team shares 150 lives.

Built with Rojo and Luau. Every file uses `--!strict`, there are no `_G` globals, and all code lives in ModuleScripts. The only third-party package is TestEZ.

## Quick start

```bash
rokit install                    # or install the versions in rokit.toml by hand
wally install                    # TestEZ -> DevPackages (only for running specs in Studio)
rojo serve                       # then connect from Studio and press Play
```

* **Studio role.** The Workspace attribute `StudioMode` is `"match"` by default. Set it to `"lobby"` to test the lobby. Live servers pick their role on their own. Reserved servers run matches and public servers run the lobby.
* **Multiplayer test (M3).** Use Studio > Test > Clients and Servers with 4 players.
* **Debug panel.** The DEBUG button at the top left only exists in Studio. It gives cash, jumps to a round, spawns any slime (camo optional), sets lives, gives Goo and unlocks all towers.
* **Saving in Studio.** Enable *Game Settings > Security > Studio Access to API Services*. Without it the game uses a temporary profile that is never saved.

### Headless tools (Lune)

| Command | What it does |
|---|---|
| `lune run tools/test` | Runs every `tests/*.spec.luau` (TestEZ API) headless. This includes the simulator acceptance test. |
| `lune run tools/generate_rounds` | Regenerates `src/shared/Data/Rounds.luau` and prints the difficulty curve. It fails if the curve breaks the rules. |
| `lune run tools/simulate [N]` | Plays the reference defense through rounds 1..N and prints pops, leaks and cash for each round. |
| `lune run tools/bench` | Measures server step and snapshot cost with about 300 slimes and 30 towers. |
| `lune run tools/smoke [scenario]` | Emulated playtests: builds the place and runs the real server Script and client LocalScript against mocked engine services. Scenarios: `solo`, `fuzz`, `coop`, `data`, `lobby`. |

`tools/lib/Loader.luau` builds a virtual DataModel from `default.project.json`. That lets the same `require(script.Parent.X)` modules and spec files run in both Lune and Studio. In Studio, the specs run when the Workspace attribute `RunTests = true` is set and `wally install` has been run.

## Layout

```
src/shared/            ReplicatedStorage.Shared
  Data/                Config, SlimeData, TowerData (all tower numbers), MapData, Rounds (generated), Products, Theme
  Sim/                 Engine (the authoritative match simulation), Path, Targeting, Upgrades, Placement,
                       Difficulty, Votes, Rewards: pure logic with no Roblox APIs
  Net/                 Remotes registry, Packet (binary 10 Hz snapshot)
  Visual/TowerModels   primitive-part tower models (used by the server and the placement ghost)
src/server/            ServerScriptService.Server
  Main.server.luau     picks lobby or match, then starts the services
  Services/            MatchService, DataService, LobbyService, MonetizationService, Analytics,
                       Guard (validation + rate limits), MapBuilder, DebugService (Studio only)
src/client/            StarterPlayerScripts.Client: renders and sends requests, never decides anything
  Controllers/         EnemyRenderer, Effects, CameraController, Placement, HUD, TowerPanel, LobbyUI,
                       Store, Monetization, Sound, UI kit, DebugPanel
src/content/           ServerStorage.Content: RoundGenerator, Simulator (content pipeline)
tests/                 ServerStorage.Tests: TestEZ specs + ReferenceDefense
tools/                 Lune CLIs and the headless loader / TestEZ-compatible runner
```

## How it works

* **One simulation for everything.** `Sim/Engine` is deterministic and has no Roblox dependencies. The server steps it at a fixed 30 Hz (twice per tick at 2×). The headless simulator runs the same code, so balance numbers from `tools/simulate` match what players get.
* **Enemies are data.** Each slime is a record holding its distance along the path. There are no physics parts. The server sends one binary snapshot to clients 10 times a second. A snapshot holds spawn/pop/leak/attack events plus `(id, distance, flags)` for every slime, at 7 bytes per slime. Clients interpolate between snapshots and move pooled Ball parts with a single `Workspace:BulkMoveTo` per frame.
* **Combat is hitscan on the server.** Projectiles are only visuals. Targeting modes are First, Last, Strong and Close. Damage that exceeds a layer carries into the first child slime. Immunities: Black slimes ignore explosive damage and Metal slimes ignore sharp damage. Camo slimes can only be targeted by towers that detect camo, either through their own upgrade or the Wizard Owl's aura.
* **The server is authoritative.** Every remote is rate-limited and validated for type, range (NaN and infinity rejected), ownership and plausibility. Cash, damage, placement and round results never come from the client. The Debug remote is only created in Studio.
* **Data.** DataService uses `UpdateAsync` only, with a session lock (JobId plus timestamp), retries with backoff, staggered autosaves, saves on PlayerRemoving and BindToClose, and versioned migrations. In a live server, a player whose profile fails to load is kicked rather than given a default profile.
* **Purchases.** Clients call `Monetization.promptPurchase(productKey, onGranted)`. Product IDs are 0 for now: Studio prints and grants the item, live servers answer "coming soon". The `ProcessReceipt` and game-pass code paths are already written for when real IDs are added.
* **Analytics.** Everything goes through `Analytics.track(event, data)`, which is currently a stub that buffers events and prints them in Studio. It covers all 9 events from the spec.

## UI design (Figma)

The whole UI is designed in Figma first: **Slime Siege UI**, https://www.figma.com/design/QeUFsylb3ObuML5Z1agJr7.
- **Design System page:** color tokens with contrast ratios (all text pairs are at least 4.5:1, for example white on green 5.2:1 and ink on gold 10.5:1), Fredoka One text styles, the Chunky shadow, the components (Button, IconButton, StatPill, HotbarSlot, TowerCard) and 19 vector icons.
- **Screens page:** desktop match HUD with the tower panel, victory and defeat results, lobby with the tower shop, phone HUD (844×390), round-start banner, and the **Motion spec** (every animation's trigger, timing and easing).
- **In the game:** `Data/Theme.luau` holds the tokens and motion timings. `Controllers/UI.luau` builds the chunky surfaces, press-in buttons, pills, chips and bars, and scales the 1920×1080 design to any screen. `Controllers/Motion.luau` runs the animations and respects Reduced Motion. `HUD`, `TowerPanel`, `Results` and `LobbyUI` are built from the screens.
- **Icons:** in Figma, select the `Icons` frame on the Design System page and export all `Icon/*` components as PNG @2x. Upload them in Studio (Asset Manager > Images) and paste the ids into `Theme.Icons`. Until then the game shows emoji.

## Interpretations of the spec (please confirm)

* **What "layers" means.** The table's *Layers* column is used as the lives lost on a leak and as the difficulty weight. Each normal slime takes one hit to pop, and the Boss has 200 HP. The table is not internally additive (a Black is worth 6 but splits into 2× Pink = 8), and I used its numbers as given.
* **Ice Penguin damage.** The spec gives no number, so freezing pulses deal 1 cold damage. Bosses cannot be frozen or stunned. Permafrost's slow aura does affect bosses.
* **Camo.** Splash and pierce also skip camo slimes for towers without detection, which keeps "only detect-camo towers can see it" strict.
* **Majority vote.** A vote needs a strict majority: 1 of 1, 2 of 2, 2 of 3, 3 of 4.
* **Round 1 countdown.** Round 1 has a 20-second prep countdown, also skippable by vote. After a lobby teleport it also waits up to 15 seconds for the rest of the party. Every other gap uses the 5-second countdown.
* **Leavers.** Towers owned by a player who leaves keep fighting, but nobody receives their pop money.
* **Bank Bee.** Income goes only to the owner unless the Bee has Path B. This is the default from §12.

## Milestone report

### M0: content tool ✅ passed (verified headless)

* The generator produces 40 rounds. Difficulty rises every round, by +14.4% per round up to the round-20 boss and +22.6% per round after it, so it never exceeds +30%. Bosses appear in rounds 20 and 40. Camo rounds start at round 12.
* The simulator runs the reference defense (`tests/ReferenceDefense.luau`, one player, buying only with earned cash) through **rounds 1–20 with 0 leaks**. All 20 rounds take 0.16 s to simulate.
* The full curve with the solo reference build: the build loses at round 36 with about $11k left unspent, so rounds 21–40 should push a full team.
* `lune run tools/test`: **55 passed, 0 failed**. The specs cover layer splitting, immunities, the crosspath rule, sell refunds and the economy, the round generator (including a check that `Rounds.luau` is in sync), the simulator acceptance test, targeting, placement, votes, the snapshot protocol and rewards.
* `luau-lsp analyze` in strict mode on `src` and `tests`: **0 errors**. `rojo build` produces a working `.rbxl`.

### Emulated playtests ✅ (`lune run tools/smoke`)

`tools/emu/Runtime.luau` loads the place built by Rojo with Lune's Roblox library and runs the **real** scripts. It replaces the engine services with mocks: a virtual-clock scheduler, per-machine client contexts, remotes that copy arguments as the network does, DataStore, Teleport, input and raycasts. It catches script errors, wiring mistakes and logic bugs. It does not test rendering, physics, feel or performance.

| Scenario | Checks | What it covers |
|---|---|---|
| `solo` | 46/46 | UI placement (hotbar → ghost → click; refused on the path), upgrade panel, targeting button, hotkeys, round 1 auto-starting, rendering slimes, skip and 2× votes, debug remote, boss round with pop burst, win at round 40, Goo reward, results card, Studio reset |
| `fuzz` | 6/6 | 1,728 garbage calls (nil, NaN, ±inf, huge strings, tables, buffers, wrong types) to every remote: no script errors, nothing placed or bought, rate limits trip |
| `coop` | 18/18 | 4 players: separate cash, can't upgrade or sell a teammate's tower, 2/4 vs 3/4 skip and speed majorities, read-only teammate panel, a player leaving mid-wave, round bonus to all |
| `data` | 14/14 | Live mode: profile created and session-locked, lock released on leave, kicked (and data untouched) when another server holds the lock, stale lock taken over, kicked on DataStore outage, BindToClose flush, no Debug remote |
| `lobby` | 12/12 | Live lobby: Goo unlocks (and refusal without enough Goo), unconfigured products refused, 2 players on the pad teleport together with a reserved code and party data |

Bugs these runs found and fixed: round 1 never auto-started unless the lobby had sent party data (`partyDeadline` defaulted to infinity). Studio's template Baseplate and SpawnLocation now get removed so they don't z-fight with the map.

### M1–M5: code complete, emulator-tested, not yet playtested in Studio ⚠️

I had no Roblox Studio in this environment, so **I have no Studio screenshots or playtest results** for M1–M5, and the 4-client M3 test has not been run. Everything compiles under strict typing and builds into a place file. The gameplay logic underneath is the same unit-tested engine. Rendering, UI layout, input feel and DataStore/Teleport behaviour still need a Studio pass:

| Milestone | Built | Check in Studio |
|---|---|---|
| M1 graybox loop | Place, start, pop, earn, win at 40 or lose at 0 lives. Studio restarts the match after the results card. | A full solo run. Use the debug panel's round jump to reach 40 quickly. |
| M2 full tower set | 6 towers × 2 paths × 3 tiers, crosspath rule, targeting cycle, sell | Every upgrade, Hot Blades against Metal slimes, Camo Vision aura |
| M3 co-op | Separate cash, shared lives, team list, skip and 2× votes | Test > 4 clients: votes, cash, panel ownership |
| M4 juice | Pop particles and a squish on every layer pop, screen shake on Boss pop, placement thump with squash and stretch, upgrade sparkle, aggregated "+$N" popups, hopping slimes | Record the 10-second muted clip |
| M5 meta | Lobby queue pad → reserved server, Goo/XP rewards, Goo unlocks, saving with a session lock | Requires a published place for TeleportService and DataStores |

**Performance** (`tools/bench`, Luau VM in Lune): one engine step with 315 slimes and 30 towers takes 0.31 ms, which is about 1.9% of a CPU core at 2× speed. A snapshot is about 2.2 KB for 315 slimes, so roughly 25 KB/s per client. On the client, slimes and projectiles are pooled parts moved with one `BulkMoveTo` call each per frame. Pop bursts are capped at 40 per frame and sounds are throttled. FPS on a mid-range phone has **not** been measured yet.

## Known risks / next steps

1. **Co-op balance.** The fixed numbers (each player gets $650 plus the full round bonus) give a 4-player team about 4× a solo player's cash by round 20, while rounds stay the same. Either scale income or slime HP by player count, or accept that co-op is easier. This needs a decision.
2. **Late-round density.** At rounds 37–40 a strong team can reach about 325 slimes at once, just over the 300-on-screen target. Profile this on a real phone.
3. **Art and audio.** Towers and slimes are built from primitive parts. Sounds are built-in `rbxasset://` placeholders and icons are emoji. Upload the gvesster icon pack and fill in `Data/Theme.luau` (no code changes needed).
4. **Selene.** Its Roblox standard library couldn't be downloaded here, so Selene was not run. Strict luau-lsp type checking was run.
