--!strict
-- Headless, deterministic match simulation. The server runs this every frame; the content
-- pipeline's simulator runs the exact same code in Lune. No Roblox APIs are used here.
--
-- Enemies are plain records tracked by distance along the path (no physics parts).
-- The engine appends render/network events to `state.events`; the owner drains them.

local Config = require(script.Parent.Parent.Data.Config)
local MapData = require(script.Parent.Parent.Data.MapData)
local SlimeData = require(script.Parent.Parent.Data.SlimeData)
local TowerData = require(script.Parent.Parent.Data.TowerData)
local Path = require(script.Parent.Path)
local Placement = require(script.Parent.Placement)
local Targeting = require(script.Parent.Targeting)
local Upgrades = require(script.Parent.Upgrades)

export type RoundGroup = {
	slimeType: string,
	count: number,
	spacingSeconds: number,
	delay: number,
	camo: boolean?,
}
export type Round = { RoundGroup }

export type Phase = "prep" | "wave" | "intermission" | "won" | "lost"

export type Enemy = {
	id: number,
	kind: string,
	def: SlimeData.SlimeDef,
	layers: number,
	hp: number,
	distance: number,
	x: number,
	z: number,
	camo: boolean,
	frozen: number,
	stunned: number,
	brittle: number,
	slow: number,
	alive: boolean,
}

export type Tower = {
	uid: number,
	id: string,
	def: TowerData.TowerDef,
	owner: number,
	x: number,
	z: number,
	footprint: number,
	tiers: Upgrades.Tiers,
	spent: number,
	targeting: Targeting.Mode,
	stats: TowerData.TowerStats,
	cooldowns: { number },
	seesCamo: boolean,
	pops: number,
}

export type PlayerState = {
	key: number,
	cash: number,
	pops: number,
	cashEarned: number,
	allowedTowers: { [string]: boolean }?,
}

export type Event = { [string]: any }

type SpawnCursor = { group: RoundGroup, spawned: number, nextAt: number }

export type State = {
	map: MapData.MapDef,
	path: Path.Path,
	rounds: { Round },
	totalRounds: number,
	time: number,
	lives: number,
	round: number,
	phase: Phase,
	nextEnemyId: number,
	nextTowerUid: number,
	enemies: { Enemy },
	enemyById: { [number]: Enemy },
	towers: { Tower },
	towerByUid: { [number]: Tower },
	players: { [number]: PlayerState },
	playerCount: number,
	cursors: { SpawnCursor },
	waveTime: number,
	events: { Event },
	emitEvents: boolean,
	-- Running totals, handy for the simulator and analytics.
	stats: { pops: number, leaks: number, leakedLayers: number, maxEnemies: number },
}

export type Options = {
	map: MapData.MapDef?,
	rounds: { Round },
	totalRounds: number?,
	lives: number?,
	emitEvents: boolean?,
}

local Engine = {}

