--!strict
-- Tower upgrade panel from the Figma "Tower Panel" (Match HUD screen): portrait + name, two
-- upgrade-path cards (pink A / cyan B) with tier pips, the next upgrade or the crosspath lock,
-- a segmented targeting control, and sell. Read-only for teammates' towers.

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

local C = UI.Colors
local WIDTH = 460
local COLUMN_W = (WIDTH - 40 - 12) / 2

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
	local shown, hidden = UDim2.new(1, -32, 0, 250), UDim2.new(1, WIDTH + 40, 0, 250)
	local panel = UI.surface({
		Name = "Panel",
		Size = UDim2.fromOffset(WIDTH, 640),
		Position = hidden,
		AnchorPoint = Vector2.new(1, 0),
		color = C.Panel,
		radius = 28,
		Visible = false,
		Parent = root,
	})
	local face = panel.face

	-- Header
	local portrait = UI.new("Frame", {
		Name = "Portrait",
		BackgroundColor3 = C.PanelRaised,
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(20, 20),
		Parent = face,
	})
	UI.corner(portrait, 999)
	UI.stroke(portrait, 3)
	local title = UI.text({
		Name = "Title",
		Text = "",
		size = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 42),
		Position = UDim2.fromOffset(106, 20),
		TextWrapped = false,
		Parent = face,
	})
	local subtitle = UI.text({
		Name = "Subtitle",
		Text = "",
		size = 16,
		color = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.fromOffset(106, 64),
		Parent = face,
		stroke = false,
	})
	UI.button({
		Name = "Close",
		icon = "close",
		color = C.Red,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(1, -20, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		radius = 16,
		Parent = face,
	}, function()
		Placement.select(nil)
	end)

	local currentModel: Model? = nil
	local paths: { [string]: PathUI } = {}

	for i, key in { "A", "B" } do
		local accent = if key == "A" then C.Pink else C.Cyan
		local col = UI.surface({
			Name = "Path" .. key,
			Size = UDim2.fromOffset(COLUMN_W, 300),
			Position = UDim2.fromOffset(20 + (i - 1) * (COLUMN_W + 12), 112),
			color = C.Card,
			radius = 20,
			lip = 0,
			Parent = face,
		})
		local cf = col.face
		local tagChip, tagLabel =
			UI.chip({ Name = "Tag", Text = key, color = accent, Position = UDim2.fromOffset(12, 12), Parent = cf })
		local _ = tagChip
		local pipRow = UI.new("Frame", {
			Name = "Pips",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 14),
			Position = UDim2.fromOffset(12, 58),
			Parent = cf,
		})
		UI.list(pipRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
		local pips = {}
		for t = 1, 3 do
			local pip = UI.new("Frame", {
				Name = "Pip" .. t,
				BackgroundColor3 = C.Disabled,
				Size = UDim2.fromOffset(52, 14),
				LayoutOrder = t,
				Parent = pipRow,
			})
			UI.corner(pip, 999)
			UI.stroke(pip, 3)
			table.insert(pips, pip)
		end
		local caption = UI.text({
			Text = "NEXT UPGRADE",
			size = 14,
			color = C.Purple,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -24, 0, 18),
			Position = UDim2.fromOffset(12, 84),
			Parent = cf,
			stroke = false,
		})
		local lockIcon =
			UI.icon("lock", { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(12, 104), Parent = cf })
		local name = UI.text({
			Name = "UpgradeName",
			Text = "",
			size = 24,
			color = C.TextDark,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -24, 0, 30),
			Position = UDim2.fromOffset(12, 104),
			Parent = cf,
		})
		local desc = UI.text({
			Name = "Description",
			Text = "",
			size = 15,
			color = C.TextDark,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -24, 0, 76),
			Position = UDim2.fromOffset(12, 140),
			Parent = cf,
		})
		local button = UI.button({
			Name = "Upgrade",
			Text = "",
			icon = "coin",
			color = C.Green,
			Size = UDim2.new(1, -24, 0, 58),
			Position = UDim2.new(0, 12, 1, -72),
			textSize = 26,
			Parent = cf,
		}, function()
			local model = currentModel
			if model then
				Remotes.get("UpgradeTower"):FireServer(model:GetAttribute("Uid"), key)
			end
		end)
		paths[key] = {
			pips = pips,
			tag = tagLabel,
			caption = caption,
			name = name,
			desc = desc,
			lockIcon = lockIcon,
			button = button,
			tier = -1,
		}
	end

	-- Targeting (segmented)
	UI.icon("target", { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(20, 428), Parent = face })
	UI.text({
		Text = "Target priority",
		size = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(300, 28),
		Position = UDim2.fromOffset(56, 428),
		Parent = face,
	})
	local segments = UI.new("Frame", {
		Name = "Targeting",
		BackgroundColor3 = C.PanelRaised,
		Size = UDim2.new(1, -40, 0, 62),
		Position = UDim2.fromOffset(20, 466),
		Parent = face,
	})
	UI.corner(segments, 18)
	UI.stroke(segments, 3)
	UI.padding(segments, 6)
	UI.list(segments, Enum.FillDirection.Horizontal, 6)
	local segmentButtons: { [string]: TextButton } = {}
	for i, mode in Targeting.MODES do
		local seg = UI.new("TextButton", {
			Name = mode,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = C.Gold,
			BackgroundTransparency = 1,
			Size = UDim2.new(0.25, -5, 1, 0),
			LayoutOrder = i,
			Parent = segments,
		})
		UI.corner(seg, 12)
		local ring = UI.stroke(seg, 3)
		ring.Enabled = false
		UI.text({ Name = "Label", Text = mode, size = 22, Parent = seg })
		seg.Activated:Connect(function()
			local model = currentModel
			if model and model:GetAttribute("Owner") == Players.LocalPlayer.UserId then
				Remotes.get("SetTargeting"):FireServer(model:GetAttribute("Uid"), mode)
			end
		end)
		segmentButtons[mode] = seg
	end

	local sellButton = UI.button({
		Name = "Sell",
		Text = "Sell",
		icon = "coin",
		color = C.Red,
		Size = UDim2.new(1, -40, 0, 64),
		Position = UDim2.new(0, 20, 1, -86),
		Parent = face,
	}, function()
		local model = currentModel
		if model then
			Remotes.get("SellTower"):FireServer(model:GetAttribute("Uid"))
			Placement.select(nil)
		end
	end)

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
		title.Text = def.displayName
		local pops = model:GetAttribute("Pops") or 0
		subtitle.Text = if mine
			then `Your tower · {pops} pops`
			else `{model:GetAttribute("OwnerName")}'s tower · {pops} pops`
		local cash = Store.cash()

		for key, ui in paths do
			local pathKey: Upgrades.PathKey = if key == "A" then "A" else "B"
			local pathDef = def.paths[pathKey]
			local accent = if key == "A" then C.Pink else C.Cyan
			ui.tag.Text = `{key} · {pathDef.name}`
			for t, pip in ui.pips do
				pip.BackgroundColor3 = if t <= tiers[pathKey] then accent else C.Disabled
			end
			if ui.tier >= 0 and tiers[pathKey] > ui.tier then
				-- upgrade bought: newest pip pops, card punches (Figma motion spec)
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
				ui.name.Position = UDim2.fromOffset(12, 104)
				ui.name.Text = nextTier.name
				ui.desc.Text = nextTier.description
				UI.setButtonText(ui.button, UI.formatCash(nextTier.cost))
				UI.setButtonColor(ui.button, if mine and cash >= nextTier.cost then C.Green else C.Disabled)
				ui.button.Visible = mine
			else
				local _, reason = Upgrades.canUpgrade(tiers, pathKey)
				local maxed = reason == "Path maxed"
				ui.caption.Visible = false
				ui.lockIcon.Visible = not maxed
				ui.name.Position = UDim2.fromOffset(if maxed then 12 else 46, 104)
				ui.name.Text = if maxed then "Fully upgraded!" else "Locked"
				ui.desc.Text = if maxed
					then "This path is maxed out."
					else "The other path is past tier 1. Only one path can go above tier 1."
				UI.setButtonText(ui.button, if maxed then "MAX" else "Locked")
				UI.setButtonColor(ui.button, C.Disabled)
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
			local label = seg:FindFirstChild("Label") :: TextLabel?
			if label then
				label.TextColor3 = if selected then C.TextDark else C.Text
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Enabled = not selected
				end
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
				portraitIcon = UI.icon(def.icon, {
					Size = UDim2.fromScale(0.8, 0.8),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Parent = portrait,
				})
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
