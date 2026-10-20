--!strict
-- Headless simulator: plays rounds against a scripted defense using the real match engine
-- (Shared.Sim.Engine), with no rendering, and reports pops, leaks and cash per round.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Engine = require(Shared.Sim.Engine)
local TowerData = require(Shared.Data.TowerData)
local Targeting = require(Shared.Sim.Targeting)
local Upgrades = require(Shared.Sim.Upgrades)

-- A defense script is an ordered list of actions. Each action waits until its round has
-- started being prepared AND the player can afford it; later actions wait behind it.
export type Action = {
	round: number,
	place: string?, -- tower id
	x: number?,
	z: number?,
	name: string, -- label used by later upgrade/target actions
	upgrade: Upgrades.PathKey?,
	target: Targeting.Mode?,
}

export type RoundReport = {
	round: number,
	pops: number,
	leaks: number,
	leakedLayers: number,
	cashEarned: number,
	cashAfter: number,
	livesAfter: number,
	maxEnemies: number,
	seconds: number,
	towers: number,
}

export type Report = {
	rounds: { RoundReport },
	result: "won" | "lost" | "stopped",
	finalRound: number,
	errors: { string },
}

export type Options = {
	rounds: { Engine.Round },
	defense: { Action },
	fromRound: number?,
	toRound: number?,
	startingCash: number?,
	dt: number?,
	maxRoundSeconds: number?,
}

local PLAYER = 1

local Simulator = {}

local function tryAction(state: Engine.State, action: Action, named: { [string]: number }, errors: { string }): boolean
	local player = state.players[PLAYER]
	if action.place then
		local def = TowerData[action.place]
		if not def or player.cash < def.cost then
			return false
		end
		local tower, err = Engine.placeTower(state, PLAYER, action.place, action.x or 0, action.z or 0)
		if not tower then
			table.insert(errors, `place {action.name}: {err}`)
			return true -- invalid placements are script bugs; skip instead of blocking forever
		end
		named[action.name] = tower.uid
		return true
	end
	local uid = named[action.name]
	if not uid then
		table.insert(errors, `unknown tower {action.name}`)
		return true
	end
	if action.upgrade then
		local tower = state.towerByUid[uid]
		local tier = Upgrades.nextTier(tower.def, tower.tiers, action.upgrade)
		if not tier then
			table.insert(errors, `upgrade {action.name} {action.upgrade}: not allowed`)
			return true
		end
		if player.cash < tier.cost then
			return false
		end
		Engine.upgradeTower(state, PLAYER, uid, action.upgrade)
		return true
	end
	if action.target then
		Engine.setTargeting(state, PLAYER, uid, action.target)
	end
	return true
end

function Simulator.run(options: Options): Report
	local dt = options.dt or Config.SIM_DT
	local toRound = options.toRound or #options.rounds
	local state = Engine.new({ rounds = options.rounds, totalRounds = toRound, emitEvents = false })
	Engine.addPlayer(state, PLAYER, options.startingCash)
	if options.fromRound and options.fromRound > 1 then
		Engine.jumpToRound(state, options.fromRound)
	end

	local pending = table.clone(options.defense)
	local named: { [string]: number } = {}
	local errors: { string } = {}
	local function runActions()
		while #pending > 0 and pending[1].round <= state.round + 1 do
			if not tryAction(state, pending[1], named, errors) then
				break
			end
			table.remove(pending, 1)
		end
	end

	local report: Report = { rounds = {}, result = "stopped", finalRound = 0, errors = errors }
	local maxSeconds = options.maxRoundSeconds or 600
	while Engine.canStartRound(state) do
		runActions()
		local player = state.players[PLAYER]
		local earnedBefore = player.cashEarned
		local popsBefore, leaksBefore, layersBefore = state.stats.pops, state.stats.leaks, state.stats.leakedLayers
		state.stats.maxEnemies = 0
		Engine.startRound(state)
		local roundNumber = state.round
		local elapsed = 0
		local nextActionCheck = 1
		while state.phase == "wave" and elapsed < maxSeconds do
			Engine.step(state, dt)
			elapsed += dt
			if elapsed >= nextActionCheck then
				nextActionCheck += 1
				runActions()
			end
		end
		table.insert(report.rounds, {
			round = roundNumber,
			pops = state.stats.pops - popsBefore,
			leaks = state.stats.leaks - leaksBefore,
			leakedLayers = state.stats.leakedLayers - layersBefore,
			cashEarned = player.cashEarned - earnedBefore,
			cashAfter = player.cash,
			livesAfter = state.lives,
			maxEnemies = state.stats.maxEnemies,
			seconds = elapsed,
			towers = #state.towers,
		})
		report.finalRound = roundNumber
		if state.phase == "lost" then
			report.result = "lost"
			return report
		elseif state.phase == "won" then
			report.result = "won"
			return report
		elseif state.phase == "wave" then
			table.insert(errors, `round {roundNumber} timed out`)
			return report
		end
	end
	if state.round >= toRound then
		report.result = "won"
	end
	return report
end

-- Plays a single round against a fixed tower setup that is built for free.
function Simulator.runRound(rounds: { Engine.Round }, round: number, setup: { Action }): RoundReport
	local defense: { Action } = {}
	for _, a in setup do
		local copy = table.clone(a)
		copy.round = round
		table.insert(defense, copy)
	end
	local report = Simulator.run({
		rounds = rounds,
		defense = defense,
		fromRound = round,
		toRound = round,
		startingCash = 1e9,
	})
	return report.rounds[1]
end

function Simulator.format(report: Report): string
	local lines = { "round  pops  leaks  lostLives  cash+   cash   lives  peak  secs  towers" }
	for _, r in report.rounds do
		table.insert(
			lines,
			string.format(
				"%5d %5d %6d %10d %6d %6d %7d %5d %5.0f %7d",
				r.round,
				r.pops,
				r.leaks,
				r.leakedLayers,
				r.cashEarned,
				r.cashAfter,
				r.livesAfter,
				r.maxEnemies,
				r.seconds,
				r.towers
			)
		)
	end
	table.insert(lines, `result: {report.result} at round {report.finalRound}`)
	for _, err in report.errors do
		table.insert(lines, "error: " .. err)
	end
	return table.concat(lines, "\n")
end

return Simulator