function Engine.new(options: Options): State
	local map = options.map or MapData
	return {
		map = map,
		path = Path.build(map.waypoints),
		rounds = options.rounds,
		totalRounds = options.totalRounds or math.min(Config.TOTAL_ROUNDS, #options.rounds),
		time = 0,
		lives = options.lives or Config.STARTING_LIVES,
		round = 0,
		phase = "prep",
		nextEnemyId = 1,
		nextTowerUid = 1,
		enemies = {},
		enemyById = {},
		towers = {},
		towerByUid = {},
		players = {},
		playerCount = 0,
		cursors = {},
		waveTime = 0,
		events = {},
		emitEvents = if options.emitEvents == nil then true else options.emitEvents,
		stats = { pops = 0, leaks = 0, leakedLayers = 0, maxEnemies = 0 },
	}
end

local function emit(state: State, event: Event)
	if state.emitEvents then
		table.insert(state.events, event)
	end
end

function Engine.drainEvents(state: State): { Event }
	local events = state.events
	state.events = {}
	return events
end

---------------------------------------------------------------------------
-- Players & economy
---------------------------------------------------------------------------

function Engine.addPlayer(state: State, key: number, startingCash: number?): PlayerState
	local existing = state.players[key]
	if existing then
		return existing
	end
	local player: PlayerState = {
		key = key,
		cash = startingCash or Config.STARTING_CASH,
		pops = 0,
		cashEarned = 0,
		allowedTowers = nil,
	}
	state.players[key] = player
	state.playerCount += 1
	return player
end

-- Towers of a departed player keep defending; their pop money is simply not paid out.
function Engine.removePlayer(state: State, key: number)
	if state.players[key] then
		state.players[key] = nil
		state.playerCount -= 1
	end
end

function Engine.giveCash(state: State, key: number, amount: number)
	local player = state.players[key]
	if player then
		player.cash += amount
		player.cashEarned += math.max(amount, 0)
	end
end

local function roundEndPayout(state: State)
	local roundBonus = Config.ROUND_BONUS_BASE + state.round
	for key in state.players do
		Engine.giveCash(state, key, roundBonus)
	end
	for _, tower in state.towers do
		local s = tower.stats
		if s.income > 0 then
			local owner = state.players[tower.owner]
			if s.interestRate > 0 and owner then
				Engine.giveCash(state, tower.owner, math.min(s.interestCap, math.floor(owner.cash * s.interestRate)))
			end
			if s.shareIncome and state.playerCount > 0 then
				local share = math.floor(s.income / state.playerCount)
				for key in state.players do
					Engine.giveCash(state, key, share)
				end
			else
				Engine.giveCash(state, tower.owner, s.income)
			end
		end
		if s.teamBonus > 0 then
			for key in state.players do
				Engine.giveCash(state, key, s.teamBonus)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------

local function spawnEnemy(state: State, kind: string, distance: number, camo: boolean): Enemy
	local def = SlimeData[kind]
	assert(def, `unknown slime {kind}`)
	local x, z = Path.positionAt(state.path, distance)
	local enemy: Enemy = {
		id = state.nextEnemyId,
		kind = kind,
		def = def,
		layers = def.layers,
		hp = def.hp,
		distance = distance,
		x = x,
		z = z,
		camo = camo,
		frozen = 0,
		stunned = 0,
		brittle = 0,
		slow = 1,
		alive = true,
	}
	state.nextEnemyId += 1
	table.insert(state.enemies, enemy)
	state.enemyById[enemy.id] = enemy
	emit(state, { t = "spawn", id = enemy.id, slime = kind, camo = camo, distance = distance })
	return enemy
end

function Engine.spawnSlime(state: State, kind: string, camo: boolean?, distance: number?): Enemy
	return spawnEnemy(state, kind, distance or 0, camo == true)
end

function Engine.isImmune(def: SlimeData.SlimeDef, damageType: SlimeData.DamageType): boolean
	return def.immune[damageType] == true
end

local function killEnemy(state: State, enemy: Enemy)
	enemy.alive = false
	state.enemyById[enemy.id] = nil
end

-- Pops one layer: the slime is removed and its children appear at the same path position
-- (spread slightly backwards so they don't overlap). Returns the first child, if any.
local function popEnemy(state: State, enemy: Enemy, tower: Tower?): Enemy?
	killEnemy(state, enemy)
	state.stats.pops += 1
	if tower then
		tower.pops += 1
		local owner = state.players[tower.owner]
		if owner then
			owner.cash += Config.CASH_PER_LAYER
			owner.cashEarned += Config.CASH_PER_LAYER
			owner.pops += 1
		end
	end
	emit(state, {
		t = "pop",
		id = enemy.id,
		slime = enemy.kind,
		x = enemy.x,
		z = enemy.z,
		tower = if tower then tower.uid else 0,
		owner = if tower then tower.owner else 0,
	})
	local first: Enemy? = nil
	for i, childKind in enemy.def.children do
		local d = math.max(enemy.distance - (i - 1) * Config.CHILD_SPREAD, 0)
		local child = spawnEnemy(state, childKind, d, enemy.camo)
		if first == nil then
			first = child
		end
	end
	return first
end

export type HitSpec = {
	damage: number,
	damageType: SlimeData.DamageType,
	bossMultiplier: number,
	freeze: number,
	stun: number,
	brittle: number,
}

-- Applies one hit. Damage beyond the current layer carries into the first child.
-- Returns the number of layers popped.
function Engine.damage(state: State, enemy: Enemy, hit: HitSpec, tower: Tower?): number
	if not enemy.alive or Engine.isImmune(enemy.def, hit.damageType) then
		return 0
	end
	local amount = hit.damage
	if enemy.def.isBoss then
		amount *= hit.bossMultiplier
	end
	if enemy.brittle > 0 then
		amount += 1
	end
	local popped = 0
	local current: Enemy? = enemy
	while current and amount > 0 do
		if Engine.isImmune(current.def, hit.damageType) then
			break
		end
		if current.hp > amount then
			current.hp -= amount
			amount = 0
			break
		end
		amount -= current.hp
		popped += 1
		current = popEnemy(state, current, tower)
	end
	if current and current.alive and not current.def.freezeImmune then
		if hit.freeze > 0 then
			current.frozen = math.max(current.frozen, hit.freeze)
		end
		if hit.stun > 0 then
			current.stunned = math.max(current.stunned, hit.stun)
		end
	end
	if current and current.alive and hit.brittle > 0 then
		current.brittle = math.max(current.brittle, hit.brittle)
	end
	return popped
end

---------------------------------------------------------------------------
-- Towers
---------------------------------------------------------------------------

local function recomputeCamo(state: State)
	for _, tower in state.towers do
		local sees = tower.stats.camo
		if not sees then
			for _, other in state.towers do
				local r = other.stats.camoAura
				if r > 0 then
					local dx, dz = tower.x - other.x, tower.z - other.z
					if dx * dx + dz * dz <= r * r then
						sees = true
						break
					end
				end
			end
		end
		tower.seesCamo = sees
	end
end

local function syncCooldowns(tower: Tower)
	for i = #tower.cooldowns + 1, #tower.stats.attacks do
		tower.cooldowns[i] = 0
	end
end

function Engine.checkPlacement(state: State, towerId: string, x: number, z: number): (boolean, string?)
	local def = TowerData[towerId]
	if not def then
		return false, "Unknown tower"
	end
	return Placement.check(state.map, state.path, state.towers :: { any }, def.footprint, x, z)
end

function Engine.placeTower(state: State, key: number, towerId: string, x: number, z: number): (Tower?, string?)
	local player = state.players[key]
	local def = TowerData[towerId]
	if not player or not def then
		return nil, "Invalid request"
	end
	if state.phase == "won" or state.phase == "lost" then
		return nil, "Match is over"
	end
	if player.allowedTowers and not player.allowedTowers[towerId] then
		return nil, "Tower locked"
	end
	local owned = 0
	for _, t in state.towers do
		if t.owner == key then
			owned += 1
		end
	end
	if owned >= Config.MAX_TOWERS_PER_PLAYER then
		return nil, "Tower limit reached"
	end
	local ok, reason = Placement.check(state.map, state.path, state.towers :: { any }, def.footprint, x, z)
	if not ok then
		return nil, reason
	end
	if player.cash < def.cost then
		return nil, "Not enough cash"
	end
	player.cash -= def.cost
	local tiers: Upgrades.Tiers = { A = 0, B = 0 }
	local tower: Tower = {
		uid = state.nextTowerUid,
		id = towerId,
		def = def,
		owner = key,
		x = x,
		z = z,
		footprint = def.footprint,
		tiers = tiers,
		spent = def.cost,
		targeting = "First",
		stats = Upgrades.computeStats(def, tiers),
		cooldowns = {},
		seesCamo = false,
		pops = 0,
	}
	syncCooldowns(tower)
	state.nextTowerUid += 1
	table.insert(state.towers, tower)
	state.towerByUid[tower.uid] = tower
	recomputeCamo(state)
	emit(state, { t = "towerPlaced", uid = tower.uid })
	return tower, nil
end

function Engine.upgradeTower(state: State, key: number, uid: number, path: Upgrades.PathKey): (boolean, string?)
	local tower = state.towerByUid[uid]
	local player = state.players[key]
	if not tower or not player or tower.owner ~= key then
		return false, "Not your tower"
	end
	local tier = Upgrades.nextTier(tower.def, tower.tiers, path)
	if not tier then
		local _, reason = Upgrades.canUpgrade(tower.tiers, path)
		return false, reason
	end
	if player.cash < tier.cost then
		return false, "Not enough cash"
	end
	player.cash -= tier.cost
	tower.spent += tier.cost
	tower.tiers[path] += 1
	tower.stats = Upgrades.computeStats(tower.def, tower.tiers)
	syncCooldowns(tower)
	recomputeCamo(state)
	emit(state, { t = "towerUpgraded", uid = uid, path = path, tier = tower.tiers[path] })
	return true, nil
end

function Engine.sellTower(state: State, key: number, uid: number): (number?, string?)
	local tower = state.towerByUid[uid]
	if not tower or tower.owner ~= key or not state.players[key] then
		return nil, "Not your tower"
	end
	local refund = Upgrades.sellValue(tower.spent)
	Engine.giveCash(state, key, refund)
	state.towerByUid[uid] = nil
	local index = table.find(state.towers, tower)
	if index then
		table.remove(state.towers, index)
	end
	recomputeCamo(state)
	emit(state, { t = "towerSold", uid = uid })
	return refund, nil
end

function Engine.setTargeting(state: State, key: number, uid: number, mode: Targeting.Mode): boolean
	local tower = state.towerByUid[uid]
	if not tower or tower.owner ~= key then
		return false
	end
	tower.targeting = mode
	return true
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------

local function visibleTo(tower: Tower, enemy: Enemy): boolean
	return enemy.alive and (not enemy.camo or tower.seesCamo)
end

local function inRadius(enemy: Enemy, x: number, z: number, r: number): boolean
	local dx, dz = enemy.x - x, enemy.z - z
	return dx * dx + dz * dz <= r * r
end

-- Enemies near (x, z) sorted by distance, excluding those already hit this attack.
local function nearby(
	state: State,
	tower: Tower,
	x: number,
	z: number,
	r: number,
	hitSet: { [Enemy]: boolean }
): { Enemy }
	local list: { Enemy } = {}
	local dist: { [Enemy]: number } = {}
	for _, e in state.enemies do
		if not hitSet[e] and visibleTo(tower, e) then
			local dx, dz = e.x - x, e.z - z
			local d2 = dx * dx + dz * dz
			if d2 <= r * r then
				table.insert(list, e)
				dist[e] = d2
			end
		end
	end
	table.sort(list, function(a, b)
		return dist[a] < dist[b]
	end)
	return list
end

local function fireAttack(state: State, tower: Tower, attack: TowerData.AttackSpec): boolean
	local candidates: { Enemy } = {}
	for _, e in state.enemies do
		if visibleTo(tower, e) and inRadius(e, tower.x, tower.z, attack.range) then
			table.insert(candidates, e)
		end
	end
	if #candidates == 0 then
		return false
	end

	local hit: HitSpec = attack
	local hitSet: { [Enemy]: boolean } = {}

	if attack.kind == "nova" then
		local hits = 0
		for _, e in candidates do
			if hits >= attack.pierce then
				break
			end
			hits += 1
			Engine.damage(state, e, hit, tower)
		end
		emit(state, { t = "attack", tower = tower.uid, visual = attack.visual, x = tower.x, z = tower.z })
		return true
	end

	local primaries = Targeting.pick(candidates, tower.targeting, attack.projectiles, tower.x, tower.z)
	for _, primary in primaries do
		if not primary.alive then
			continue
		end
		local px, pz = primary.x, primary.z
		emit(state, { t = "attack", tower = tower.uid, visual = attack.visual, x = px, z = pz })

		local targets: { Enemy }
		if attack.splash > 0 then
			targets = nearby(state, tower, px, pz, attack.splash, hitSet)
		else
			targets = { primary }
			for _, e in nearby(state, tower, px, pz, Config.PIERCE_RADIUS, hitSet) do
				if e ~= primary then
					table.insert(targets, e)
				end
			end
		end
		for i = 1, math.min(attack.pierce, #targets) do
			hitSet[targets[i]] = true
			Engine.damage(state, targets[i], hit, tower)
		end

		if attack.clusters > 0 then
			local spots = nearby(state, tower, px, pz, attack.splash * 2 + Config.CLUSTER_RADIUS, {})
			for c = 1, math.min(attack.clusters, #spots) do
				local spot = spots[c]
				local cx, cz = spot.x, spot.z
				emit(state, { t = "attack", tower = tower.uid, visual = "cluster", x = cx, z = cz })
				local mini = nearby(state, tower, cx, cz, Config.CLUSTER_RADIUS, {})
				for i = 1, math.min(6, #mini) do
					Engine.damage(state, mini[i], hit, tower)
				end
			end
		end

		if attack.chain > 0 then
			local lx, lz = px, pz
			for _ = 1, attack.chain do
				local nextTargets = nearby(state, tower, lx, lz, Config.CHAIN_RADIUS, hitSet)
				local nextEnemy = nextTargets[1]
				if not nextEnemy then
					break
				end
				hitSet[nextEnemy] = true
				emit(state, { t = "chain", tower = tower.uid, x1 = lx, z1 = lz, x2 = nextEnemy.x, z2 = nextEnemy.z })
				lx, lz = nextEnemy.x, nextEnemy.z
				Engine.damage(state, nextEnemy, hit, tower)
			end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Rounds
---------------------------------------------------------------------------

function Engine.canStartRound(state: State): boolean
	return (state.phase == "prep" or state.phase == "intermission") and state.round < state.totalRounds
end

function Engine.startRound(state: State): boolean
	if not Engine.canStartRound(state) then
		return false
	end
	state.round += 1
	state.phase = "wave"
	state.waveTime = 0
	state.cursors = {}
	for _, group in state.rounds[state.round] do
		table.insert(state.cursors, { group = group, spawned = 0, nextAt = group.delay })
	end
	emit(state, { t = "roundStart", round = state.round })
	return true
end

-- Debug helper: jump so that the next round started is `round`.
function Engine.jumpToRound(state: State, round: number)
	for _, e in state.enemies do
		killEnemy(state, e)
	end
	table.clear(state.enemies)
	state.cursors = {}
	state.round = math.clamp(round, 1, state.totalRounds) - 1
	state.phase = "intermission"
	emit(state, { t = "clear" })
end

local function updateSpawns(state: State)
	for _, cursor in state.cursors do
		local group = cursor.group
		while cursor.spawned < group.count and state.waveTime >= cursor.nextAt do
			spawnEnemy(state, group.slimeType, 0, group.camo == true)
			cursor.spawned += 1
			cursor.nextAt += group.spacingSeconds
		end
	end
end

local function spawnsDone(state: State): boolean
	for _, cursor in state.cursors do
		if cursor.spawned < cursor.group.count then
			return false
		end
	end
	return true
end

local function applyAuras(state: State)
	for _, e in state.enemies do
		e.slow = 1
	end
	for _, tower in state.towers do
		local s = tower.stats
		if s.slowAura > 0 and s.slowFactor < 1 then
			for _, e in state.enemies do
				if e.alive and (s.slowBosses or not e.def.isBoss) and inRadius(e, tower.x, tower.z, s.slowAura) then
					e.slow = math.min(e.slow, s.slowFactor)
				end
			end
		end
	end
end

local function moveEnemies(state: State, dt: number)
	local total = state.path.totalLength
	for _, e in state.enemies do
		if not e.alive then
			continue
		end
		if e.brittle > 0 then
			e.brittle = math.max(e.brittle - dt, 0)
		end
		if e.frozen > 0 then
			e.frozen = math.max(e.frozen - dt, 0)
		elseif e.stunned > 0 then
			e.stunned = math.max(e.stunned - dt, 0)
		else
			e.distance += e.def.speed * e.slow * dt
		end
		if e.distance >= total then
			killEnemy(state, e)
			state.lives = math.max(state.lives - e.layers, 0)
			state.stats.leaks += 1
			state.stats.leakedLayers += e.layers
			emit(state, { t = "leak", id = e.id, layers = e.layers })
		else
			e.x, e.z = Path.positionAt(state.path, e.distance)
		end
	end
end

local function compactEnemies(state: State)
	local list = state.enemies
	local j = 0
	for i = 1, #list do
		local e = list[i]
		if e.alive then
			j += 1
			list[j] = e
		end
	end
	for i = #list, j + 1, -1 do
		list[i] = nil
	end
end

-- Advances the simulation by `dt` seconds of game time.
function Engine.step(state: State, dt: number)
	if state.phase == "won" or state.phase == "lost" then
		return
	end
	state.time += dt

	if state.phase == "wave" then
		state.waveTime += dt
		updateSpawns(state)
	end

	applyAuras(state)
	moveEnemies(state, dt)
	compactEnemies(state)

	if state.lives <= 0 then
		state.phase = "lost"
		emit(state, { t = "lost", round = state.round })
		return
	end

	for _, tower in state.towers do
		for i, attack in tower.stats.attacks do
			local cd = tower.cooldowns[i] - dt
			if cd <= 0 then
				if fireAttack(state, tower, attack) then
					cd += attack.cooldown
				else
					cd = 0
				end
			end
			tower.cooldowns[i] = cd
		end
	end
	compactEnemies(state)

	if #state.enemies > state.stats.maxEnemies then
		state.stats.maxEnemies = #state.enemies
	end

	if state.phase == "wave" and spawnsDone(state) and #state.enemies == 0 then
		roundEndPayout(state)
		emit(state, { t = "roundEnd", round = state.round })
		if state.round >= state.totalRounds then
			state.phase = "won"
			emit(state, { t = "won", round = state.round })
		else
			state.phase = "intermission"
		end
	end
end

return Engine
