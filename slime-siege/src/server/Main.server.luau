--!strict
-- Server bootstrap. One place serves both roles:
--   lobby: public servers (players walk onto the queue pad)
--   match: reserved servers created by the lobby (TeleportService)
-- In Studio the role comes from the Workspace attribute "StudioMode" ("match" or "lobby").

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local Services = script.Parent:WaitForChild("Services")
local Analytics = require(Services.Analytics)
local BadgeService = require(Services.BadgeService)
local DataService = require(Services.DataService)
local MonetizationService = require(Services.MonetizationService)
local DebugService = require(Services.DebugService)

local function detectMode(): string
	if RunService:IsStudio() then
		local attr = Workspace:GetAttribute("StudioMode")
		return if attr == "lobby" then "lobby" else "match"
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return "match"
	end
	return "lobby"
end

local mode = detectMode()
ReplicatedStorage:SetAttribute("Mode", mode)
Players.CharacterAutoLoads = mode == "lobby"

Remotes.createAll()

local sessionStart: { [Player]: number } = {}
Players.PlayerAdded:Connect(function(player)
	sessionStart[player] = os.clock()
	Analytics.track("session_start", { userId = player.UserId, mode = mode })
end)
Players.PlayerRemoving:Connect(function(player)
	local started = sessionStart[player]
	sessionStart[player] = nil
	Analytics.track("session_end", {
		userId = player.UserId,
		mode = mode,
		seconds = if started then math.floor(os.clock() - started) else 0,
	})
end)

DataService.start()
MonetizationService.start()
BadgeService.start()

if mode == "match" then
	local MatchService = require(Services.MatchService)
	MatchService.start()
	DebugService.start(MatchService)
else
	local LobbyService = require(Services.LobbyService)
	LobbyService.start()
	DebugService.start(nil)
end

print(`[SlimeSiege] server started in {mode} mode`)
