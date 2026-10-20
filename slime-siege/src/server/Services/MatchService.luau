--!strict
-- Runs a match on the server: owns the authoritative Engine state, validates every request,
-- handles countdowns and majority votes, streams 10 Hz snapshots, and hands out rewards.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local MapData = require(Shared.Data.MapData)
local TowerData = require(Shared.Data.TowerData)
local Rounds = require(Shared.Data.Rounds)
local Engine = require(Shared.Sim.Engine)
local Targeting = require(Shared.Sim.Targeting)
local Upgrades = require(Shared.Sim.Upgrades)
local Votes = require(Shared.Sim.Votes)
local Rewards = require(Shared.Sim.Rewards)
local Packet = require(Shared.Net.Packet)
local Remotes = require(Shared.Net.Remotes)
local TowerModels = require(Shared.Visual.TowerModels)

local Guard = require(script.Parent.Guard)
local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

local MatchService = {}

local state: Engine.State
local towerModels: { [number]: Model } = {}
local towersFolder: Folder
local skipVotes: { [number]: boolean } = {}
local speedVotes: { [number]: boolean } = {}
local participants: { [number]: Player } = {}
local extraCashGranted: { [number]: boolean } = {}
local readyPlayers: { [Player]: boolean } = {}
local netEvents: { Engine.Event } = {}
local countdown = Config.PREP_SECONDS
local speed = 1
local accumulator = 0
local snapshotTimer = 0
local stateTimer = 0
local matchOver = false
local matchStarted = false
local partyDeadline = 0 -- only set when the lobby sent party info (teleport data)
local expectedParty: { [number]: boolean }? = nil

local remotes: { [string]: RemoteEvent } = {}

local function notify(player: Player, message: string, kind: string?)
	remotes.Notify:FireClient(player, message, kind or "error")
end

local function speedMultiplier(): number
	return if Votes.hasMajority(Votes.count(speedVotes, state.players), state.playerCount)
		then Config.FAST_FORWARD_MULTIPLIER
		else 1
end

---------------------------------------------------------------------------
-- Tower models (replicated to every client automatically)
---------------------------------------------------------------------------

local function facingPath(x: number, z: number): CFrame
	-- Face the nearest point on the path.
	local best, bx, bz = math.huge, x, z - 1
	for i = 1, #MapData.waypoints - 1 do
		local a, b = MapData.waypoints[i], MapData.waypoints[i + 1]
		local ex, ez = b.x - a.x, b.z - a.z
		local len2 = ex * ex + ez * ez
		local t = math.clamp(((x - a.x) * ex + (z - a.z) * ez) / len2, 0, 1)
		local px, pz = a.x + ex * t, a.z + ez * t
		local d = (px - x) ^ 2 + (pz - z) ^ 2
		if d < best then
			best, bx, bz = d, px, pz
		end
	end
	local pos = Vector3.new(x, MapData.groundY, z)
	return CFrame.lookAt(pos, Vector3.new(bx, MapData.groundY, bz))
end

local function refreshTowerModel(tower: Engine.Tower)
	local model = towerModels[tower.uid]
	if not model then
		return
	end
	model:SetAttribute("TierA", tower.tiers.A)
	model:SetAttribute("TierB", tower.tiers.B)
	model:SetAttribute("Targeting", tower.targeting)
	model:SetAttribute("Spent", tower.spent)
	model:SetAttribute("SellValue", Upgrades.sellValue(tower.spent))
	model:SetAttribute("Range", if tower.stats.attacks[1] then tower.stats.attacks[1].range else 0)
	model:SetAttribute("SeesCamo", tower.seesCamo)
	TowerModels.setTierPips(model, tower.tiers.A, tower.tiers.B)
end

local function createTowerModel(tower: Engine.Tower, owner: Player)
	local model = TowerModels.build(tower.id, { vip = DataService.hasPass(owner, "VipSkins") })
	model.Name = `{tower.id}_{tower.uid}`
	model:PivotTo(facingPath(tower.x, tower.z))
	model:SetAttribute("Uid", tower.uid)
	model:SetAttribute("TowerId", tower.id)
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("OwnerName", owner.DisplayName)
	model:SetAttribute("Footprint", tower.footprint)
	model:SetAttribute("Pops", 0)
	towerModels[tower.uid] = model
	refreshTowerModel(tower)
	model.Parent = towersFolder
end

