--!strict
-- Client-side view of server state (read-only mirror). Gameplay decisions never use it;
-- it only drives UI. The server re-validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

export type PlayerView = { userId: number, name: string, cash: number, pops: number, skip: boolean, fast: boolean }
export type MatchView = {
	lives: number,
	round: number,
	totalRounds: number,
	phase: string,
	countdown: number,
	waitingForParty: boolean,
	waveProgress: number?,
	slimesLeft: number?,
	speed: number,
	skipVotes: number,
	speedVotes: number,
	playerCount: number,
	players: { PlayerView },
}
export type ProfileView = {
	goo: number,
	xp: number,
	level: number,
	unlocked: { [string]: boolean },
	passes: { [string]: boolean },
	stats: { [string]: number },
	badges: { [string]: boolean },
	equippedBadge: string,
}

local Store = {}

Store.match = nil :: MatchView?
Store.profile = nil :: ProfileView?
Store.matchChanged = Signal.new()
Store.profileChanged = Signal.new()
Store.notified = Signal.new() :: Signal.Signal<string, string>

function Store.me(): PlayerView?
	local match = Store.match
	if not match then
		return nil
	end
	for _, p in match.players do
		if p.userId == Players.LocalPlayer.UserId then
			return p
		end
	end
	return nil
end

function Store.cash(): number
	local me = Store.me()
	return if me then me.cash else 0
end

function Store.start()
	Remotes.get("MatchState").OnClientEvent:Connect(function(view: MatchView)
		Store.match = view
		Store.matchChanged:Fire()
	end)
	Remotes.get("ProfileData").OnClientEvent:Connect(function(view: ProfileView)
		Store.profile = view
		Store.profileChanged:Fire()
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(message: string, kind: string)
		Store.notified:Fire(message, kind)
	end)
end

return Store
