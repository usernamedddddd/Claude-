--!strict
-- Lobby UI from the Figma "Lobby + Towers shop" frame: Goo + level pills, Towers / Store menu,
-- the tower shop (TowerCard: Owned / Can unlock / Need Goo), the stubbed store, the queue
-- banner with countdown chip, and toasts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Monetization = require(script.Parent.Monetization)
local Motion = require(script.Parent.Motion)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local LobbyUI = {}

local C = UI.Colors

function LobbyUI.start()
	local gui = UI.screen("Lobby", 1)
	local root = UI.root(gui)

	-- Profile pills
	local top = UI.new("Frame", {
		Name = "Profile",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(800, 70),
		Position = UDim2.fromOffset(32, 28),
		Parent = root,
	})
	UI.list(top, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Left)
	local goo = UI.pill({ Name = "Goo", icon = "goo", width = 220, LayoutOrder = 1, Parent = top })
	local level = UI.pill({ Name = "Level", icon = "star", width = 330, LayoutOrder = 2, Parent = top })

	-- Modals
	local scrim = UI.new("TextButton", {
		Name = "Scrim",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	local function modal(name: string, title: string, icon: string): (any, Frame)
		local m = UI.surface({
			Name = name,
			Size = UDim2.fromOffset(900, 790),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			color = C.Panel,
			radius = 36,
			Visible = false,
			Parent = root,
		})
		UI.icon(icon, { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(32, 28), Parent = m.face })
		UI.text({
			Text = title,
			size = 60,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(400, 70),
			Position = UDim2.fromOffset(96, 20),
			Parent = m.face,
			strokeThickness = 3,
		})
		UI.button({
			Name = "Close",
			icon = "close",
			color = C.Red,
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(1, -32, 0, 24),
			AnchorPoint = Vector2.new(1, 0),
			radius = 18,
			Parent = m.face,
		}, function()
			m.holder.Visible = false
			scrim.Visible = false
		end)
		local grid = UI.new("Frame", {
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -64, 1, -130),
			Position = UDim2.fromOffset(32, 112),
			Parent = m.face,
		})
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(260, 310),
			CellPadding = UDim2.fromOffset(22, 26),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		return m, grid
	end

	local towerModal, towerGrid = modal("Towers", "Towers", "shop")
	local gooTag = UI.pill({
		Name = "GooTag",
		icon = "goo",
		width = 200,
		Position = UDim2.new(1, -112, 0, 24),
		AnchorPoint = Vector2.new(1, 0),
		Parent = towerModal.face,
	})

	type Card = { action: TextButton, holder: GuiObject }
	local cards: { [string]: Card } = {}
	local defs = {}
	for _, def in TowerData do
		table.insert(defs, def)
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	for _, def in defs do
		local card = UI.surface({
			Name = def.id,
			color = C.Card,
			radius = 24,
			LayoutOrder = def.order,
			Size = UDim2.fromOffset(260, 310),
			Parent = towerGrid,
		})
		local art = UI.new("Frame", {
			Name = "Art",
			BackgroundColor3 = Color3.fromHex("#F3E8FF"),
			Size = UDim2.fromOffset(110, 110),
			Position = UDim2.new(0.5, 0, 0, 18),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.corner(art, 999)
		UI.icon(def.icon, {
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = art,
		})
		UI.text({
			Text = def.displayName,
			size = 26,
			color = C.TextDark,
			Size = UDim2.new(1, -20, 0, 32),
			Position = UDim2.fromOffset(10, 136),
			Parent = card.face,
		})
		UI.text({
			Text = def.description,
			size = 15,
			color = C.TextDark,
			Size = UDim2.new(1, -28, 0, 46),
			Position = UDim2.fromOffset(14, 170),
			Parent = card.face,
		})
		local action = UI.button({
			Name = "Action",
			Text = "Unlock",
			color = C.Green,
			Size = UDim2.new(1, -28, 0, 56),
			Position = UDim2.new(0, 14, 1, -72),
			textSize = 20,
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
		cards[def.id] = { action = action, holder = card.holder }
	end

	local storeModal, storeGrid = modal("Store", "Store", "shop")
	local order = 0
	for key, product in Products do
		order += 1
		local card = UI.surface({
			Name = key,
			color = C.Card,
			radius = 24,
			LayoutOrder = order,
			Size = UDim2.fromOffset(260, 310),
			Parent = storeGrid,
		})
		UI.icon(if product.kind == "gamepass" then "star" else "goo", {
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.new(0.5, 0, 0, 22),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card.face,
		})
		UI.text({
			Text = product.displayName,
			size = 24,
			color = C.TextDark,
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.fromOffset(10, 118),
			Parent = card.face,
		})
		UI.text({
			Text = product.description,
			size = 16,
			color = C.TextDark,
			Size = UDim2.new(1, -28, 0, 66),
			Position = UDim2.fromOffset(14, 152),
			Parent = card.face,
		})
		UI.button({
			Name = "Buy",
			Text = "Buy",
			icon = "coin",
			color = C.Gold,
			Size = UDim2.new(1, -28, 0, 56),
			Position = UDim2.new(0, 14, 1, -72),
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

	-- Menu
	local menu = UI.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 160),
		Position = UDim2.new(0, 32, 0.5, -80),
		Parent = root,
	})
	UI.list(menu, Enum.FillDirection.Vertical, 16, Enum.HorizontalAlignment.Left)
	UI.button({
		Name = "TowersButton",
		Text = "Towers",
		icon = "frog",
		color = C.Green,
		Size = UDim2.fromOffset(240, 66),
		LayoutOrder = 1,
		Parent = menu,
	}, function()
		open(towerModal)
	end)
	UI.button({
		Name = "StoreButton",
		Text = "Store",
		icon = "shop",
		color = C.Gold,
		Size = UDim2.fromOffset(240, 66),
		LayoutOrder = 2,
		Parent = menu,
	}, function()
		open(storeModal)
	end)

	-- Queue banner
	local queue = UI.new("Frame", {
		Name = "Queue",
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromOffset(0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -32),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UI.corner(queue, 999)
	UI.stroke(queue, 4)
	UI.padding(queue, 6, 28, 8, 22)
	UI.list(queue, Enum.FillDirection.Horizontal, 14)
	UI.icon("play", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 1, Parent = queue })
	local queueLabel = UI.text({
		Name = "QueueLabel",
		Text = "Walk onto the glowing pad to start a match!",
		size = 26,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = queue,
	})
	local countdownChip, countdownLabel = UI.chip({
		Name = "Countdown",
		Text = "",
		color = C.Gold,
		textSize = 20,
		LayoutOrder = 3,
		Visible = false,
		Parent = queue,
	})
	local lastCountdown: number? = nil
	Remotes.get("QueueState").OnClientEvent:Connect(function(state: { [string]: any })
		local players = state.players or {}
		if #players == 0 then
			queueLabel.Text = "Walk onto the glowing pad to start a match!"
			countdownChip.Visible = false
			lastCountdown = nil
		else
			queueLabel.Text = `On the pad {#players}/{state.max}: {table.concat(players, ", ")}`
			countdownChip.Visible = true
			countdownLabel.Text = `Starting in {state.countdown or 0}`
			if state.countdown ~= lastCountdown then
				Motion.punch(countdownChip, 1.12)
				lastCountdown = state.countdown
			end
		end
	end)

	-- Toasts
	local toast, toastLabel = UI.chip({
		Name = "Toast",
		Text = "",
		height = 56,
		textSize = 26,
		color = C.Gold,
		Position = UDim2.new(0.5, 0, 0, -80),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local token = 0
	Store.notified:Connect(function(message, kind)
		token += 1
		local mine = token
		local fill = if kind == "error" then C.Red elseif kind == "success" then C.Green else C.Panel
		toast.BackgroundColor3 = fill
		toastLabel.Text = message
		toastLabel.TextColor3 = UI.labelColorFor(fill)
		if kind == "error" then
			Sound.play("error")
		elseif kind == "success" then
			Sound.play("sparkle")
		end
		Motion.slide(toast, UDim2.new(0.5, 0, 0, -80), UDim2.new(0.5, 0, 0, 120), true)
		task.delay(3, function()
			if mine == token then
				Motion.slide(toast, UDim2.new(0.5, 0, 0, -80), UDim2.new(0.5, 0, 0, 120), false)
			end
		end)
	end)

	local lastGoo: number? = nil
	local function refresh()
		local profile = Store.profile
		if not profile then
			return
		end
		Motion.countTo(goo.value, profile.goo, function(n)
			return `{n} Goo`
		end)
		if lastGoo and profile.goo ~= lastGoo then
			Motion.punch(goo.holder)
		end
		lastGoo = profile.goo
		gooTag.value.Text = `{profile.goo} Goo`
		local xpInLevel = profile.xp % Config.XP_PER_LEVEL
		level.value.Text = `Level {profile.level} · {xpInLevel}/{Config.XP_PER_LEVEL} XP`
		for id, card in cards do
			local def = TowerData[id]
			local owned = profile.unlocked[id] == true
			local wasOwned = card.action:GetAttribute("Owned") == true
			if owned then
				UI.setButtonText(card.action, "Owned ✔")
				UI.setButtonColor(card.action, C.Disabled)
				if not wasOwned and card.action:GetAttribute("Owned") ~= nil then
					Motion.punch(card.holder, 1.08) -- just unlocked
				end
			elseif profile.goo >= def.unlockGoo then
				UI.setButtonText(card.action, `Unlock · {def.unlockGoo} Goo`)
				UI.setButtonColor(card.action, C.Green)
			else
				UI.setButtonText(card.action, `Need {def.unlockGoo} Goo`)
				UI.setButtonColor(card.action, C.Disabled)
			end
			card.action:SetAttribute("Owned", owned)
		end
	end
	Store.profileChanged:Connect(refresh)
	refresh()
end

return LobbyUI