local function refreshAllTowerModels()
	for _, tower in state.towers do
		refreshTowerModel(tower)
	end
end

---------------------------------------------------------------------------
-- Remote handlers (validate type -> range -> ownership -> plausibility)
---------------------------------------------------------------------------

local function onPlaceTower(player: Player, rawId: unknown, rawX: unknown, rawZ: unknown)
	if not Guard.allow(player, "PlaceTower", 4, 6) or matchOver then
		return
	end
	local towerId = Guard.key(rawId, TowerData)
	local b = MapData.bounds
	local x = Guard.number(rawX, b.minX, b.maxX)
	local z = Guard.number(rawZ, b.minZ, b.maxZ)
	if not towerId or not x or not z then
		return
	end
	local tower, err = Engine.placeTower(state, player.UserId, towerId, x, z)
	if not tower then
		notify(player, err or "Can't place there")
		return
	end
	createTowerModel(tower, player)
	refreshAllTowerModels() -- camo auras can change other towers
	Analytics.track("tower_placed", { userId = player.UserId, towerId = towerId, round = state.round })
end

local function onUpgradeTower(player: Player, rawUid: unknown, rawPath: unknown)
	if not Guard.allow(player, "UpgradeTower", 5, 8) or matchOver then
		return
	end
	local uid = Guard.integer(rawUid, 1, 1e9)
	local path = Guard.oneOf(rawPath, { "A", "B" })
	if not uid or not path then
		return
	end
	local ok, err = Engine.upgradeTower(state, player.UserId, uid, path :: Upgrades.PathKey)
	if not ok then
		notify(player, err or "Can't upgrade")
		return
	end
	local tower = state.towerByUid[uid]
	refreshAllTowerModels()
	Analytics.track("tower_upgraded", {
		userId = player.UserId,
		towerId = tower.id,
		path = path,
		tier = tower.tiers[path :: Upgrades.PathKey],
	})
end

local function onSellTower(player: Player, rawUid: unknown)
	if not Guard.allow(player, "SellTower", 4, 6) or matchOver then
		return
	end
	local uid = Guard.integer(rawUid, 1, 1e9)
	if not uid then
		return
	end
	local refund = Engine.sellTower(state, player.UserId, uid)
	if not refund then
		return
	end
	local model = towerModels[uid]
	if model then
		model:Destroy()
		towerModels[uid] = nil
	end
	refreshAllTowerModels()
end

local function onSetTargeting(player: Player, rawUid: unknown, rawMode: unknown)
	if not Guard.allow(player, "SetTargeting", 6, 10) then
		return
	end
	local uid = Guard.integer(rawUid, 1, 1e9)
	if not uid or not Targeting.isMode(rawMode) then
		return
	end
	if Engine.setTargeting(state, player.UserId, uid, rawMode :: Targeting.Mode) then
		refreshTowerModel(state.towerByUid[uid])
	end
end

local function onVoteSkip(player: Player)
	if not Guard.allow(player, "VoteSkip", 3, 4) or not state.players[player.UserId] then
		return
	end
	if state.phase == "prep" or state.phase == "intermission" then
		skipVotes[player.UserId] = not skipVotes[player.UserId]
	end
end

local function onVoteSpeed(player: Player)
	if not Guard.allow(player, "VoteSpeed", 3, 4) or not state.players[player.UserId] then
		return
	end
	speedVotes[player.UserId] = not speedVotes[player.UserId]
end

---------------------------------------------------------------------------
-- Snapshots & state sync
---------------------------------------------------------------------------

local function sendSnapshot()
	local packet = Packet.encodeSnapshot(netEvents, state.enemies :: { any })
	table.clear(netEvents)
	for player in readyPlayers do
		remotes.Snapshot:FireClient(player, packet)
	end
end

-- A late joiner gets every live slime as a spawn event, then regular snapshots.
local function sendFullSync(player: Player)
	local events: { Engine.Event } = { { t = "clear" } }
	for _, e in state.enemies do
		table.insert(events, { t = "spawn", id = e.id, slime = e.kind, camo = e.camo, distance = e.distance })
	end
	remotes.Snapshot:FireClient(player, Packet.encodeSnapshot(events, state.enemies :: { any }))
end

