--!strict
-- `lune run tools/bench` — server cost of one simulation step and one snapshot encode with
-- 300 slimes on the path and 30 towers, plus a 4-player co-op economy comparison.

local process = require("@lune/process")
local Loader = require("./lib/Loader")

local env = Loader.load(process.cwd)
local function load(path: string): any
	return env.require(Loader.find(env, path))
end
local Engine = load("ReplicatedStorage.Shared.Sim.Engine")
local Packet = load("ReplicatedStorage.Shared.Net.Packet")
local Config = load("ReplicatedStorage.Shared.Data.Config")

-- Steady state: keep ~300 slimes alive (respawn what gets popped) under 30 towers.
local state = Engine.new({ rounds = { {} } })
Engine.addPlayer(state, 1, 1e9)
local spots = {
	{ -4, -29 },
	{ -34, 19 },
	{ 26, 24 },
	{ -16, 19 },
	{ -4, 10 },
	{ 14, -29 },
	{ 56, -4 },
	{ -28, 15 },
	{ 44, 5 },
	{ -70, -24 },
	{ -46, 0 },
	{ -34, -10 },
	{ -4, -10 },
	{ 14, 10 },
	{ 26, 10 },
	{ 44, 20 },
	{ 26, -20 },
	{ -16, 0 },
	{ 56, 4 },
	{ -60, -36 },
	{ -46, 20 },
	{ -22, 31 },
	{ 8, -41 },
	{ 14, 36 },
	{ 44, 36 },
	{ 62, -16 },
	{ -52, -24 },
	{ 26, -30 },
	{ -16, -20 },
	{ 56, 22 },
}
local kinds = { "DartFrog", "CannonCrab", "IcePenguin", "SpikeTurtle", "WizardOwl" }
local placed = 0
for i, s in spots do
	local tower = Engine.placeTower(state, 1, kinds[(i - 1) % #kinds + 1], s[1], s[2])
	if tower then
		placed += 1
		Engine.upgradeTower(state, 1, tower.uid, "A")
		Engine.upgradeTower(state, 1, tower.uid, "A")
		Engine.upgradeTower(state, 1, tower.uid, "B")
	end
end
local function refill()
	local i = 0
	while #state.enemies < 300 do
		i += 1
		Engine.spawnSlime(
			state,
			if i % 3 == 0 then "Rainbow" else "Pink",
			i % 5 == 0,
			(i * 7.3) % (state.path.totalLength * 0.9)
		)
	end
end
refill()
Engine.drainEvents(state)

local STEPS = 900
local stepTime, encodeTime = 0, 0
local maxEvents = 0
local counts: { [string]: number } = {}
for i = 1, STEPS do
	refill()
	local t0 = os.clock()
	Engine.step(state, Config.SIM_DT)
	stepTime += os.clock() - t0
	if i % 3 == 0 then
		local events = Engine.drainEvents(state)
		maxEvents = math.max(maxEvents, #events)
		for _, e in events do
			counts[e.t] = (counts[e.t] or 0) + 1
		end
		local t1 = os.clock()
		Packet.encodeSnapshot(events, state.enemies)
		encodeTime += os.clock() - t1
	end
end
local events = Engine.drainEvents(state)
local packet = Packet.encodeSnapshot(events, state.enemies)
print(string.format("towers placed: %d, slimes alive: %d", placed, #state.enemies))
print(
	string.format("Engine.step: %.3f ms avg (%d steps @ %d Hz sim)", stepTime / STEPS * 1000, STEPS, 1 / Config.SIM_DT)
)
print(
	string.format(
		"snapshot encode: %.3f ms avg, %d bytes for %d slimes (+%d events max)",
		encodeTime / (STEPS / 3) * 1000,
		buffer.len(packet),
		#state.enemies,
		maxEvents
	)
)
local msPerSecond2x = stepTime / STEPS * 1000 * 60 -- 2x speed = 60 steps per real second
print(string.format("server CPU at 2x speed: %.1f ms per second (%.1f%%)", msPerSecond2x, msPerSecond2x / 10))

local parts = {}
for t, n in counts do
	table.insert(parts, `{t}={math.floor(n / (STEPS / 3))}`)
end
table.sort(parts)
print("avg events per snapshot: " .. table.concat(parts, " "))

-- Co-op economy: total team cash available by round 20 for 1 vs 4 players.
local roundBonusTotal = 0
for r = 1, 19 do
	roundBonusTotal += Config.ROUND_BONUS_BASE + r
end
print(
	string.format(
		"co-op economy by round 20 (excl. pops): solo $%d, 4 players $%d team total",
		Config.STARTING_CASH + roundBonusTotal,
		4 * (Config.STARTING_CASH + roundBonusTotal)
	)
)
