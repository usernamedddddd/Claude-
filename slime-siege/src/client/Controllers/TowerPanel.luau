--!strict
-- Tower upgrade panel from the Figma "Tower Panel v2" (reference style): dark gradient panel
-- with a purple border, portrait + outlined name, two path cards (pink A / cyan B) with tier
-- pips and either the next upgrade (green buy button) or the crosspath lock, a segmented
-- targeting control, and a red sell button. Read-only for teammates' towers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerData = require(Shared.Data.TowerData)
local Targeting = require(Shared.Sim.Targeting)
local Upgrades = require(Shared.Sim.Upgrades)
local Remotes = require(Shared.Net.Remotes)

local Motion = require(script.Parent.Motion)
local Placement = require(script.Parent.Placement)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local TowerPanel = {}

local V = UI.V2
local WIDTH = 450
local COLUMN_W = (WIDTH - 36 - 12) / 2
local PIP_OFF = Color3.fromHex("#3A3150")

type PathUI = {
	pips: { Frame },
	tag: TextLabel,
	caption: TextLabel,
	name: TextLabel,
	desc: TextLabel,
	lockIcon: GuiObject,
	button: TextButton,
	tier: number,
}

function TowerPanel.start()
	local gui = UI.screen("TowerPanel", 2)
	local root = UI.root(gui)
	local shown, hidden = UDim2.new(1, -40, 0, 200), UDim2.new(1, WIDTH + 60, 0, 200)
	local panel = UI.panel({
		Name = "Panel",
		Size = UDim2.fromOffset(WIDTH, 650),
		Position = hidden,
		AnchorPoint = Vector2.new(1, 0),
		accent = V.Purple,
		Visible = false,
		Parent = root,
	})
	local face = panel.face

	-- Header
	local portrait = UI.new(
		"Frame",
		{
			Name = "Portrait",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(76, 76),
			Position = UDim2.fromOffset(16, 14),
			Parent = face,
		}
	)
	local title = UI.text({
		Name = "Title",
		Text = "",
		size = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(100, 16),
		Parent = face,
	})
	local subtitle = UI.text({
		Name = "Subtitle",
		Text = "",
		font = "label",
		size = 13,
		color = V.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(102, 62),
		Parent = face,
	})
	UI.button(
		{
			Name = "Close",
			icon = "close",
			style = "red",
			Size = UDim2.fromOffset(54, 54),
			Position = UDim2.new(1, -18, 0, 18),
			AnchorPoint = Vector2.new(1, 0),
			iconSize = 30,
			Parent = face,
		},
		function()
			Placement.select(nil)
		end
	)

	local currentModel: Model? = nil
	local paths: { [string]: PathUI } = {}

	for i, key in { "A", "B" } do
		local accent = if key == "A" then V.PathA else V.PathB
		local col = UI.panel({
			Name = "Path" .. key,
			Size = UDim2.fromOffset(COLUMN_W, 312),
			Position = UDim2.fromOffset(18 + (i - 1) * (COLUMN_W + 12), 104),
			accent = accent,
			strokeWidth = 4,
			radius = 16,
			lip = 0,
			Parent = face,
		})
		local cf = col.face
		local tag = UI.text({
			Name = "Tag",
			Text = key,
			font = "label",
			size = 17,
			color = accent,
			Position = UDim2.fromOffset(12, 12),
			Parent = cf,
		})
		local pipRow = UI.new(
			"Frame",
			{
				Name = "Pips",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -24, 0, 12),
				Position = UDim2.fromOffset(12, 44),
				Parent = cf,
			}
		)
		UI.list(pipRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		local pips = {}
		for t = 1, 3 do
			local pip = UI.new(
				"Frame",
				{
					Name = "Pip" .. t,
					BackgroundColor3 = PIP_OFF,
					Size = UDim2.fromOffset(56, 12),
					LayoutOrder = t,
					Parent = pipRow,
				}
			)
			UI.corner(pip, 999)
			UI.stroke(pip, 2)
			table.insert(pips, pip)
		end
		local caption = UI.text({
			Text = "Next upgrade",
			font = "label",
			size = 12,
			color = V.Gold,
			Position = UDim2.fromOffset(12, 70),
			Parent = cf,
		})
		local lockIcon =
			UI.icon("lock", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(12, 88), Parent = cf })
		local name = UI.text({
			Name = "UpgradeName",
			Text = "",
			size = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -24, 0, 30),
			Position = UDim2.fromOffset(12, 90),
			Parent = cf,
		})
		local desc = UI.text({
			Name = "Description",
			Text = "",
			size = 15,
			color = Color3.fromHex("#E2DCEE"),
			stroke = false,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -24, 0, 92),
			Position = UDim2.fromOffset(12, 126),
			Parent = cf,
		})
		local button = UI.button(
			{
				Name = "Upgrade",
				Text = "",
				icon = "coin",
				style = "green",
				Size = UDim2.new(1, -24, 0, 56),
				Position = UDim2.new(0, 12, 1, -70),
				textSize = 24,
				iconSize = 30,
				Parent = cf,
			},
			function()
				local model = currentModel
				if model then
					Remotes.get("UpgradeTower"):FireServer(model:GetAttribute("Uid"), key)
				end
			end
		)
		paths[key] = {
			pips = pips,
			tag = tag,
			caption = caption,
			name = name,
			desc = desc,
			lockIcon = lockIcon,
			button = button,
			tier = -1,
		}
	end

	-- Targeting (segmented)
	UI.icon("target", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(18, 432), Parent = face })
	UI.text({
		Text = "Target priority",
		font = "label",
		size = 16,
		Position = UDim2.new(0, 56, 0, 447),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = face,
	})
	local segments = UI.new(
		"Frame",
		{
			Name = "Targeting",
			BackgroundColor3 = V.Slot,
			BackgroundTransparency = 0.25,
			Size = UDim2.new(1, -36, 0, 60),
			Position = UDim2.fromOffset(18, 472),
			Parent = face,
		}
	)
	UI.corner(segments, 14)
	UI.stroke(segments, 3)
	UI.padding(segments, 6)
	UI.list(segments, Enum.FillDirection.Horizontal, 6)
	local segmentButtons: { [string]: TextButton } = {}
	for i, mode in Targeting.MODES do
		local seg = UI.new(
			"TextButton",
			{
				Name = mode,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = V.Gold,
				BackgroundTransparency = 1,
				Size = UDim2.new(0.25, -5, 1, 0),
				LayoutOrder = i,
				Parent = segments,
			}
		)
		UI.corner(seg, 10)
		local ring = UI.stroke(seg, 3, Color3.new(1, 1, 1))
		ring.Enabled = false
		UI.text({ Name = "Label", Text = mode, font = "label", size = 16, Size = UDim2.fromScale(1, 1), Parent = seg })
		seg.Activated:Connect(function()
			local model = currentModel
			if model and model:GetAttribute("Owner") == Players.LocalPlayer.UserId then
				Remotes.get("SetTargeting"):FireServer(model:GetAttribute("Uid"), mode)
			end
		end)
		segmentButtons[mode] = seg
	end

	local sellButton = UI.button(
		{
			Name = "Sell",
			Text = "Sell",
			icon = "coin",
			style = "red",
			Size = UDim2.new(1, -36, 0, 62),
			Position = UDim2.new(0, 18, 1, -84),
			textSize = 22,
			Parent = face,
		},
		function()
			local model = currentModel
			if model then
				Remotes.get("SellTower"):FireServer(model:GetAttribute("Uid"))
				Placement.select(nil)
			end
		end
	)

	local portraitIcon: GuiObject? = nil
	local function refresh()
		local model = currentModel
		if not model or not model.Parent then
			return
		end
		local towerId = model:GetAttribute("TowerId")
		local def = if type(towerId) == "string" then TowerData[towerId] else nil
		if not def then
			return
		end
		local mine = model:GetAttribute("Owner") == Players.LocalPlayer.UserId
		local tiers: Upgrades.Tiers =
			{ A = tonumber(model:GetAttribute("TierA")) or 0, B = tonumber(model:GetAttribute("TierB")) or 0 }
		UI.setText(title, def.displayName)
		local pops = model:GetAttribute("Pops") or 0
		UI.setText(
			subtitle,
			if mine then `Your tower · {pops} pops` else `{model:GetAttribute("OwnerName")}'s tower · {pops} pops`
		)
		local cash = Store.cash()

		for key, ui in paths do
			local pathKey: Upgrades.PathKey = if key == "A" then "A" else "B"
			local pathDef = def.paths[pathKey]
			local accent = if key == "A" then V.PathA else V.PathB
			UI.setText(ui.tag, `{key} · {pathDef.name}`)
			for t, pip in ui.pips do
				pip.BackgroundColor3 = if t <= tiers[pathKey] then accent else PIP_OFF
			end
			if ui.tier >= 0 and tiers[pathKey] > ui.tier then
				local pip = ui.pips[tiers[pathKey]]
				if pip then
					Motion.punch(pip, 1.4)
				end
				Motion.punch(ui.button, 1.1)
			end
			ui.tier = tiers[pathKey]
			local nextTier = Upgrades.nextTier(def, tiers, pathKey)
			if nextTier then
				ui.caption.Visible = true
				ui.lockIcon.Visible = false
				ui.name.Position = UDim2.fromOffset(12, 90)
				UI.setText(ui.name, nextTier.name)
				ui.desc.Text = nextTier.description
				UI.setButtonText(ui.button, UI.formatCash(nextTier.cost))
				UI.setButtonStyle(ui.button, if mine and cash >= nextTier.cost then "green" else "gray")
				ui.button.Visible = mine
			else
				local _, reason = Upgrades.canUpgrade(tiers, pathKey)
				local maxed = reason == "Path maxed"
				ui.caption.Visible = false
				ui.lockIcon.Visible = not maxed
				ui.name.Position = UDim2.fromOffset(if maxed then 12 else 52, 90)
				UI.setText(ui.name, if maxed then "Maxed!" else "Locked")
				ui.desc.Text = if maxed
					then "This path is fully upgraded."
					else "The other path is past tier 1. Only one path can go above tier 1."
				UI.setButtonText(ui.button, if maxed then "Max" else "Locked")
				UI.setButtonStyle(ui.button, "gray")
				ui.button.Visible = mine
			end
		end

		local mode = model:GetAttribute("Targeting") or "First"
		for name, seg in segmentButtons do
			local selected = name == mode
			seg.BackgroundTransparency = if selected then 0 else 1
			local ring = seg:FindFirstChildOfClass("UIStroke")
			if ring then
				ring.Enabled = selected
			end
			seg.Active = mine
		end
		segments.Visible = #def.base.attacks > 0
		sellButton.Visible = mine
		UI.setButtonText(sellButton, `Sell for {UI.formatCash(tonumber(model:GetAttribute("SellValue")) or 0)}`)
	end

	local attributeConnection: RBXScriptConnection? = nil
	Placement.selected:Connect(function(model)
		if attributeConnection then
			attributeConnection:Disconnect()
			attributeConnection = nil
		end
		local previous = currentModel
		currentModel = model
		if model then
			local def = TowerData[model:GetAttribute("TowerId") :: string]
			if portraitIcon then
				portraitIcon:Destroy()
			end
			if def then
				portraitIcon = UI.icon(def.icon, { Size = UDim2.fromScale(1, 1), Parent = portrait })
			end
			for _, ui in paths do
				ui.tier = -1
			end
			attributeConnection = model.AttributeChanged:Connect(refresh)
			refresh()
			if previous == nil or not panel.holder.Visible then
				Motion.slide(panel.holder, hidden, shown, true)
			else
				Motion.punch(panel.holder, 1.03)
			end
		elseif panel.holder.Visible then
			Motion.slide(panel.holder, hidden, shown, false)
		end
	end)
	Store.matchChanged:Connect(refresh)
end

return TowerPanel
