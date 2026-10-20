--!strict
-- Studio-only QA panel. Only appears when the server created the Debug remote (Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Packet = require(Shared.Net.Packet)

local UI = require(script.Parent.UI)

local DebugPanel = {}

function DebugPanel.start(mode: string)
	if not RunService:IsStudio() then
		return
	end
	local remote = Remotes.find("Debug")
	if not remote then
		return
	end
	local debugRemote = remote :: RemoteEvent
	local gui = UI.screen("DebugPanel", 10)
	local root = UI.root(gui)
	local panel = UI.new("ScrollingFrame", {
		Name = "Panel",
		BackgroundColor3 = UI.Colors.Ink,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(300, 640),
		Position = UDim2.fromOffset(32, 300),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		Visible = false,
		Parent = root,
	})
	UI.corner(panel, 16)
	UI.list(panel, Enum.FillDirection.Vertical, 8)
	UI.padding(panel, 12)
	UI.button({
		Name = "DebugToggle",
		Text = "DEBUG",
		color = UI.Colors.Disabled,
		Size = UDim2.fromOffset(140, 48),
		Position = UDim2.fromOffset(32, 236),
		textSize = 20,
		lip = 3,
		Parent = root,
	}, function()
		panel.Visible = not panel.Visible
	end)

	local camo = false
	local function row(text: string, onClick: () -> ())
		UI.button({
			Text = text,
			Size = UDim2.new(1, 0, 0, 48),
			color = UI.Colors.PanelRaised,
			textSize = 20,
			lip = 3,
			Parent = panel,
		}, onClick)
	end
	row("+1000 Goo", function()
		debugRemote:FireServer("goo", 1000)
	end)
	row("Unlock all towers", function()
		debugRemote:FireServer("unlockAll")
	end)
	if mode ~= "match" then
		return
	end
	row("+$10,000 cash", function()
		debugRemote:FireServer("cash", 10000)
	end)
	row("Lives = 9999", function()
		debugRemote:FireServer("lives", 9999)
	end)
	for _, r in { 10, 20, 30, 40 } do
		row(`Jump to round {r}`, function()
			debugRemote:FireServer("round", r)
		end)
	end
	local camoButton: TextButton
	camoButton = UI.button({
		Text = "Camo: off",
		Size = UDim2.new(1, 0, 0, 48),
		color = UI.Colors.PanelRaised,
		textSize = 20,
		lip = 3,
		Parent = panel,
	}, function()
		camo = not camo
		UI.setButtonText(camoButton, if camo then "Camo: ON" else "Camo: off")
	end)
	for _, kind in Packet.KINDS do
		row(`Spawn {kind}`, function()
			debugRemote:FireServer("spawn", kind, camo)
		end)
	end
end

return DebugPanel
