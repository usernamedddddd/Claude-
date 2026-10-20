--!strict
-- Lobby: a queue pad ("elevator") that sends up to 4 players to a reserved match server,
-- plus the Goo shop for unlocking towers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Guard = require(script.Parent.Guard)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

local LobbyService = {}

local PAD_RADIUS = 7
local TICK = 0.25

local queue: { Player } = {}
local countdown: number? = nil
local launching = false

local function onPad(player: Player, pad: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.CFrame.Position - pad.CFrame.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= PAD_RADIUS and math.abs(offset.Y) < 10
end

local function teleportGroup(group: { Player })
	local party = {}
	for _, p in group do
		table.insert(party, p.UserId)
	end
	if RunService:IsStudio() then
		for _, p in group do
			Remotes.get("Notify"):FireClient(
				p,
				'Teleports don\'t work in Studio. Set Workspace attribute StudioMode = "match" to playtest a match.',
				"info"
			)
		end
		return
	end
	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(game.PlaceId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ party = party })
		TeleportService:TeleportAsync(game.PlaceId, group, options)
	end)
	if not ok then
		warn(`[Lobby] teleport failed: {err}`)
		for _, p in group do
			Remotes.get("Notify"):FireClient(p, "Couldn't start the match, try again!", "error")
		end
	end
end

local function onUnlockTower(player: Player, rawId: unknown)
	if not Guard.allow(player, "UnlockTower", 2, 4) then
		return
	end
	local towerId = Guard.key(rawId, TowerData)
	local profile = DataService.get(player)
	if not towerId or not profile then
		return
	end
	local def = TowerData[towerId]
	if profile.unlocked[towerId] then
		return
	end
	if profile.goo < def.unlockGoo then
		Remotes.get("Notify"):FireClient(player, "Not enough Goo", "error")
		return
	end
	DataService.update(player, function(p)
		p.goo -= def.unlockGoo
		p.unlocked[towerId] = true
	end)
	Remotes.get("Notify"):FireClient(player, `Unlocked {def.displayName}!`, "success")
end

function LobbyService.start()
	local lobby = MapBuilder.buildLobby()
	Remotes.get("UnlockTower").OnServerEvent:Connect(onUnlockTower)
	local queueRemote = Remotes.get("QueueState")

	task.spawn(function()
		while true do
			task.wait(TICK)
			if launching then
				continue
			end
			-- Rebuild the queue from who is standing on the pad (keeps arrival order).
			local still: { Player } = {}
			for _, p in queue do
				if p.Parent and onPad(p, lobby.pad) then
					table.insert(still, p)
				end
			end
			for _, p in Players:GetPlayers() do
				if #still >= Config.MAX_PLAYERS then
					break
				end
				if not table.find(still, p) and onPad(p, lobby.pad) then
					table.insert(still, p)
				end
			end
			queue = still

			if #queue == 0 then
				countdown = nil
				lobby.padLabel.Text = "Step here to play!"
			else
				countdown = (countdown or Config.QUEUE_COUNTDOWN) - TICK
				local secondsLeft = math.max(math.ceil(countdown :: number), 0)
				lobby.padLabel.Text = `{#queue}/{Config.MAX_PLAYERS}  -  starting in {secondsLeft}`
				if (countdown :: number) <= 0 or #queue >= Config.MAX_PLAYERS then
					launching = true
					local group = table.clone(queue)
					queue = {}
					countdown = nil
					lobby.padLabel.Text = "Launching!"
					teleportGroup(group)
					task.wait(3)
					launching = false
				end
			end
			local names = {}
			for _, p in queue do
				table.insert(names, p.DisplayName)
			end
			queueRemote:FireAllClients({
				players = names,
				max = Config.MAX_PLAYERS,
				countdown = if countdown then math.ceil(countdown) else nil,
			})
		end
	end)
end

return LobbyService
