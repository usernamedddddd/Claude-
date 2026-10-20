--!strict
-- Client bootstrap. The server publishes the place role in ReplicatedStorage's "Mode"
-- attribute ("match" or "lobby"); the client only renders and requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent:WaitForChild("Controllers")
local Store = require(Controllers.Store)
local DebugPanel = require(Controllers.DebugPanel)

local mode = ReplicatedStorage:GetAttribute("Mode")
while mode == nil do
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Wait()
	mode = ReplicatedStorage:GetAttribute("Mode")
end

Store.start()

if mode == "match" then
	local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)
	local CameraController = require(Controllers.CameraController)
	local Towers = require(Controllers.Towers)
	local Effects = require(Controllers.Effects)
	local EnemyRenderer = require(Controllers.EnemyRenderer)
	local Placement = require(Controllers.Placement)
	local HUD = require(Controllers.HUD)
	local TowerPanel = require(Controllers.TowerPanel)
	local Results = require(Controllers.Results)

	CameraController.start()
	Towers.start()
	Effects.start()
	EnemyRenderer.start()
	Placement.start()
	HUD.start()
	TowerPanel.start()
	Results.start()
	Remotes.get("ClientReady"):FireServer()
else
	local LobbyUI = require(Controllers.LobbyUI)
	LobbyUI.start()
end

DebugPanel.start(mode :: string)