local function sendMatchState()
	local list = {}
	for key, ps in state.players do
		local player = participants[key]
		table.insert(list, {
			userId = key,
			name = if player then player.DisplayName else "?",
			cash = ps.cash,
			pops = ps.pops,
			skip = skipVotes[key] == true,
			fast = speedVotes[key] == true,
		})
	end
	table.sort(list, function(a, b)
		return a.userId < b.userId
	end)
	remotes.MatchState:FireAllClients({
		lives = state.lives,
		round = state.round,
		totalRounds = state.totalRounds,
		phase = state.phase,
		countdown = if state.phase == "prep" or state.phase == "intermission" then math.ceil(countdown) else 0,
		waitingForParty = not matchStarted and os.clock() < partyDeadline,
		speed = speed,
		skipVotes = Votes.count(skipVotes, state.players),
		speedVotes = Votes.count(speedVotes, state.players),
		playerCount = state.playerCount,
		players = list,
	})
end

---------------------------------------------------------------------------
-- Match flow
---------------------------------------------------------------------------

local function returnToLobby()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	if RunService:IsStudio() then
		return
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players)
		end)
		if ok then
			return
		end
		warn(`[Match] return teleport failed ({attempt}/3): {err}`)
		task.wait(2 * attempt)
	end
end

local function endMatch(won: boolean)
	if matchOver then
		return
	end
	matchOver = true
	local roundReached = state.round
	Analytics.track(if won then "match_win" else "match_lose", { round = roundReached, players = state.playerCount })
	for key in state.players do
		local player = participants[key]
		if player then
			local reward = Rewards.compute(roundReached, won, DataService.hasPass(player, "DoubleGoo"))
			DataService.update(player, function(profile)
				profile.goo += reward.goo
				profile.xp += reward.xp
				profile.stats.matches += 1
				if won then
					profile.stats.wins += 1
				end
				profile.stats.bestRound = math.max(profile.stats.bestRound, roundReached)
			end)
			remotes.MatchResult:FireClient(player, {
				won = won,
				round = roundReached,
				goo = reward.goo,
				xp = reward.xp,
				returnIn = Config.RETURN_TO_LOBBY_SECONDS,
				studio = RunService:IsStudio(),
			})
		end
	end
	task.delay(Config.RETURN_TO_LOBBY_SECONDS, function()
		if RunService:IsStudio() then
			MatchService.reset()
		else
			returnToLobby()
		end
	end)
end

local function startNextRound()
	table.clear(skipVotes)
	if Engine.startRound(state) and not matchStarted then
		matchStarted = true
		Analytics.track("match_start", { players = state.playerCount })
	end
end

local function handleEvents()
	local events = Engine.drainEvents(state)
	for _, ev in events do
		local t = ev.t
		if t == "roundEnd" then
			Analytics.track("round_complete", { round = ev.round, livesLeft = state.lives })
			countdown = Config.INTERMISSION_SECONDS
		elseif t == "won" then
			endMatch(true)
		elseif t == "lost" then
			endMatch(false)
		end
		table.insert(netEvents, ev)
	end
end

local function onHeartbeat(dt: number)
	dt = math.min(dt, 0.25)
	if matchOver then
		return
	end

	if (state.phase == "prep" or state.phase == "intermission") and state.playerCount > 0 then
		local waiting = state.phase == "prep" and os.clock() < partyDeadline
		if not waiting then
			countdown -= dt
		end
		local skip = Votes.hasMajority(Votes.count(skipVotes, state.players), state.playerCount)
		if countdown <= 0 or skip then
			startNextRound()
		end
	end

	speed = speedMultiplier()
	accumulator += dt * speed
	local steps = 0
	while accumulator >= Config.SIM_DT and steps < 12 do
		Engine.step(state, Config.SIM_DT)
		accumulator -= Config.SIM_DT
		steps += 1
		handleEvents()
	end
	if steps >= 12 then
		accumulator = 0 -- server is overloaded: slow the game rather than spiral
	end

	snapshotTimer += dt
	if snapshotTimer >= 1 / Config.NET_SNAPSHOT_HZ then
		snapshotTimer = 0
		sendSnapshot()
	end
	stateTimer += dt
	if stateTimer >= 0.25 then
		stateTimer = 0
		sendMatchState()
		for _, tower in state.towers do
			local model = towerModels[tower.uid]
			if model and model:GetAttribute("Pops") ~= tower.pops then
				model:SetAttribute("Pops", tower.pops)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function applyProfile(player: Player)
	local ps = state.players[player.UserId]
	local profile = DataService.get(player)
	if not ps or not profile then
		return
	end
	if RunService:IsStudio() and Config.STUDIO_UNLOCK_ALL then
		ps.allowedTowers = nil
	else
		ps.allowedTowers = table.clone(profile.unlocked)
	end
	if profile.passes.ExtraCash and not extraCashGranted[player.UserId] then
		extraCashGranted[player.UserId] = true
		Engine.giveCash(state, player.UserId, Config.EXTRA_CASH_PASS_AMOUNT)
	end
