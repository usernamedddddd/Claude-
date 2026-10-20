--!strict
-- Lobby UI: Goo + level, tower unlock shop (spend Goo), store (stubbed purchases) and the
-- queue pad status.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Products = require(Shared.Data.Products)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Monetization = require(script.Parent.Monetization)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local LobbyUI = {}

local C = UI.Colors

function LobbyUI.start()
	local gui = UI.screen("Lobby", 1)

	local top = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.6, 0.075),
		Position = UDim2.fromScale(0.01, 0.015),
		Parent = gui,
	})
	UI.list(top, Enum.FillDirection.Horizontal, 0.01, Enum.HorizontalAlignment.Left)
	local function pill(icon: string, color: Color3, order: number): TextLabel
		local p =
			UI.panel({ Size = UDim2.fromScale(1, 1), color = color, LayoutOrder = order, Parent = top, corner = 0.5 })
		UI.aspect(p, 3, Enum.DominantAxis.Height)
		UI.icon(icon, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.04, 0.1), Parent = p })
		return UI.text({
			Text = "",
			Size = UDim2.fromScale(0.62, 0.75),
			Position = UDim2.fromScale(0.33, 0.12),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = p,
		})
	end
	local gooText = pill("goo", C.Green, 1)
	local levelText = pill("star", C.Purple, 2)

	-- Side buttons
	local side = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.12, 0.3),
		Position = UDim2.fromScale(0.01, 0.35),
		Parent = gui,
	})
	UI.list(side, Enum.FillDirection.Vertical, 0.05, Enum.HorizontalAlignment.Left)

	local function modal(name: string, titleText: string): (Frame, Frame)
		local panel = UI.panel({
			Size = UDim2.fromScale(0.6, 0.7),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			Name = name,
			Parent = gui,
		})
		UI.aspect(panel, 1.45)
		UI.text({
			Text = titleText,
			Size = UDim2.fromScale(0.7, 0.1),
			Position = UDim2.fromScale(0.15, 0.03),
			Parent = panel,
		})
		UI.button({
			Text = "✖",
			Size = UDim2.fromScale(0.08, 0.1),
			Position = UDim2.fromScale(0.9, 0.03),
			color = C.Red,
			Parent = panel,
		}, function()
			panel.Visible = false
		end)
		local grid = UI.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.94, 0.8),
			Position = UDim2.fromScale(0.03, 0.16),
			Parent = panel,
		})
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromScale(0.31, 0.46),
			CellPadding = UDim2.fromScale(0.02, 0.04),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		return panel, grid
	end

	-- Tower shop
	local towerPanel, towerGrid = modal("Towers", "Towers")
	local towerCards: { [string]: { button: TextButton, status: TextLabel } } = {}
	local defs = {}
	for _, def in TowerData do
		table.insert(defs, def)
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	for _, def in defs do
		local card = UI.new("Frame", { BackgroundColor3 = C.Panel, LayoutOrder = def.order, Parent = towerGrid })
		UI.corner(card, 0.12)
		UI.stroke(card, 3)
		UI.icon(def.icon, {
			Size = UDim2.fromScale(0.4, 0.34),
			Position = UDim2.fromScale(0.5, 0.04),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card,
		})
		UI.text({
			Text = def.displayName,
			Size = UDim2.fromScale(0.9, 0.15),
			Position = UDim2.fromScale(0.05, 0.38),
			color = C.TextDark,
			stroke = false,
			Parent = card,
		})
		local status = UI.text({
			Text = "",
			Size = UDim2.fromScale(0.9, 0.12),
			Position = UDim2.fromScale(0.05, 0.53),
			color = C.TextDark,
			stroke = false,
			Parent = card,
		})
		local button = UI.button({
			Text = "",
			Size = UDim2.fromScale(0.84, 0.24),
			Position = UDim2.fromScale(0.08, 0.7),
			color = C.Green,
			Parent = card,
		}, function()
			Remotes.get("UnlockTower"):FireServer(def.id)
		end)
		towerCards[def.id] = { button = button, status = status }
	end

	-- Store (stubbed purchases)
	local storePanel, storeGrid = modal("Store", "Store")
	local order = 0
	for key, product in Products do
		order += 1
		local card = UI.new("Frame", { BackgroundColor3 = C.Panel, LayoutOrder = order, Parent = storeGrid })
		UI.corner(card, 0.12)
		UI.stroke(card, 3)
		UI.icon(if product.kind == "gamepass" then "star" else "goo", {
			Size = UDim2.fromScale(0.3, 0.26),
			Position = UDim2.fromScale(0.5, 0.04),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = card,
		})
		UI.text({
			Text = product.displayName,
			Size = UDim2.fromScale(0.9, 0.15),
			Position = UDim2.fromScale(0.05, 0.32),
			color = C.TextDark,
			stroke = false,
			Parent = card,
		})
		UI.text({
			Text = product.description,
			Size = UDim2.fromScale(0.9, 0.2),
			Position = UDim2.fromScale(0.05, 0.48),
			color = C.TextDark,
			stroke = false,
			maxTextSize = 20,
			Parent = card,
		})
		UI.button({
			Text = "Buy",
			Size = UDim2.fromScale(0.84, 0.22),
			Position = UDim2.fromScale(0.08, 0.73),
			color = C.Gold,
			Parent = card,
		}, function()
			Monetization.promptPurchase(key, function()
				Store.notified:Fire(`Thanks! {product.displayName} granted.`, "success")
			end)
		end)
	end

	local towersButton = UI.button(
		{ Text = "🐸 Towers", Size = UDim2.fromScale(1, 0.3), color = C.Green, LayoutOrder = 1, Parent = side },
		function()
			towerPanel.Visible = not towerPanel.Visible
			storePanel.Visible = false
		end
	)
	UI.aspect(towersButton, 2.6)
	local storeButton = UI.button(
		{ Text = "🛒 Store", Size = UDim2.fromScale(1, 0.3), color = C.Gold, LayoutOrder = 2, Parent = side },
		function()
			storePanel.Visible = not storePanel.Visible
			towerPanel.Visible = false
		end
	)
	UI.aspect(storeButton, 2.6)

	-- Queue status
	local queueLabel = UI.text({
		Text = "Walk onto the glowing pad to start a match!",
		Size = UDim2.fromScale(0.6, 0.06),
		Position = UDim2.fromScale(0.5, 0.97),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = gui,
	})
	Remotes.get("QueueState").OnClientEvent:Connect(function(state: { [string]: any })
		local players = state.players or {}
		if #players == 0 then
			queueLabel.Text = "Walk onto the glowing pad to start a match!"
		else
			queueLabel.Text =
				`On the pad ({#players}/{state.max}): {table.concat(players, ", ")}  -  {state.countdown or 0}s`
		end
	end)

	local toast = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.5, 0.06),
		Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	toast.Visible = false
	local token = 0
	Store.notified:Connect(function(message, kind)
		token += 1
		local mine = token
		toast.Text = message
		toast.TextColor3 = if kind == "error" then C.Red elseif kind == "success" then C.Green else C.Text
		toast.Visible = true
		task.delay(3, function()
			if mine == token then
				toast.Visible = false
			end
		end)
	end)

	local function refresh()
		local profile = Store.profile
		if not profile then
			return
		end
		gooText.Text = `{profile.goo} Goo`
		local xpInLevel = profile.xp % Config.XP_PER_LEVEL
		levelText.Text = `Lv {profile.level} ({xpInLevel}/{Config.XP_PER_LEVEL})`
		for id, card in towerCards do
			local def = TowerData[id]
			local owned = profile.unlocked[id] == true
			card.status.Text = if owned then "Unlocked ✔" else `{def.unlockGoo} Goo`
			UI.setButtonText(card.button, if owned then "Owned" else "Unlock")
			card.button.BackgroundColor3 = if owned
				then C.Gray
				elseif profile.goo >= def.unlockGoo then C.Green
				else C.Gray
		end
	end
	Store.profileChanged:Connect(refresh)
	refresh()
end

return LobbyUI
