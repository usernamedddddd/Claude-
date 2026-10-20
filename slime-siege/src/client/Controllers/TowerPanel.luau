--!strict
-- Upgrade panel for the selected tower: two upgrade paths with costs, crosspath state,
-- targeting mode, and sell. Read-only for towers owned by teammates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerData = require(Shared.Data.TowerData)
local Targeting = require(Shared.Sim.Targeting)
local Upgrades = require(Shared.Sim.Upgrades)
local Remotes = require(Shared.Net.Remotes)

local Placement = require(script.Parent.Placement)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local TowerPanel = {}

local C = UI.Colors

type PathUI = {
	pips: { Frame },
	button: TextButton,
	name: TextLabel,
	desc: TextLabel,
}

function TowerPanel.start()
	local gui = UI.screen("TowerPanel", 2)
	local panel = UI.panel({
		Size = UDim2.fromScale(0.3, 0.66),
		Position = UDim2.fromScale(0.99, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		Parent = gui,
	})
	UI.aspect(panel, 0.72)

	local title = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.62, 0.08),
		Position = UDim2.fromScale(0.2, 0.02),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local iconHolder = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.16, 0.1),
		Position = UDim2.fromScale(0.03, 0.015),
		Parent = panel,
	})
	local subtitle = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.75, 0.045),
		Position = UDim2.fromScale(0.2, 0.095),
		TextXAlignment = Enum.TextXAlignment.Left,
		color = C.Pink,
		Parent = panel,
	})
	UI.button({
		Text = "✖",
		Size = UDim2.fromScale(0.12, 0.08),
		Position = UDim2.fromScale(0.86, 0.02),
		color = C.Red,
		Parent = panel,
	}, function()
		Placement.select(nil)
	end)

	local pathsFrame = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.94, 0.58),
		Position = UDim2.fromScale(0.03, 0.155),
		Parent = panel,
	})
	UI.list(pathsFrame, Enum.FillDirection.Horizontal, 0.03)

	local currentModel: Model? = nil
	local paths: { [string]: PathUI } = {}

	local function upgrade(path: string)
		local model = currentModel
		if not model then
			return
		end
		Remotes.get("UpgradeTower"):FireServer(model:GetAttribute("Uid"), path)
	end

	for i, key in { "A", "B" } do
		local column = UI.new("Frame", {
			BackgroundColor3 = if key == "A" then Color3.fromRGB(255, 205, 232) else Color3.fromRGB(205, 232, 255),
			Size = UDim2.fromScale(0.485, 1),
			LayoutOrder = i,
			Parent = pathsFrame,
		})
		UI.corner(column, 0.08)
		UI.stroke(column, 3)
		local name = UI.text({
			Text = "",
			Size = UDim2.fromScale(0.9, 0.11),
			Position = UDim2.fromScale(0.05, 0.02),
			color = C.TextDark,
			stroke = false,
			Parent = column,
		})
		local pipRow = UI.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.8, 0.07),
			Position = UDim2.fromScale(0.1, 0.14),
			Parent = column,
		})
		UI.list(pipRow, Enum.FillDirection.Horizontal, 0.08)
		local pips = {}
		for t = 1, 3 do
			local pip = UI.new(
				"Frame",
				{ BackgroundColor3 = C.Gray, Size = UDim2.fromScale(0.26, 1), LayoutOrder = t, Parent = pipRow }
			)
			UI.corner(pip, 0.5)
			UI.stroke(pip, 2)
			table.insert(pips, pip)
		end
		local desc = UI.text({
			Text = "",
			Size = UDim2.fromScale(0.9, 0.36),
			Position = UDim2.fromScale(0.05, 0.24),
			color = C.TextDark,
			stroke = false,
			maxTextSize = 22,
			Parent = column,
		})
		local button = UI.button({
			Text = "",
			Size = UDim2.fromScale(0.9, 0.3),
			Position = UDim2.fromScale(0.05, 0.66),
			color = C.Green,
			Parent = column,
		}, function()
			upgrade(key)
		end)
		paths[key] = { pips = pips, button = button, name = name, desc = desc }
	end

	local targetButton = UI.button({
		Text = "🎯 First",
		Size = UDim2.fromScale(0.6, 0.09),
		Position = UDim2.fromScale(0.03, 0.76),
		color = C.Blue,
		Parent = panel,
	}, function()
		local model = currentModel
		if not model then
			return
		end
		local mode = model:GetAttribute("Targeting")
		local index = table.find(Targeting.MODES, mode :: any) or 1
		local nextMode = Targeting.MODES[index % #Targeting.MODES + 1]
		Remotes.get("SetTargeting"):FireServer(model:GetAttribute("Uid"), nextMode)
	end)
	local popsLabel = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.32, 0.07),
		Position = UDim2.fromScale(0.65, 0.77),
		Parent = panel,
	})
	local sellButton = UI.button({
		Text = "Sell",
		Size = UDim2.fromScale(0.94, 0.1),
		Position = UDim2.fromScale(0.03, 0.87),
		color = C.Red,
		Parent = panel,
	}, function()
		local model = currentModel
		if model then
			Remotes.get("SellTower"):FireServer(model:GetAttribute("Uid"))
			Placement.select(nil)
		end
	end)

	local function refresh()
		local model = currentModel
		if not model or not model.Parent then
			panel.Visible = false
			return
		end
		local towerId = model:GetAttribute("TowerId")
		local def = if type(towerId) == "string" then TowerData[towerId] else nil
		if not def then
			return
		end
		local mine = model:GetAttribute("Owner") == Players.LocalPlayer.UserId
		local tiers: Upgrades.Tiers = {
			A = tonumber(model:GetAttribute("TierA")) or 0,
			B = tonumber(model:GetAttribute("TierB")) or 0,
		}
		title.Text = def.displayName
		subtitle.Text = if mine then "Your tower" else `{model:GetAttribute("OwnerName")}'s tower`
		popsLabel.Text = `Pops: {model:GetAttribute("Pops") or 0}`
		local cash = Store.cash()

		for key, ui in paths do
			local pathKey: Upgrades.PathKey = if key == "A" then "A" else "B"
			local pathDef = def.paths[pathKey]
			ui.name.Text = pathDef.name
			for t, pip in ui.pips do
				pip.BackgroundColor3 = if t <= tiers[pathKey] then (if key == "A" then C.Pink else C.Blue) else C.Gray
			end
			local nextTier = Upgrades.nextTier(def, tiers, pathKey)
			if nextTier then
				ui.desc.Text = `{nextTier.name}\n{nextTier.description}`
				UI.setButtonText(ui.button, UI.formatCash(nextTier.cost))
				ui.button.BackgroundColor3 = if mine and cash >= nextTier.cost then C.Green else C.Gray
				ui.button.Active = mine
			else
				local _, reason = Upgrades.canUpgrade(tiers, pathKey)
				ui.desc.Text = if reason == "Path maxed"
					then "Fully upgraded!"
					else "Locked: the other path is past tier 1"
				UI.setButtonText(ui.button, if reason == "Path maxed" then "MAX" else "🔒")
				ui.button.BackgroundColor3 = C.Gray
				ui.button.Active = false
			end
		end
		UI.setButtonText(targetButton, `🎯 {model:GetAttribute("Targeting") or "First"}`)
		targetButton.Visible = mine and #def.base.attacks > 0
		sellButton.Visible = mine
		UI.setButtonText(sellButton, `Sell for {UI.formatCash(tonumber(model:GetAttribute("SellValue")) or 0)}`)
	end

	local attributeConnection: RBXScriptConnection? = nil
	Placement.selected:Connect(function(model)
		if attributeConnection then
			attributeConnection:Disconnect()
			attributeConnection = nil
		end
		currentModel = model
		for _, child in iconHolder:GetChildren() do
			child:Destroy()
		end
		if model then
			local def = TowerData[model:GetAttribute("TowerId") :: string]
			if def then
				UI.icon(def.icon, { Size = UDim2.fromScale(1, 1), Parent = iconHolder })
			end
			attributeConnection = model.AttributeChanged:Connect(refresh)
			panel.Visible = true
			panel.Position = UDim2.fromScale(1.3, 0.5)
			TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(0.99, 0.5),
			}):Play()
		else
			panel.Visible = false
		end
		refresh()
	end)
	Store.matchChanged:Connect(refresh)
end

return TowerPanel
