--!strict
-- Lobby UI from the Figma "Lobby v2" frame (reference style): announcement strip, STORE /
-- TOWERS menu tiles, Goo counter, Settings tile, the big green PLAY button (moves you onto the
-- queue pad), queue status chip, the numbered loadout of your towers, the level/XP bar, and the
-- Towers shop / Store popups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Monetization = require(script.Parent.Monetization)
local Motion = require(script.Parent.Motion)
local SettingsPanel = require(script.Parent.SettingsPanel)
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

	---------------------------------------------------------------- popups
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
	local function popup(name: string, title: string, icon: string, accent: Color3): (any, Frame)
		local m = UI.panel({
			Name = name,
			Size = UDim2.fromOffset(920, 780),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			accent = accent,
			strokeWidth = 6,
			radius = 28,
			Visible = false,
			Parent = root,
		})
		UI.icon(icon, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(28, 18), Parent = m.face })
		UI.text({
			Text = title,
			font = "label",
			size = 48,
			Position = UDim2.new(0, 104, 0, 50),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = m.face,
		})
		UI.button({
			Name = "Close",
			icon = "close",
			style = "red",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(1, -28, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			iconSize = 34,
			Parent = m.face,
		}, function()
			m.holder.Visible = false
			scrim.Visible = false
		end)
		local grid = UI.new("Frame", {
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -56, 1, -124),
			Position = UDim2.fromOffset(28, 104),
			Parent = m.face,
		})
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(268, 304),
			CellPadding = UDim2.fromOffset(20, 24),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		return m, grid
	end

	local towerModal, towerGrid = popup("Towers", "Towers", "towers", V.Cyan)
	type Card = { action: TextButton, holder: GuiObject, ring: UIStroke }
	local cards: { [string]: Card } = {}
	for _, def in sortedDefs() do
		local card = UI.panel({
			Name = def.id,
			accent = V.SlotRing,
			strokeWidth = 4,
			radius = 20,
			lip = 0,
			LayoutOrder = def.order,
			Size = UDim2.fromOffset(268, 304),
			Parent = towerGrid,
		})
		UI.icon(def.icon, {
			Size = UDim2.fromOffset(104, 104),
			Position = UDim2.new(0.5, 0, 0, 14),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.text({
			Text = def.displayName,
			size = 28,
			Position = UDim2.new(0.5, 0, 0, 128),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.text({
			Text = def.description,
			size = 15,
			color = Color3.fromHex("#E2DCEE"),
			stroke = false,
			TextWrapped = true,
			Size = UDim2.new(1, -28, 0, 48),
			Position = UDim2.fromOffset(14, 168),
			Parent = card.face,
		})
		local action = UI.button({
			Name = "Action",
			Text = "Unlock",
			style = "green",
			Size = UDim2.new(1, -28, 0, 56),
			Position = UDim2.new(0, 14, 1, -70),
			textSize = 18,
			Parent = card.face,
		}, function()
			local profile = Store.profile
			if profile and not profile.unlocked[def.id] then
				if profile.goo >= def.unlockGoo then
					Remotes.get("UnlockTower"):FireServer(def.id)
				else
					Sound.play("error")
					Motion.shake(card.holder, 6, 3)
				end
			end
		end)
		cards[def.id] = { action = action, holder = card.holder, ring = card.stroke }
	end

	local storeModal, storeGrid = popup("Store", "Store", "store", V.Red)
	local order = 0
	for key, product in Products do
		order += 1
		local card = UI.panel({
			Name = key,
			accent = V.Gold,
			strokeWidth = 4,
			radius = 20,
			lip = 0,
			LayoutOrder = order,
			Size = UDim2.fromOffset(268, 304),
			Parent = storeGrid,
		})
		UI.icon(if product.kind == "gamepass" then "star" else "goo", {
			Size = UDim2.fromOffset(90, 90),
			Position = UDim2.new(0.5, 0, 0, 18),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.text({
			Text = product.displayName,
			size = 26,
			Position = UDim2.new(0.5, 0, 0, 118),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.text({
			Text = product.description,
			size = 16,
			color = Color3.fromHex("#E2DCEE"),
			stroke = false,
			TextWrapped = true,
			Size = UDim2.new(1, -28, 0, 58),
			Position = UDim2.fromOffset(14, 158),
			Parent = card.face,
		})
		UI.button({
			Name = "Buy",
			Text = "Buy",
			icon = "coin",
			style = "gold",
			Size = UDim2.new(1, -28, 0, 56),
			Position = UDim2.new(0, 14, 1, -70),
			Parent = card.face,
		}, function()
			Monetization.promptPurchase(key, function()
				Store.notified:Fire(`Thanks! {product.displayName} granted.`, "success")
			end)
		end)
	end

	local function open(m: any)
		towerModal.holder.Visible = false
		storeModal.holder.Visible = false
		scrim.Visible = true
		Motion.popIn(m.holder, 0.7, 0.35)
	end
	scrim.Activated:Connect(function()
		towerModal.holder.Visible = false
		storeModal.holder.Visible = false
		scrim.Visible = false
	end)

	UI.menuTile(
		{ Name = "StoreButton", Text = "Store", icon = "store", accent = V.Red, LayoutOrder = 1, Parent = menu },
		function()
			open(storeModal)
		end
	)
	UI.menuTile(
		{ Name = "TowersButton", Text = "Towers", icon = "towers", accent = V.Cyan, LayoutOrder = 2, Parent = menu },
		function()
			open(towerModal)
		end
	)

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

		for id, card in cards do
			local def = TowerData[id]
			local owned = profile.unlocked[id] == true
			local wasOwned = card.action:GetAttribute("Owned")
			if owned then
				UI.setButtonText(card.action, "Owned")
				UI.setButtonStyle(card.action, "gray")
				card.ring.Color = V.Green
				if wasOwned == false then
					Motion.punch(card.holder, 1.08)
				end
			elseif profile.goo >= def.unlockGoo then
				UI.setButtonText(card.action, `Unlock · {def.unlockGoo} Goo`)
				UI.setButtonStyle(card.action, "green")
				card.ring.Color = V.SlotRing
			else
				UI.setButtonText(card.action, `Need {def.unlockGoo} Goo`)
				UI.setButtonStyle(card.action, "gray")
				card.ring.Color = V.SlotRing
			end
			card.action:SetAttribute("Owned", owned)

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
