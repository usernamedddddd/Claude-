--!strict
-- Badges window from the Figma "Badges window" frame: red-bordered window, "N / 16 EARNED",
-- an 8-wide grid of medallions (earned = colourful, locked = dim "?", equipped = gold ring,
-- claimable = green "!" dot), a detail strip with progress + CLAIM button, and EQUIP/UNEQUIP.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeData = require(Shared.Data.BadgeData)
local Theme = require(Shared.Data.Theme)
local Badges = require(Shared.Sim.Badges)
local Remotes = require(Shared.Net.Remotes)

local Motion = require(script.Parent.Motion)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local BadgesUI = {}

local V = UI.V2
local WHITE = Color3.new(1, 1, 1)
local COLUMNS = 8

type Medallion = { holder: Frame, disc: Frame, icon: GuiObject, nameTag: Frame, nameLabel: TextLabel, dot: Frame }

-- Round medallion with a name tag across its bottom edge and a green "!" dot.
local function medallion(parent: Instance, size: number, def: BadgeData.BadgeDef): Medallion
	local holder = UI.new("Frame", {
		Name = "Medallion",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = parent,
	})
	local disc = UI.new("Frame", {
		Name = "Disc",
		BackgroundColor3 = Theme.BadgeTint[def.tint],
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UI.corner(disc, 999)
	UI.stroke(disc, 3, V.Outline)
	UI.gradient(disc, WHITE, Color3.fromRGB(190, 190, 190))
	local icon = UI.icon(def.icon, {
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = disc,
	})
	local nameTag = UI.new("Frame", {
		Name = "NameTag",
		BackgroundColor3 = V.Slot,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = holder,
	})
	UI.corner(nameTag, 6)
	UI.stroke(nameTag, 2, Theme.BadgeTint[def.tint])
	UI.padding(nameTag, 0, 6, 0, 6)
	local nameLabel = UI.text({
		Name = "Label",
		Text = def.name,
		font = "label",
		size = 11,
		stroke = false,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 4,
		Parent = nameTag,
	})
	local dot = UI.new("Frame", {
		Name = "Claimable",
		BackgroundColor3 = V.Green,
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, 2, 0, -2),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = 5,
		Parent = holder,
	})
	UI.corner(dot, 999)
	UI.stroke(dot, 2, WHITE)
	UI.text({
		Text = "!",
		size = 18,
		stroke = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = dot,
	})
	return { holder = holder, disc = disc, icon = icon, nameTag = nameTag, nameLabel = nameLabel, dot = dot }
end

-- Earned look vs locked "?" look.
local function paint(m: Medallion, def: BadgeData.BadgeDef, earned: boolean)
	m.disc.BackgroundColor3 = if earned then Theme.BadgeTint[def.tint] else V.Locked
	m.icon.Visible = earned
	local question = m.disc:FindFirstChild("Question")
	if not earned and not question then
		UI.icon("question", {
			Name = "Question",
			Size = UDim2.fromScale(0.55, 0.55),
			Position = UDim2.fromScale(0.5, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = m.disc,
		})
	elseif earned and question then
		question:Destroy()
	end
	UI.setText(m.nameLabel, if earned then def.name else "???")
	local ring = m.nameTag:FindFirstChildOfClass("UIStroke")
	if ring then
		ring.Color = if earned then Theme.BadgeTint[def.tint] else V.Locked
	end
end

export type Window = { holder: GuiObject, onOpen: () -> () }

function BadgesUI.build(parent: Instance, onClose: () -> ()): Window
	local holder = UI.new("Frame", {
		Name = "Badges",
		BackgroundColor3 = V.Window,
		Size = UDim2.fromOffset(1000, 620),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	UI.corner(holder, 22)
	UI.stroke(holder, 6, V.Red)

	UI.text({
		Name = "Title",
		Text = "BADGES",
		size = 52,
		color = V.Red,
		strokeThickness = 4,
		Position = UDim2.new(0.5, 0, 0, 52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = holder,
	})
	local countLabel = UI.text({
		Name = "Count",
		Text = "0 / 16 earned",
		font = "label",
		size = 15,
		color = V.Muted,
		stroke = false,
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = holder,
	})
	UI.button({
		Name = "Close",
		icon = "close",
		style = "red",
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(1, -30, 0, 24),
		AnchorPoint = Vector2.new(1, 0),
		iconSize = 32,
		radius = 999,
		Parent = holder,
	}, onClose)

	---------------------------------------------------------------- grid
	local grid = UI.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMNS * 118 - 4, 2 * 118 - 4),
		Position = UDim2.new(0.5, 0, 0, 124),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = holder,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(114, 114),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	type Tile = { button: TextButton, ring: UIStroke, medal: Medallion, def: BadgeData.BadgeDef }
	local tiles: { [string]: Tile } = {}
	local selected = BadgeData.list[1].id
	local select: (string) -> ()

	for _, def in BadgeData.list do
		local button = UI.new("TextButton", {
			Name = def.id,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = V.WindowInner,
			LayoutOrder = def.order,
			Parent = grid,
		})
		UI.corner(button, 12)
		local ring = UI.stroke(button, 2, V.Locked)
		local medal = medallion(button, 88, def)
		button.Activated:Connect(function()
			Sound.play("click")
			select(def.id)
		end)
		local scale = Motion.scaleOf(button)
		button.MouseEnter:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1.06 })
		end)
		button.MouseLeave:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1 })
		end)
		tiles[def.id] = { button = button, ring = ring, medal = medal, def = def }
	end

	---------------------------------------------------------------- detail strip
	local detail = UI.new("Frame", {
		Name = "Detail",
		BackgroundColor3 = V.WindowInner,
		Size = UDim2.fromOffset(COLUMNS * 118 - 4, 140),
		Position = UDim2.new(0.5, 0, 0, 376),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = holder,
	})
	UI.corner(detail, 14)
	UI.stroke(detail, 2, V.Locked)
	local detailMedalBox = UI.new("Frame", {
		Name = "MedalBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(116, 116),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = detail,
	})
	local detailMedal: Medallion = medallion(detailMedalBox, 96, BadgeData.list[1])
	local detailName = UI.text({
		Name = "BadgeName",
		Text = "",
		size = 30,
		Position = UDim2.fromOffset(150, 28),
		Parent = detail,
	})
	local detailDesc = UI.text({
		Name = "Description",
		Text = "",
		font = "label",
		size = 15,
		color = V.Muted,
		stroke = false,
		Position = UDim2.fromOffset(150, 68),
		Parent = detail,
	})
	local track, fill = UI.bar({
		Name = "Progress",
		Size = UDim2.fromOffset(440, 16),
		Position = UDim2.fromOffset(150, 98),
		Parent = detail,
	})
	local progressLabel = UI.text({
		Name = "ProgressLabel",
		Text = "",
		size = 18,
		Position = UDim2.new(1, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = track,
	})
	local claim = UI.button({
		Name = "Claim",
		Text = "Claim",
		icon = "goo",
		style = "green",
		Size = UDim2.fromOffset(250, 72),
		Position = UDim2.new(1, -20, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		textSize = 26,
		Parent = detail,
	}, function()
		local profile = Store.profile
		if profile and profile.badges[selected] == false then
			Remotes.get("ClaimBadge"):FireServer(selected)
		else
			Sound.play("error")
			Motion.shake(detail, 5, 3)
		end
	end)

	local equip = UI.button({
		Name = "Equip",
		Text = "Equip",
		style = "purple",
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.new(0.5, 0, 1, -22),
		AnchorPoint = Vector2.new(0.5, 1),
		textSize = 26,
		Parent = holder,
	}, function()
		local profile = Store.profile
		if not profile or profile.badges[selected] == nil then
			Sound.play("error")
			Motion.shake(detail, 5, 3)
			return
		end
		Remotes.get("EquipBadge"):FireServer(if profile.equippedBadge == selected then "" else selected)
	end)

	local function showDetail()
		local def = BadgeData.byId[selected]
		local profile = Store.profile
		if not profile then
			return
		end
		local status = Badges.status(profile :: any, def.id)
		local earned = status ~= "locked"
		detailMedal.holder:Destroy()
		detailMedal = medallion(detailMedalBox, 96, def)
		paint(detailMedal, def, earned)
		detailMedal.dot.Visible = status == "claimable"
		UI.setText(detailName, def.name)
		UI.setText(detailDesc, def.description)
		local current, goal = Badges.progress(def, Badges.facts(profile :: any))
		if earned then
			current = goal
		end
		Motion.tween(fill, 0.35, { Size = UDim2.fromScale(current / goal, 1) })
		progressLabel.Text = `{current}/{goal}`
		claim.Visible = status ~= "locked"
		if status == "claimable" then
			UI.setButtonText(claim, `Claim {def.reward}`)
			UI.setButtonStyle(claim, "green")
		elseif status == "claimed" then
			UI.setButtonText(claim, "Claimed")
			UI.setButtonStyle(claim, "gray")
		end
		equip.Visible = earned
		UI.setButtonText(equip, if profile.equippedBadge == def.id then "Unequip" else "Equip")
		UI.setButtonStyle(equip, if profile.equippedBadge == def.id then "gray" else "purple")
	end

	function select(id: string)
		selected = id
		local profile = Store.profile
		for tileId, tile in tiles do
			local equipped = profile ~= nil and profile.equippedBadge == tileId
			tile.ring.Color = if equipped then V.Gold elseif tileId == id then WHITE else V.Locked
			tile.ring.Thickness = if equipped or tileId == id then 4 else 2
		end
		showDetail()
		Motion.punch(detail, 1.02)
	end

	local function refresh()
		local profile = Store.profile
		if not profile then
			return
		end
		local badges = profile.badges or {}
		for id, tile in tiles do
			local status = Badges.status(profile :: any, id)
			local was = tile.button:GetAttribute("Status")
			paint(tile.medal, tile.def, status ~= "locked")
			tile.medal.dot.Visible = status == "claimable"
			tile.button:SetAttribute("Status", status)
			if was == "locked" and status ~= "locked" then
				Motion.popIn(tile.medal.holder, 0.4, 0.4)
			end
		end
		UI.setText(countLabel, `{Badges.earnedCount(badges)} / {#BadgeData.list} earned`)
		select(selected)
	end
	Store.profileChanged:Connect(refresh)
	refresh()

	-- Open on the first claimable badge, if any (so the reward is one click away).
	local function onOpen()
		local profile = Store.profile
		if profile then
			for _, def in BadgeData.list do
				if profile.badges[def.id] == false then
					selected = def.id
					break
				end
			end
		end
		refresh()
	end

	return { holder = holder, onOpen = onOpen }
end

return BadgesUI
