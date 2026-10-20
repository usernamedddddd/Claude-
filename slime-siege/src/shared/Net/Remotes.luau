--!strict
-- Every remote in the game is listed here. The server creates them (Remotes.createAll);
-- clients only look them up. The Debug remote only exists in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.EVENTS = {
	-- client -> server requests
	"PlaceTower", -- (towerId: string, x: number, z: number)
	"UpgradeTower", -- (uid: number, path: "A" | "B")
	"SellTower", -- (uid: number)
	"SetTargeting", -- (uid: number, mode: string)
	"VoteSkip", -- ()
	"VoteSpeed", -- ()
	"UnlockTower", -- (towerId: string)  lobby only
	"QuickPlay", -- ()  lobby only: move my character onto the queue pad
	"PurchaseRequest", -- (productKey: string)
	"ClientReady", -- ()  client finished loading; server sends a full enemy sync
	-- server -> client
	"Snapshot", -- (packet: buffer)
	"MatchState", -- (state: table)
	"ProfileData", -- (profile view: table)
	"Notify", -- (message: string, kind: string)
	"MatchResult", -- (result: table)
	"PurchaseResult", -- (productKey: string, granted: boolean)
	"QueueState", -- (state: table)  lobby only
}

local FOLDER_NAME = "Remotes"

function Remotes.createAll(): Folder
	assert(RunService:IsServer(), "only the server creates remotes")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in Remotes.EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	if RunService:IsStudio() then
		local debugRemote = Instance.new("RemoteEvent")
		debugRemote.Name = "Debug"
		debugRemote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), `missing remote {name}`)
	return remote
end

function Remotes.find(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local remote = folder and folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

return Remotes
