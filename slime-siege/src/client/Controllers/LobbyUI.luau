--!strict
-- Lobby UI from the Figma "Lobby v2" frame (reference style): announcement strip, SHOP /
-- BADGES menu tiles (windows in ShopUI / BadgesUI), Goo counter, Settings tile, the big green
-- PLAY button (moves you onto the queue pad), queue status chip, the numbered loadout of your
-- towers and the level/XP bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local BadgesUI = require(script.Parent.BadgesUI)
local Motion = require(script.Parent.Motion)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ShopUI = require(script.Parent.ShopUI)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local LobbyUI = {}

local V = UI.V2

local function sortedDefs(): { TowerData.TowerDef }
	local defs = {}
	for _, def in TowerData do
		table.insert(defs, def)
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	return defs
end

function LobbyUI.start()
	local gui = UI.screen("Lobby", 1)
	local root = UI.root(gui)

	---------------------------------------------------------------- announcement strip
	local news = UI.new("Frame", {
		Name = "Announcement",
		BackgroundColor3 = V.Slot,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	UI.corner(news, 14)
	UI.padding(news, 0, 10, 0, 20)
	UI.list(news, Enum.FillDirection.Horizontal, 14)
	local newsLabel = UI.text({ Name = "Label", Text = "", font = "label", size = 18, LayoutOrder = 1, Parent = news })

	---------------------------------------------------------------- left menu + Goo
	local menu = UI.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(270, 190),
		Position = UDim2.new(0, 40, 0, 290),
		Parent = root,
	})
	UI.list(menu, Enum.FillDirection.Vertical, 16, Enum.HorizontalAlignment.Left).VerticalAlignment =
		Enum.VerticalAlignment.Top
	local gooFrame, gooValue = UI.currency({
		Name = "Goo",
		icon = "goo",
		color = V.GooText,
		Position = UDim2.new(0, 48, 0, 500),
		Parent = root,
	})

	---------------------------------------------------------------- windows (Shop / Badges)
	local scrim = UI.new("TextButton", {
		Name = "Scrim",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = V.Slot,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = root,
	})
	local windows: { GuiObject } = {}
	local function closeAll()
		for _, w in windows do
			w.Visible = false
		end
		scrim.Visible = false
	end
	local function open(w: GuiObject, onOpen: () -> ())
		local wasOpen = w.Visible
		closeAll()
		if wasOpen then
			return -- the menu tile toggles
		end
		onOpen()
		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.tween(scrim, 0.2, { BackgroundTransparency = 0.45 })
		Motion.popIn(w, 0.7, 0.35)
	end
	scrim.Activated:Connect(closeAll)
	local shop = ShopUI.build(root, closeAll)
	local badges = BadgesUI.build(root, closeAll)
	table.insert(windows, shop.holder)
	table.insert(windows, badges.holder)

	UI.menuTile(
		{ Name = "ShopButton", Text = "Shop", icon = "store", accent = V.Gold, LayoutOrder = 1, Parent = menu },
		function()
			open(shop.holder, shop.onOpen)
		end
	)
	local badgesTile = UI.menuTile(
		{ Name = "BadgesButton", Text = "Badges", icon = "medal", accent = V.Red, LayoutOrder = 2, Parent = menu },
		function()
			open(badges.holder, badges.onOpen)
		end
	)
	-- Red count bubble on the Badges tile while rewards are waiting to be claimed.
	local claimBubble = UI.new("Frame", {
		Name = "ClaimCount",
		BackgroundColor3 = V.Badge,
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(1, 10, 0, -12),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = 5,
		Parent = badgesTile,
	})
	UI.corner(claimBubble, 999)
	UI.stroke(claimBubble, 3, Color3.new(1, 1, 1))
	local claimCount =
		UI.text({ Text = "0", size = 20, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = claimBubble })

	---------------------------------------------------------------- top-right
	UI.squareTile({
		Name = "SettingsButton",
		icon = "settings",
		Text = "Settings",
		accent = V.Blue,
		Position = UDim2.new(1, -40, 0, 24),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
	}, function()
		SettingsPanel.toggle(root)
	end)

	---------------------------------------------------------------- PLAY + queue + loadout + XP
	local xp = UI.xpBar({ Position = UDim2.new(0.5, 0, 1, -82), AnchorPoint = Vector2.new(0.5, 0), Parent = root })
	local loadout = UI.new("Frame", {
		Name = "Loadout",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 110),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -100),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UI.list(loadout, Enum.FillDirection.Horizontal, 14)
	type LoadSlot = { icon: GuiObject, lock: GuiObject, status: TextLabel, ring: UIStroke }
	local loadSlots: { [string]: LoadSlot } = {}
	for i, def in sortedDefs() do
		local slot = UI.new("Frame", {
			Name = def.id,
			BackgroundColor3 = V.Slot,
			BackgroundTransparency = V.SlotTransparency,
			Size = UDim2.fromOffset(110, 110),
			LayoutOrder = i,
			Parent = loadout,
		})
		UI.corner(slot, 14)
		local ring = UI.stroke(slot, 3, V.SlotRing)
		local icon = UI.icon(def.icon, {
			Size = UDim2.fromOffset(68, 68),
			Position = UDim2.new(0.5, 0, 0, 10),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = slot,
		})
		local lock = UI.icon("lock", {
			Name = "Lock",
			Size = UDim2.fromOffset(58, 58),
			Position = UDim2.new(0.5, 0, 0, 12),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = slot,
		})
		local key = UI.new("Frame", {
			Name = "Key",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(6, 6),
			Parent = slot,
		})
		UI.corner(key, 7)
		UI.stroke(key, 2)
		UI.text({
			Text = tostring(i),
			font = "label",
			size = 18,
			color = Color3.new(0, 0, 0),
			stroke = false,
			Size = UDim2.fromScale(1, 1),
			Parent = key,
		})
		local status = UI.text({
			Name = "Status",
			Text = "",
			font = "label",
			size = 14,
			Position = UDim2.new(0.5, 0, 1, -16),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = slot,
		})
		loadSlots[def.id] = { icon = icon, lock = lock, status = status, ring = ring }
	end

	local playButton = UI.button({
		Name = "PlayButton",
		Text = "Play",
		style = "green",
		Size = UDim2.fromOffset(340, 92),
		Position = UDim2.new(0.5, 0, 1, -236),
		AnchorPoint = Vector2.new(0.5, 1),
		textSize = 44,
		strokeWidth = 6,
		Parent = root,
	}, function()
		Remotes.get("QuickPlay"):FireServer()
	end)
	local queueChip, queueLabel = UI.chip({
		Name = "Queue",
		Text = "",
		ring = V.Gold,
		height = 48,
		textSize = 18,
		Position = UDim2.new(0.5, 0, 1, -350),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	local lastCountdown: number? = nil
	Remotes.get("QueueState").OnClientEvent:Connect(function(state: { [string]: any })
		local players = state.players or {}
		if #players == 0 then
			queueChip.Visible = false
			UI.setButtonText(playButton, "Play")
			lastCountdown = nil
		else
			queueChip.Visible = true
			UI.setText(queueLabel, `On the pad {#players}/{state.max} · starting in {state.countdown or 0}`)
			UI.setButtonText(playButton, `Starting {state.countdown or 0}`)
			if state.countdown ~= lastCountdown then
				Motion.punch(queueChip, 1.1)
				lastCountdown = state.countdown
			end
		end
	end)

	---------------------------------------------------------------- toasts
	local toastHidden, toastShown = UDim2.new(0.5, 0, 0, -80), UDim2.new(0.5, 0, 0, 104)
	local toast, toastLabel = UI.chip({
		Name = "Toast",
		Text = "",
		height = 54,
		textSize = 20,
		Position = toastHidden,
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local toastStroke = toast:FindFirstChildOfClass("UIStroke") :: UIStroke
	local token = 0
	Store.notified:Connect(function(message, kind)
		token += 1
		local mine = token
		toastStroke.Color = if kind == "error" then V.Red elseif kind == "success" then V.Green else V.Blue
		UI.setText(toastLabel, message)
		if kind == "error" then
			Sound.play("error")
		elseif kind == "success" then
			Sound.play("sparkle")
		end
		Motion.slide(toast, toastHidden, toastShown, true)
		task.delay(3, function()
			if mine == token then
				Motion.slide(toast, toastHidden, toastShown, false)
			end
		end)
	end)

	---------------------------------------------------------------- profile → UI
	local lastGoo: number? = nil
	local function refresh()
		local profile = Store.profile
		if not profile then
			return
		end
		Motion.countTo(gooValue, profile.goo, tostring)
		if lastGoo and profile.goo ~= lastGoo then
			Motion.punch(gooFrame)
		end
		lastGoo = profile.goo

		local inLevel = profile.xp % Config.XP_PER_LEVEL
		UI.setText(xp.level, tostring(profile.level))
		UI.setText(xp.nextLevel, tostring(profile.level + 1))
		UI.setText(xp.exp, `{inLevel} Exp`)
		UI.setText(xp.max, tostring(Config.XP_PER_LEVEL))
		Motion.tween(xp.fill, 0.5, { Size = UDim2.fromScale(inLevel / Config.XP_PER_LEVEL, 1) })

		-- Announcement: the cheapest tower you can't afford yet, or what you can unlock now.
		local suggestion: TowerData.TowerDef? = nil
		for _, def in sortedDefs() do
			if
				not profile.unlocked[def.id]
				and (suggestion == nil or def.unlockGoo < (suggestion :: TowerData.TowerDef).unlockGoo)
			then
				suggestion = def
			end
		end
		news.Visible = suggestion ~= nil
		if suggestion then
			local s = suggestion :: TowerData.TowerDef
			UI.setText(
				newsLabel,
				if profile.goo >= s.unlockGoo
					then `You can unlock the {s.displayName} now!`
					else `Unlock the {s.displayName} for {s.unlockGoo} Goo!`
			)
		end

		local claimable = 0
		for _, claimed in profile.badges do
			if claimed == false then
				claimable += 1
			end
		end
		local hadBubble = claimBubble.Visible
		claimBubble.Visible = claimable > 0
		claimCount.Text = tostring(claimable)
		if claimable > 0 and not hadBubble then
			Motion.popIn(claimBubble, 0.3, 0.35)
		end

		for id, def in TowerData do
			local owned = profile.unlocked[id] == true
			local slot = loadSlots[id]
			slot.icon.Visible = owned
			slot.lock.Visible = not owned
			UI.setText(slot.status, if owned then "Owned" else `{def.unlockGoo} Goo`)
			slot.status.TextColor3 = if owned then V.GooText else V.Muted
			slot.ring.Color = if owned then V.SlotRing else Color3.fromHex("#6E6680")
		end
	end
	Store.profileChanged:Connect(refresh)
	refresh()
end

return LobbyUI
