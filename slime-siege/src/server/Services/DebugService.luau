--!strict
-- Studio-only QA commands. The Debug remote is only created when RunService:IsStudio(),
-- and every handler re-checks, so none of this exists in live servers.
--   cash <amount> | round <n> | spawn <slime> [camo] | lives <n> | goo <amount> | unlockAll

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local SlimeData = require(Shared.Data.SlimeData)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Guard = require(script.Parent.Guard)
local DataService = require(script.Parent.DataService)

export type MatchHooks = {
	debugGiveCash: (Player, number) -> (),
	debugJumpToRound: (number) -> (),
	debugSpawn: (string, boolean) -> (),
	debugSetLives: (number) -> (),
}

local DebugService = {}

function DebugService.start(match: MatchHooks?)
	if not RunService:IsStudio() then
		return
	end
	local remote = Remotes.find("Debug")
	if not remote then
		return
	end
	remote.OnServerEvent:Connect(function(player: Player, rawCommand: unknown, rawArg: unknown, rawArg2: unknown)
		if not RunService:IsStudio() or not Guard.allow(player, "Debug", 5, 10) then
			return
		end
		local command = Guard.oneOf(rawCommand, { "cash", "round", "spawn", "lives", "goo", "unlockAll" })
		if not command then
			return
		end
		if command == "goo" then
			local amount = Guard.integer(rawArg, 1, 1e7)
			if amount then
				DataService.update(player, function(p)
					p.goo += amount
				end)
			end
		elseif command == "unlockAll" then
			DataService.update(player, function(p)
				for id in TowerData do
					p.unlocked[id] = true
				end
			end)
		elseif match then
			if command == "cash" then
				local amount = Guard.integer(rawArg, 1, 1e7)
				if amount then
					match.debugGiveCash(player, amount)
				end
			elseif command == "round" then
				local round = Guard.integer(rawArg, 1, Config.TOTAL_ROUNDS)
				if round then
					match.debugJumpToRound(round)
				end
			elseif command == "spawn" then
				local kind = Guard.key(rawArg, SlimeData)
				if kind then
					match.debugSpawn(kind, rawArg2 == true)
				end
			elseif command == "lives" then
				local lives = Guard.integer(rawArg, 1, 100000)
				if lives then
					match.debugSetLives(lives)
				end
			end
		end
	end)
	print("[Debug] Studio debug remote enabled")
end

return DebugService
