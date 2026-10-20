--!strict
-- Match HUD from the Figma "Match HUD v2" frame (reference style): outlined lives + cash on
-- the left, WAVE counter + progress top-centre, Skip / 2x / Settings square tiles top-right
-- with vote badges, the numbered loadout hotbar at the bottom, toasts, the round banner, the
-- boss warning and the touch/gamepad place bar. Motion follows the Figma motion spec.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Rounds = require(Shared.Data.Rounds)
local SlimeData = require(Shared.Data.SlimeData)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

local Motion = require(script.Parent.Motion)
local Placement = require(script.Parent.Placement)
local SettingsPanel = require(script.Parent.SettingsPanel)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local HUD = {}

local V = UI.V2

local function sortedTowers(): { TowerData.TowerDef }
	local list = {}
	for _, def in TowerData do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

local function isAllowed(towerId: string): boolean
	if RunService:IsStudio() and Config.STUDIO_UNLOCK_ALL then
		return true
	end
	local profile = Store.profile
	if not profile then
		return TowerData[towerId].unlockGoo == 0
	end
	return profile.unlocked[towerId] == true
end

-- "Yellow + Pink slimes incoming!" from the round data.
local function describeRound(round: number): string
	local groups = Rounds[round]
	if not groups then
		return ""
	end
	local names, seen, boss, camo = {}, {}, false, false
	for _, g in groups do
		if g.slimeType == "Boss" then
			boss = true
		elseif not seen[g.slimeType] then
			seen[g.slimeType] = true
			table.insert(names, g.slimeType)
		end
		camo = camo or g.camo == true
	end
	if boss then
		return "The Big Boss Slime is here!"
	end
	local text = table.concat(names, " + ") .. " slimes incoming!"
	return if camo then text .. " Some are camo!" else text
end

local function isBossRound(round: number): boolean
	local groups = Rounds[round]
	if not groups then
		return false
	end
	for _, g in groups do
		if SlimeData[g.slimeType] and SlimeData[g.slimeType].isBoss then
			return true
		end
	end
	return false
end