end

local function onPlayerAdded(player: Player)
	if expectedParty == nil then
		local joinData = player:GetJoinData()
		local data: any = joinData and joinData.TeleportData
		if type(data) == "table" and type(data.party) == "table" then
			expectedParty = {}
			for _, id in data.party do
				if type(id) == "number" then
					(expectedParty :: { [number]: boolean })[id] = true
				end
			end
			partyDeadline = os.clock() + Config.WAIT_FOR_PARTY_SECONDS
		end
	end
	if state.playerCount >= Config.MAX_PLAYERS or matchOver then
		notify(player, "This match is full; you're spectating.", "info")
		return
	end
	participants[player.UserId] = player
	local ps = Engine.addPlayer(state, player.UserId)
	local defaults: { [string]: boolean } = {}
	for id, def in TowerData do
		if def.unlockGoo == 0 then
			defaults[id] = true
		end
	end
	ps.allowedTowers = defaults
	applyProfile(player)

	-- Everyone from the queue has arrived: stop waiting.
	if expectedParty then
		local all = true
		for id in expectedParty do
			if not participants[id] then
				all = false
			end
		end
		if all then
			partyDeadline = 0
		end
	end
end

local function onPlayerRemoving(player: Player)
	readyPlayers[player] = nil
	participants[player.UserId] = nil
	skipVotes[player.UserId] = nil
	speedVotes[player.UserId] = nil
	Engine.removePlayer(state, player.UserId)
end

---------------------------------------------------------------------------
-- Lifecycle & debug hooks
---------------------------------------------------------------------------

local function newState()
	state = Engine.new({ rounds = Rounds, totalRounds = Config.TOTAL_ROUNDS })
	countdown = Config.PREP_SECONDS
	matchOver = false
	matchStarted = false
	accumulator = 0
	table.clear(skipVotes)
	table.clear(speedVotes)
	table.clear(netEvents)
	table.clear(extraCashGranted)
	table.insert(netEvents, { t = "clear" })
end

-- Studio: restart the match in place after it ends.
function MatchService.reset()
	for _, model in towerModels do
		model:Destroy()
	end
	table.clear(towerModels)
	newState()
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function MatchService.debugGiveCash(player: Player, amount: number)
	Engine.giveCash(state, player.UserId, amount)
end

function MatchService.debugJumpToRound(round: number)
	Engine.jumpToRound(state, round)
	countdown = Config.INTERMISSION_SECONDS
	handleEvents()
end

function MatchService.debugSpawn(kind: string, camo: boolean)
	Engine.spawnSlime(state, kind, camo, 0)
	handleEvents()
end

function MatchService.debugSetLives(lives: number)
	state.lives = lives
end

function MatchService.start()
	for _, name in { "Notify", "Snapshot", "MatchState", "MatchResult" } do
		remotes[name] = Remotes.get(name)
	end
	MapBuilder.buildMatchMap()
	local folder = Instance.new("Folder")
	folder.Name = "Towers"
	folder.Parent = Workspace
	towersFolder = folder
	newState()

	Remotes.get("PlaceTower").OnServerEvent:Connect(onPlaceTower)
	Remotes.get("UpgradeTower").OnServerEvent:Connect(onUpgradeTower)
	Remotes.get("SellTower").OnServerEvent:Connect(onSellTower)
	Remotes.get("SetTargeting").OnServerEvent:Connect(onSetTargeting)
	Remotes.get("VoteSkip").OnServerEvent:Connect(onVoteSkip)
	Remotes.get("VoteSpeed").OnServerEvent:Connect(onVoteSpeed)
	Remotes.get("ClientReady").OnServerEvent:Connect(function(player)
		if readyPlayers[player] or not Guard.allow(player, "ClientReady", 0.2, 2) then
			return
		end
		readyPlayers[player] = true
		sendFullSync(player)
		sendMatchState()
	end)

	DataService.onLoaded(function(player)
		applyProfile(player)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MatchService
