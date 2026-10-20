--!strict
-- Shop window from the Figma "Shop window" frame: a gold "GOO & PASSES" side panel (Robux
-- bundles + game passes) next to the black SHOP window with rarity-coloured tower cards and a
-- red-bordered FEATURED TOWER card. Clicking a card features that tower; the featured buy
-- button unlocks it for Goo (the server re-checks everything).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Data.Products)
local Theme = require(Shared.Data.Theme)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Monetization = require(script.Parent.Monetization)
local Motion = require(script.Parent.Motion)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local ShopUI = {}

local V = UI.V2
local WHITE = Color3.new(1, 1, 1)

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

local function sortedProducts(): { Products.Product }
	local list = {}
	for _, product in Products do
		table.insert(list, product)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- Flat dark box with a coloured ring (the Figma windows are flat, not gradient panels).
local function box(props: { [string]: any }): Frame
	local frame = UI.new("Frame", {
		Name = props.Name or "Box",
		BackgroundColor3 = props.fill or V.Window,
		BackgroundTransparency = props.fillTransparency or 0,
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UI.corner(frame, props.radius or 20)
	local ring = UI.stroke(frame, props.ring or 5, props.color or V.Gold)
	ring.Name = "Ring"
	return frame
end

local function pricePill(
	parent: Instance,
	color: Color3,
	position: UDim2,
	anchor: Vector2
): (Frame, TextLabel, GuiObject)
	local pill = UI.new("Frame", {
		Name = "Price",
		BackgroundColor3 = V.Slot,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = position,
		AnchorPoint = anchor,
		Parent = parent,
	})
	UI.corner(pill, 10)
	local ring = UI.stroke(pill, 3, color)
	ring.Name = "Ring"
	UI.padding(pill, 0, 14, 0, 12)
	UI.list(pill, Enum.FillDirection.Horizontal, 6)
	local icon = UI.icon("goo", { Size = UDim2.fromOffset(24, 24), LayoutOrder = 1, Parent = pill })
	local label = UI.text({ Name = "Label", Text = "0", size = 22, LayoutOrder = 2, Parent = pill })
	return pill, label, icon
end

export type Window = { holder: GuiObject, onOpen: () -> () }

function ShopUI.build(parent: Instance, onClose: () -> ()): Window
	local holder = UI.new("Frame", {
		Name = "Shop",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1780, 760),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})

	---------------------------------------------------------------- GOO & PASSES side panel
	local side = box({ Name = "Passes", Size = UDim2.fromOffset(400, 760), Parent = holder })
	UI.icon("goo", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(32, 30), Parent = side })
	UI.text({
		Text = "Goo & Passes",
		font = "label",
		size = 24,
		Position = UDim2.fromOffset(78, 47),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = side,
	})
	local rows = UI.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 1, -110),
		Position = UDim2.fromOffset(24, 92),
		Parent = side,
	})
	UI.list(rows, Enum.FillDirection.Vertical, 18, Enum.HorizontalAlignment.Center).VerticalAlignment =
		Enum.VerticalAlignment.Top
	type Row = { product: Products.Product, price: TextLabel, button: TextButton }
	local productRows: { Row } = {}
	for _, product in sortedProducts() do
		local isPass = product.kind == "gamepass"
		local button = UI.new("TextButton", {
			Name = product.key,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = WHITE,
			Size = UDim2.new(1, 0, 0, 104),
			LayoutOrder = product.order,
			Parent = rows,
		})
		UI.corner(button, 14)
		UI.stroke(button, 4, V.Outline)
		UI.gradient(
			button,
			if isPass then Color3.fromHex("#B58BFF") else Color3.fromHex("#FFD95A"),
			if isPass then Color3.fromHex("#7B3FE4") else Color3.fromHex("#E8A21A")
		)
		local iconBox = UI.new("Frame", {
			Name = "IconBox",
			BackgroundColor3 = V.Slot,
			Size = UDim2.fromOffset(78, 78),
			Position = UDim2.new(0, 14, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = button,
		})
		UI.corner(iconBox, 12)
		local iconKey = if product.goo
			then "goo"
			elseif product.key == "DoubleGoo" then "star"
			elseif product.key == "ExtraCash" then "coin"
			else "trophy"
		UI.icon(iconKey, {
			Size = UDim2.fromOffset(54, 54),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = iconBox,
		})
		UI.text({
			Name = "Title",
			Text = if product.goo then `{product.goo} Goo` else product.displayName,
			size = 28,
			Position = UDim2.fromOffset(108, 18),
			Parent = button,
		})
		local pill = UI.new("Frame", {
			Name = "Robux",
			BackgroundColor3 = V.Slot,
			BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.fromOffset(108, 58),
			Parent = button,
		})
		UI.corner(pill, 8)
		UI.padding(pill, 0, 12, 0, 12)
		local price = UI.text({
			Name = "Label",
			Text = `R$ {product.priceRobux}`,
			font = "label",
			size = 16,
			Size = UDim2.new(0, 0, 1, 0),
			Parent = pill,
		})
		if product.badge then
			local tag = UI.new("Frame", {
				Name = "Tag",
				BackgroundColor3 = V.Slot,
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(6, -10),
				ZIndex = 3,
				Parent = button,
			})
			UI.corner(tag, 8)
			UI.padding(tag, 0, 8, 0, 8)
			UI.text({
				Text = product.badge,
				font = "label",
				size = 13,
				Size = UDim2.new(0, 0, 1, 0),
				ZIndex = 4,
				Parent = tag,
			})
		end
		local scale = Motion.scaleOf(button)
		button.MouseEnter:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1.03 })
		end)
		button.MouseLeave:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1 })
		end)
		button.Activated:Connect(function()
			Sound.play("click")
			Motion.punch(button, 0.94)
			local profile = Store.profile
			if isPass and profile and profile.passes[product.key] then
				Store.notified:Fire(`You already own {product.displayName}.`, "info")
				return
			end
			Monetization.promptPurchase(product.key, function()
				Store.notified:Fire(`Thanks! {product.displayName} granted.`, "success")
			end)
		end)
		table.insert(productRows, { product = product, price = price, button = button })
	end

	---------------------------------------------------------------- SHOP window
	local main = box({
		Name = "Window",
		Size = UDim2.fromOffset(1340, 760),
		Position = UDim2.fromOffset(440, 0),
		Parent = holder,
	})
	UI.icon("shop", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(36, 22), Parent = main })
	UI.text({
		Name = "Title",
		Text = "SHOP",
		size = 56,
		color = V.Gold,
		strokeThickness = 4,
		Position = UDim2.new(0, 108, 0, 50),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = main,
	})
	local gooPill = box({
		Name = "Balance",
		Size = UDim2.fromOffset(0, 62),
		Position = UDim2.new(1, -124, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		color = V.Gold,
		ring = 4,
		radius = 14,
		Parent = main,
	})
	gooPill.AutomaticSize = Enum.AutomaticSize.X
	UI.padding(gooPill, 0, 20, 0, 16)
	UI.list(gooPill, Enum.FillDirection.Horizontal, 10)
	UI.icon("goo", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 1, Parent = gooPill })
	local gooValue = UI.text({ Name = "Value", Text = "0", size = 34, LayoutOrder = 2, Parent = gooPill })
	UI.button({
		Name = "Close",
		icon = "close",
		style = "red",
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(1, -30, 0, 22),
		AnchorPoint = Vector2.new(1, 0),
		iconSize = 32,
		radius = 999,
		Parent = main,
	}, onClose)

	local inner = box({
		Name = "Inner",
		fill = V.WindowInner,
		color = Color3.fromHex("#3A3320"),
		ring = 2,
		radius = 16,
		Size = UDim2.new(1, -60, 1, -140),
		Position = UDim2.fromOffset(30, 112),
		Parent = main,
	})

	---------------------------------------------------------------- rarity cards
	local grid = UI.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(640, 520),
		Position = UDim2.fromOffset(30, 46),
		Parent = inner,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(180, 228),
		CellPadding = UDim2.fromOffset(20, 26),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	type Card = { button: TextButton, label: TextLabel, priceIcon: GuiObject, def: TowerData.TowerDef }
	local cards: { [string]: Card } = {}
	local selected: string? = nil -- tower the player clicked (nil = automatic featured pick)
	local shown: string? = nil -- tower currently in the featured card
	local select: (string) -> ()

	for _, def in sortedDefs() do
		local color = Theme.Rarity[def.rarity] or V.SlotRing
		local button = UI.new("TextButton", {
			Name = def.id,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = V.Window,
			LayoutOrder = def.order,
			Parent = grid,
		})
		UI.corner(button, 14)
		UI.stroke(button, 4, color).Name = "Ring"
		UI.text({
			Name = "Rarity",
			Text = def.rarity,
			font = "label",
			size = 16,
			color = color,
			Position = UDim2.new(0.5, 0, 0, 24),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = button,
		})
		local iconBox = UI.new("Frame", {
			Name = "IconBox",
			BackgroundColor3 = V.WindowInner,
			Size = UDim2.fromOffset(110, 110),
			Position = UDim2.new(0.5, 0, 0, 46),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = button,
		})
		UI.corner(iconBox, 12)
		UI.stroke(iconBox, 3, color)
		UI.icon(def.icon, {
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = iconBox,
		})
		local _, label, priceIcon = pricePill(button, color, UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1))
		local scale = Motion.scaleOf(button)
		button.MouseEnter:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1.05 })
		end)
		button.MouseLeave:Connect(function()
			Motion.tween(scale, 0.12, { Scale = 1 })
		end)
		button.Activated:Connect(function()
			Sound.play("click")
			select(def.id)
		end)
		cards[def.id] = { button = button, label = label, priceIcon = priceIcon, def = def }
	end

	---------------------------------------------------------------- featured tower
	local featured = box({
		Name = "Featured",
		fill = V.Window,
		color = V.Red,
		ring = 5,
		radius = 18,
		Size = UDim2.fromOffset(440, 540),
		Position = UDim2.new(1, -30, 0, 36),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inner,
	})
	local featuredTitle = UI.text({
		Name = "Heading",
		Text = "Featured Tower",
		font = "label",
		size = 24,
		color = V.Red,
		Position = UDim2.new(0.5, 0, 0, 38),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = featured,
	})
	local featuredHint = UI.text({
		Name = "Hint",
		Text = "Cheapest unlock you don't own yet",
		font = "label",
		size = 13,
		color = V.Muted,
		stroke = false,
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = featured,
	})
	local featuredBox = UI.new("Frame", {
		Name = "IconBox",
		BackgroundColor3 = V.WindowInner,
		Size = UDim2.fromOffset(200, 180),
		Position = UDim2.new(0.5, 0, 0, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = featured,
	})
	UI.corner(featuredBox, 14)
	local featuredRing = UI.stroke(featuredBox, 4, V.Red)
	local featuredIcon: GuiObject = UI.icon("frog", {
		Size = UDim2.fromOffset(140, 140),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = featuredBox,
	})
	local featuredName = UI.text({
		Name = "TowerName",
		Text = "",
		size = 44,
		color = Color3.fromHex("#FF6F82"),
		Position = UDim2.new(0.5, 0, 0, 316),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = featured,
	})
	local featuredRarity = UI.text({
		Name = "Rarity",
		Text = "",
		font = "label",
		size = 18,
		Position = UDim2.new(0.5, 0, 0, 358),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = featured,
	})
	local featuredDesc = UI.text({
		Name = "Description",
		Text = "",
		size = 17,
		color = Color3.fromHex("#FF9AA8"),
		stroke = false,
		TextWrapped = true,
		Size = UDim2.new(1, -60, 0, 52),
		Position = UDim2.new(0.5, 0, 0, 380),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = featured,
	})
	local buy = UI.button({
		Name = "Buy",
		Text = "0",
		icon = "goo",
		style = "red",
		Size = UDim2.new(1, -40, 0, 70),
		Position = UDim2.new(0.5, 0, 1, -22),
		AnchorPoint = Vector2.new(0.5, 1),
		textSize = 34,
		Parent = featured,
	}, function()
		local id = shown
		local profile = Store.profile
		if not id or not profile or profile.unlocked[id] then
			return
		end
		if profile.goo >= TowerData[id].unlockGoo then
			Remotes.get("UnlockTower"):FireServer(id)
		else
			Sound.play("error")
			Motion.shake(featured, 6, 3)
			Store.notified:Fire(`Need {TowerData[id].unlockGoo - profile.goo} more Goo`, "error")
		end
	end)

	local function showFeatured(id: string)
		shown = id
		local def = TowerData[id]
		local profile = Store.profile
		local owned = profile ~= nil and profile.unlocked[id] == true
		local color = Theme.Rarity[def.rarity] or V.SlotRing
		featuredIcon:Destroy()
		featuredIcon = UI.icon(def.icon, {
			Size = UDim2.fromOffset(140, 140),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = featuredBox,
		})
		UI.setText(featuredName, def.displayName)
		UI.setText(featuredRarity, def.rarity)
		featuredRarity.TextColor3 = color
		featuredRing.Color = color
		featuredDesc.Text = def.description
		UI.setText(featuredHint, if owned then "Already in your loadout" else "Unlock with Goo")
		UI.setText(featuredTitle, if selected == nil then "Featured Tower" else "Tower")
		if owned then
			UI.setButtonText(buy, "Owned")
			UI.setButtonStyle(buy, "gray")
		else
			UI.setButtonText(buy, tostring(def.unlockGoo))
			UI.setButtonStyle(buy, if profile and profile.goo >= def.unlockGoo then "red" else "gray")
		end
	end

	-- Cheapest tower you don't own yet (the Figma "featured" rule), else the first tower.
	local function featuredId(): string
		local profile = Store.profile
		local best: TowerData.TowerDef? = nil
		for _, def in sortedDefs() do
			local owned = profile ~= nil and profile.unlocked[def.id] == true
			if not owned and (best == nil or def.unlockGoo < (best :: TowerData.TowerDef).unlockGoo) then
				best = def
			end
		end
		return if best then best.id else sortedDefs()[1].id
	end

	function select(id: string)
		selected = id
		for cardId, card in cards do
			local ring = card.button:FindFirstChild("Ring")
			if ring and ring:IsA("UIStroke") then
				ring.Thickness = if cardId == id then 7 else 4
			end
		end
		showFeatured(id)
		Motion.punch(featured, 1.03)
	end

	local lastGoo: number? = nil
	local function refresh()
		local profile = Store.profile
		if not profile then
			return
		end
		Motion.countTo(gooValue, profile.goo, tostring)
		if lastGoo and lastGoo ~= profile.goo then
			Motion.punch(gooPill, 1.1)
		end
		lastGoo = profile.goo
		for id, card in cards do
			local owned = profile.unlocked[id] == true
			local wasOwned = card.button:GetAttribute("Owned")
			card.priceIcon.Visible = not owned
			UI.setText(card.label, if owned then "Owned" else tostring(card.def.unlockGoo))
			card.button:SetAttribute("Owned", owned)
			if owned and wasOwned == false then
				Motion.punch(card.button, 1.12)
				Sound.play("sparkle")
				if selected == id then
					selected = nil -- move the spotlight to the next tower
				end
			end
		end
		for _, row in productRows do
			if row.product.kind == "gamepass" then
				UI.setText(
					row.price,
					if profile.passes[row.product.key] then "Owned" else `R$ {row.product.priceRobux}`
				)
			end
		end
		showFeatured(selected or featuredId())
	end
	Store.profileChanged:Connect(refresh)
	refresh()

	return {
		holder = holder,
		onOpen = function()
			selected = nil -- reopen on the featured pick
			refresh()
		end,
	}
end

return ShopUI