function HUD.start()
	local gui = UI.screen("HUD", 1)
	local root = UI.root(gui)

	---------------------------------------------------------------- resources (left)
	local resources = UI.new("Frame", {
		Name = "Resources",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(320, 150),
		Position = UDim2.fromOffset(40, 120),
		Parent = root,
	})
	UI.list(resources, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left).VerticalAlignment =
		Enum.VerticalAlignment.Top
	local livesFrame, livesValue =
		UI.currency({ Name = "Lives", icon = "heart", color = V.LivesText, LayoutOrder = 1, Parent = resources })
	local cashFrame, cashValue =
		UI.currency({ Name = "Cash", icon = "coin", color = V.CoinText, LayoutOrder = 2, Parent = resources })

	---------------------------------------------------------------- wave (top-centre)
	local wave = UI.new("Frame", {
		Name = "Wave",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(420, 110),
		Position = UDim2.new(0.5, 0, 0, 104),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	local waveTitle = UI.text({
		Name = "Title",
		Text = "Wave 1/40",
		font = "label",
		size = 40,
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = wave,
	})
	local waveBar, waveFill = UI.bar({
		Name = "Progress",
		Size = UDim2.fromOffset(360, 18),
		Position = UDim2.fromOffset(30, 54),
		Parent = wave,
	})
	local waveLeft = UI.text({
		Name = "Left",
		Text = "",
		font = "label",
		size = 14,
		Position = UDim2.new(0.5, 0, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = wave,
	})

	---------------------------------------------------------------- controls (top-right)
	local controls = UI.new("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(420, 130),
		Position = UDim2.new(1, -40, 0, 24),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
	})
	UI.list(controls, Enum.FillDirection.Horizontal, 22, Enum.HorizontalAlignment.Right).VerticalAlignment =
		Enum.VerticalAlignment.Top
	local skip = UI.squareTile({
		Name = "StartButton",
		icon = "skip",
		Text = "Start",
		accent = V.Green,
		badge = "",
		LayoutOrder = 1,
		Parent = controls,
	}, function()
		Remotes.get("VoteSkip"):FireServer()
	end)
	local speed = UI.squareTile({
		Name = "SpeedButton",
		icon = "fast",
		Text = "2x Speed",
		accent = V.Blue,
		badge = "",
		LayoutOrder = 2,
		Parent = controls,
	}, function()
		Remotes.get("VoteSpeed"):FireServer()
	end)
	UI.squareTile({
		Name = "SettingsButton",
		icon = "settings",
		Text = "Settings",
		accent = V.Blue,
		LayoutOrder = 3,
		Parent = controls,
	}, function()
		SettingsPanel.toggle(root)
	end)

	---------------------------------------------------------------- toast (under the wave counter)
	local toastShown, toastHidden = UDim2.new(0.5, 0, 0, 226), UDim2.new(0.5, 0, 0, -80)
	local toast, toastLabel = UI.chip({
		Name = "Toast",
		Text = "",
		icon = "coin",
		height = 54,
		textSize = 22,
		color = V.CoinText,
		Position = toastHidden,
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local toastIcon = toast:FindFirstChild("Icon") :: GuiObject
	local toastStroke = toast:FindFirstChildOfClass("UIStroke") :: UIStroke
	local toastToken = 0
	local function showToast(message: string, kind: string)
		toastToken += 1
		local token = toastToken
		local ring = if kind == "error"
			then V.Red
			elseif kind == "success" then V.Green
			elseif kind == "info" then V.Blue
			else V.Gold
		toastStroke.Color = ring
		toastLabel.TextColor3 = if kind == "cash" then V.CoinText else Color3.new(1, 1, 1)
		UI.setText(toastLabel, message)
		toastIcon.Visible = kind == "cash"
		if kind == "error" then
			Sound.play("error")
		end
		Motion.slide(toast, toastHidden, toastShown, true)
		task.delay(Motion.T.toastHold, function()
			if token == toastToken then
				Motion.slide(toast, toastHidden, toastShown, false)
			end
		end)
	end
	Store.notified:Connect(function(message, kind)
		showToast(message, kind)
	end)

	---------------------------------------------------------------- round banner + boss warning
	local banner = UI.panel({
		Name = "RoundBanner",
		Size = UDim2.fromOffset(680, 180),
		Position = UDim2.new(0.5, 0, 0, 300),
		AnchorPoint = Vector2.new(0.5, 0),
		accent = V.Gold,
		strokeWidth = 6,
		radius = 28,
		Visible = false,
		Parent = root,
	})
	local bannerTitle = UI.text({
		Name = "Title",
		Text = "Round 1",
		font = "label",
		size = 88,
		Position = UDim2.new(0.5, 0, 0, 18),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = banner.face,
	})
	local bannerSub = UI.text({
		Name = "Subtitle",
		Text = "",
		font = "label",
		size = 22,
		color = V.Gold,
		Position = UDim2.new(0.5, 0, 0, 122),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = banner.face,
	})
	local bossChip = UI.chip({
		Name = "BossWarning",
		Text = "Next round: Big Boss Slime!",
		icon = "skull",
		ring = V.Red,
		height = 50,
		textSize = 20,
		Position = UDim2.new(0.5, 0, 0, 226),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})

	local bannerToken = 0
	local function showBanner(roundNumber: number)
		bannerToken += 1
		local token = bannerToken
		local boss = isBossRound(roundNumber)
		UI.setText(bannerTitle, `Round {roundNumber}`)
		UI.setText(bannerSub, describeRound(roundNumber))
		banner.stroke.Color = if boss then V.Red else V.Gold
		bannerSub.TextColor3 = if boss then V.LivesText else V.Gold
		Motion.popIn(banner.holder, 0.4, Motion.T.bannerIn)
		if boss then
			Sound.play("bossPop")
			task.delay(Motion.T.bannerIn, function()
				Motion.shake(banner.holder, 10, 2)
			end)
		end
		task.delay(Motion.T.bannerIn + Motion.T.bannerHold, function()
			if token == bannerToken then
				banner.holder.Visible = false
			end
		end)
	end

	---------------------------------------------------------------- loadout hotbar (bottom)
	local hotbar = UI.new("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 112),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -28),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UI.list(hotbar, Enum.FillDirection.Horizontal, 14)

	type Slot = {
		button: TextButton,
		ring: UIStroke,
		cost: TextLabel,
		icon: GuiObject,
		lock: GuiObject,
		def: TowerData.TowerDef,
	}
	local slots: { [string]: Slot } = {}
	local hotkeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
	}
	for i, def in sortedTowers() do
		local slotRef: Slot? = nil
		local function choose()
			if not isAllowed(def.id) then
				Sound.play("error")
				if slotRef then
					Motion.shake(slotRef.button, 6, 3)
				end
				Store.notified:Fire("Unlock this tower in the lobby with Goo!", "info")
				return
			end
			if Placement.placingId() == def.id then
				Placement.cancel()
			else
				Placement.begin(def.id)
			end
		end
		-- Figma LoadoutSlot: translucent dark square, light ring, white number badge, cost.
		local button = UI.new("TextButton", {
			Name = def.id,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = V.Slot,
			BackgroundTransparency = V.SlotTransparency,
			Size = UDim2.fromOffset(110, 110),
			LayoutOrder = i,
			Selectable = true,
			Parent = hotbar,
		})
		UI.corner(button, 14)
		local ring = UI.stroke(button, 3, V.SlotRing)
		local icon = UI.icon(def.icon, {
			Size = UDim2.fromOffset(66, 66),
			Position = UDim2.new(0.5, 0, 0, 10),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = button,
		})
		local lock = UI.icon("lock", {
			Name = "Lock",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(0.5, 0, 0, 12),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = button,
		})
		local key = UI.new("Frame", {
			Name = "Key",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(6, 6),
			Parent = button,
		})
		UI.corner(key, 7)
		UI.stroke(key, 2)
		UI.text({
			Text = tostring(i),
			Name = "Hotkey",
			font = "label",
			size = 18,
			color = Color3.new(0, 0, 0),
			stroke = false,
			Size = UDim2.fromScale(1, 1),
			Parent = key,
		})
		local cost = UI.text({
			Name = "Cost",
			Text = UI.formatCash(def.cost),
			size = 20,
			color = V.CoinText,
			Position = UDim2.new(0.5, 0, 1, -16),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = button,
		})
		local scale = Motion.scaleOf(button)
		button.MouseButton1Down:Connect(function()
			Motion.tween(scale, Motion.T.press, { Scale = 0.93 })
		end)
		button.MouseButton1Up:Connect(function()
			Motion.tween(scale, Motion.T.release, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		button.Activated:Connect(function()
			Sound.play("click")
			choose()
		end)
		local slot: Slot = { button = button, ring = ring, cost = cost, icon = icon, lock = lock, def = def }
		slotRef = slot
		slots[def.id] = slot
		if hotkeys[i] then
			ContextActionService:BindAction(`SlimeHotbar{i}`, function(_, state)
				if state == Enum.UserInputState.Begin then
					choose()
				end
				return Enum.ContextActionResult.Pass
			end, false, hotkeys[i])
		end
	end
	ContextActionService:BindAction("SlimeFocusHotbar", function(_, state)
		if state == Enum.UserInputState.Begin then
			GuiService.SelectedObject = if GuiService.SelectedObject then nil else slots.DartFrog.button
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonY)

	-- Figma LoadoutSlot states: Default / Selected / Too expensive / Locked
	local selectedId: string? = nil
	local function refreshSlots()
		local cashNow = Store.cash()
		for id, slot in slots do
			local allowed = isAllowed(id)
			local selected = Placement.placingId() == id
			local affordable = cashNow >= slot.def.cost
			slot.icon.Visible = allowed
			slot.lock.Visible = not allowed
			if not allowed then
				slot.ring.Color = Color3.fromHex("#6E6680")
				slot.ring.Thickness = 3
				UI.setText(slot.cost, `{slot.def.unlockGoo} Goo`)
				slot.cost.TextColor3 = V.Muted
			else
				slot.ring.Color = if selected then V.Gold else V.SlotRing
				slot.ring.Thickness = if selected then 6 else 3
				UI.setText(slot.cost, UI.formatCash(slot.def.cost))
				slot.cost.TextColor3 = if affordable or selected then V.CoinText else V.LivesText
			end
		end
		local nowSelected = Placement.placingId()
		if nowSelected ~= selectedId then
			if selectedId and slots[selectedId] then
				Motion.tween(Motion.scaleOf(slots[selectedId].button), 0.12, { Scale = 1 })
			end
			if nowSelected and slots[nowSelected] and not Motion.reduced() then
				Motion.tween(Motion.scaleOf(slots[nowSelected].button), 0.16, { Scale = 1.08 }, Enum.EasingStyle.Back)
			end
			selectedId = nowSelected
		end
	end

	---------------------------------------------------------------- touch / gamepad place bar
	local placeBar = UI.new("Frame", {
		Name = "PlaceBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(480, 130),
		Position = UDim2.new(0.5, 0, 1, -160),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	local _hint, hintLabel = UI.chip({
		Name = "Hint",
		Text = "",
		ring = V.Purple,
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = placeBar,
	})
	local placeButton = UI.button({
		Name = "Place",
		Text = "Place",
		icon = "check",
		style = "green",
		Size = UDim2.fromOffset(220, 68),
		Position = UDim2.new(0, 10, 1, -72),
		Parent = placeBar,
	}, function()
		Placement.confirm()
	end)
	UI.button({
		Name = "Cancel",
		Text = "Cancel",
		icon = "close",
		style = "red",
		Size = UDim2.fromOffset(220, 68),
		Position = UDim2.new(1, -10, 1, -72),
		AnchorPoint = Vector2.new(1, 0),
		Parent = placeBar,
	}, function()
		Placement.cancel()
	end)
	local crosshair = UI.text({
		Text = "+",
		size = 56,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})

	---------------------------------------------------------------- state → UI
	local lastLives, lastCash, lastRound, lastPhase = -1, -1, -1, ""
	local stopCountdownPulse: (() -> ())? = nil
	local stopLowLivesPulse: (() -> ())? = nil
	local skipRing = skip.face:FindFirstChildOfClass("UIStroke") :: UIStroke
	local speedRing = speed.face:FindFirstChildOfClass("UIStroke") :: UIStroke

	local function refreshMatch()
		local match = Store.match
		if not match then
			return
		end
		local me = Store.me()

		Motion.countTo(livesValue, match.lives, tostring)
		if lastLives >= 0 and match.lives < lastLives then
			Motion.shake(livesFrame, 5, 2)
			livesValue.TextColor3 = V.Red
			task.delay(0.25, function()
				livesValue.TextColor3 = V.LivesText
			end)
		end
		if match.lives < 25 and match.lives > 0 and not stopLowLivesPulse then
			stopLowLivesPulse = Motion.pulse(livesFrame, 1.12, 0.6)
		elseif match.lives >= 25 and stopLowLivesPulse then
			stopLowLivesPulse()
			stopLowLivesPulse = nil
		end
		lastLives = match.lives

		local cashNow = Store.cash()
		Motion.countTo(cashValue, cashNow, UI.formatCash)
		if lastCash >= 0 and cashNow > lastCash + 50 then
			Motion.punch(cashFrame)
		end
		lastCash = cashNow

		UI.setText(waveTitle, `Wave {math.max(match.round, 1)}/{match.totalRounds}`)
		if match.round ~= lastRound and match.round > 0 and lastRound >= 0 then
			Motion.punch(waveTitle, 1.15)
			showBanner(match.round)
		end
		if lastPhase == "wave" and match.phase == "intermission" then
			showToast(`Round bonus +${Config.ROUND_BONUS_BASE + match.round}!`, "cash")
			Sound.play("cash")
		end
		lastRound = match.round
		lastPhase = match.phase

		local inWave = match.phase == "wave"
		waveBar.Visible = inWave
		waveLeft.Visible = inWave
		Motion.tween(waveFill, 0.25, { Size = UDim2.fromScale(math.clamp(match.waveProgress or 0, 0, 1), 1) })
		UI.setText(waveLeft, `{match.slimesLeft or 0} slimes left`)

		local waiting = match.phase == "prep" or match.phase == "intermission"
		skip.button.Visible = waiting
		if waiting then
			local countdownText = if match.waitingForParty then "…" else `{match.countdown}s`
			UI.setText(skip.label, (if match.phase == "prep" then "Start " else "Skip ") .. countdownText)
			skip.badge.Visible = match.playerCount > 1
			local before = skip.badgeLabel.Text
			UI.setText(skip.badgeLabel, `{match.skipVotes}/{match.playerCount}`)
			if before ~= skip.badgeLabel.Text and before ~= "" then
				Motion.punch(skip.badge, 1.25)
			end
			if match.countdown <= 3 and not match.waitingForParty then
				if not stopCountdownPulse then
					stopCountdownPulse = Motion.pulse(skip.button, 1.06, 1)
				end
			elseif stopCountdownPulse then
				stopCountdownPulse()
				stopCountdownPulse = nil
			end
		elseif stopCountdownPulse then
			stopCountdownPulse()
			stopCountdownPulse = nil
		end
		skipRing.Color = if me and me.skip then V.Gold else V.Green
		UI.setText(speed.label, `{match.speed}x Speed`)
		speed.badge.Visible = match.playerCount > 1
		UI.setText(speed.badgeLabel, `{match.speedVotes}/{match.playerCount}`)
		speedRing.Color = if me and me.fast then V.Gold else V.Blue

		bossChip.Visible = waiting and isBossRound(match.round + 1)
		refreshSlots()
	end
	Store.matchChanged:Connect(refreshMatch)
	Store.profileChanged:Connect(refreshMatch)

	local function refreshPlacement()
		local placing = Placement.isPlacing()
		local mode = Placement.inputMode()
		placeBar.Visible = placing and mode ~= "mouse"
		local ok, reason = Placement.status()
		UI.setButtonStyle(placeButton, if ok then "green" else "gray")
		UI.setText(
			hintLabel,
			if not placing
				then ""
				elseif mode == "touch" then (if ok then "Tap the garden to aim, then Place" else reason or "")
				elseif mode == "gamepad" then (if ok then "A: Place   B: Cancel" else reason or "")
				else ""
		)
		crosshair.Visible = mode == "gamepad"
		refreshSlots()
	end
	Placement.changed:Connect(refreshPlacement)
	Placement.inputModeChanged:Connect(refreshPlacement)
	refreshPlacement()
	refreshMatch()
end

return HUD
