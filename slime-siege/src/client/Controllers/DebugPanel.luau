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
	local panel = UI.panel({
		Size = UDim2.fromScale(0.2, 0.62),
		Position = UDim2.fromScale(0.01, 0.3),
		Visible = false,
		color = Color3.fromRGB(40, 40, 50),
		Parent = gui,
	})
	UI.list(panel, Enum.FillDirection.Vertical, 0.01)
	UI.padding(panel, 0.02)
	local toggle = UI.button({
		Text = "DEBUG",
		Size = UDim2.fromScale(0.07, 0.045),
		Position = UDim2.fromScale(0.01, 0.24),
		color = Color3.fromRGB(80, 80, 90),
		Parent = gui,
	}, function()
		panel.Visible = not panel.Visible
	end)
	toggle.ZIndex = 5

	local camo = false
	local function row(text: string, onClick: () -> ())
		UI.button(
			{ Text = text, Size = UDim2.fromScale(1, 0.065), color = Color3.fromRGB(110, 110, 130), Parent = panel },
			onClick
		)
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
	camoButton = UI.button(
		{ Text = "Camo: off", Size = UDim2.fromScale(1, 0.065), color = Color3.fromRGB(110, 110, 130), Parent = panel },
		function()
			camo = not camo
			UI.setButtonText(camoButton, if camo then "Camo: ON" else "Camo: off")
		end
	)
	for _, kind in Packet.KINDS do
		row(`Spawn {kind}`, function()
			debugRemote:FireServer("spawn", kind, camo)
		end)
	end
end

return DebugPanel
