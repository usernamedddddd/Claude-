--!strict
-- Match HUD, implemented from the Figma "Match HUD — Desktop" / "— Phone" frames:
-- stat pills + wave progress (top-left), team list, start/skip + 2x votes (top-right),
-- toasts (top-centre), the tower hotbar (bottom), the touch/gamepad place bar, the round
-- banner and the boss warning. Animations follow the Figma motion spec (see Motion.luau).

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
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local HUD = {}

local C = UI.Colors

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
		return "The BIG BOSS SLIME is here!"
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

	---------------------------------------------------------------- stats (top-left)
	local stats = UI.new("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(700, 70),
		Position = UDim2.fromOffset(32, 28),
		Parent = root,
	})
	UI.list(stats, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Left)
	local lives = UI.pill({ Name = "Lives", icon = "heart", width = 150, LayoutOrder = 1, Parent = stats })
	local cash = UI.pill({ Name = "Cash", icon = "coin", width = 210, LayoutOrder = 2, Parent = stats })
	local round = UI.pill({ Name = "Round", icon = "star", width = 250, LayoutOrder = 3, Parent = stats })

	local wave = UI.new("Frame", {
		Name = "Wave",
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromOffset(470, 34),
		Position = UDim2.fromOffset(32, 112),
		Visible = false,
		Parent = root,
	})
	UI.corner(wave, 999)
	UI.stroke(wave, 3)
	UI.list(wave, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	UI.padding(wave, 0, 16, 0, 16)
	UI.text({
		Text = "Wave",
		color = C.TextMuted,
		size = 16,
		Size = UDim2.fromOffset(44, 34),
		LayoutOrder = 1,
		Parent = wave,
		stroke = false,
	})
	local _, waveFill = UI.bar({ Size = UDim2.fromOffset(250, 14), LayoutOrder = 2, Parent = wave })
	local waveLabel = UI.text({
		Text = "",
		size = 16,
		Size = UDim2.fromOffset(130, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = wave,
		stroke = false,
	})

	---------------------------------------------------------------- team list
	local team = UI.new("Frame", {
		Name = "Team",
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = UDim2.fromOffset(32, 166),
		Visible = false,
		Parent = root,
	})
	UI.corner(team, 20)
	UI.stroke(team, 3)
	UI.padding(team, 12, 18, 14, 16)
	UI.list(team, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	UI.text({
		Text = "TEAM",
		color = C.TextMuted,
		size = 15,
		Size = UDim2.fromOffset(200, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		Parent = team,
		stroke = false,
	})

	---------------------------------------------------------------- controls (top-right)
	local controls = UI.new("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(400, 200),
		Position = UDim2.new(1, -32, 0, 28),
		AnchorPoint = Vector2.new(1, 0),
		Parent = root,
	})
	UI.list(controls, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Right).VerticalAlignment =
		Enum.VerticalAlignment.Top
	local skipButton = UI.button({
		Name = "StartButton",
		Text = "Start",
		icon = "play",
		color = C.Green,
		Size = UDim2.fromOffset(330, 66),
		LayoutOrder = 1,
		Parent = controls,
	}, function()
		Remotes.get("VoteSkip"):FireServer()
	end)
	local votesChip, votesLabel = UI.chip({ Name = "SkipVotes", Text = "", LayoutOrder = 2, Parent = controls })
	local speedButton = UI.button({
		Name = "SpeedButton",
		Text = "2× speed",
		icon = "fast",
		color = C.Blue,
		Size = UDim2.fromOffset(330, 66),
		LayoutOrder = 3,
		Parent = controls,
	}, function()
		Remotes.get("VoteSpeed"):FireServer()
	end)

	---------------------------------------------------------------- toast (top-centre)
	local toast = UI.new("Frame", {
		Name = "Toast",
		BackgroundColor3 = C.Gold,
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, -80),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	UI.corner(toast, 999)
	UI.stroke(toast, 4)
	UI.padding(toast, 6, 26, 8, 18)
	UI.list(toast, Enum.FillDirection.Horizontal, 12)
	local toastIcon = UI.icon("coin", { Size = UDim2.fromOffset(36, 36), LayoutOrder = 1, Parent = toast })
	local toastText = UI.text({
		Text = "",
		size = 26,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		color = C.TextDark,
		LayoutOrder = 2,
		Parent = toast,
	})
	local toastShown, toastHidden = UDim2.new(0.5, 0, 0, 30), UDim2.new(0.5, 0, 0, -80)
	local toastToken = 0
	local function showToast(message: string, kind: string)
		toastToken += 1
		local token = toastToken
		local fill = if kind == "error"
			then C.Red
			elseif kind == "success" then C.Green
			elseif kind == "info" then C.Panel
			else C.Gold
		toast.BackgroundColor3 = fill
		toastText.Text = message
		toastText.TextColor3 = UI.labelColorFor(fill)
		local stroke = toastText:FindFirstChildOfClass("UIStroke")
		if UI.labelColorFor(fill) == C.Text and not stroke then
			UI.stroke(toastText, 2)
		elseif stroke then
			stroke.Enabled = UI.labelColorFor(fill) == C.Text
		end
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

	---------------------------------------------------------------- round banner
	local banner = UI.new("Frame", {
		Name = "RoundBanner",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(760, 220),
		Position = UDim2.new(0.5, 0, 0, 260),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})
	local bannerCard = UI.surface({
		Name = "Card",
		Size = UDim2.fromOffset(640, 170),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		color = C.Purple,
		radius = 40,
		Parent = banner,
	})
	local bannerTitle = UI.text({
		Name = "Title",
		Text = "ROUND 1",
		size = 96,
		Size = UDim2.new(1, 0, 0, 110),
		Position = UDim2.fromOffset(0, 8),
		Parent = bannerCard.face,
		strokeThickness = 3,
	})
	local bannerSub = UI.text({
		Text = "",
		size = 26,
		color = C.Gold,
		Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.new(0, 20, 0, 118),
		Parent = bannerCard.face,
	})
	local bossChip = UI.chip({
		Name = "BossWarning",
		Text = "Next round: BIG BOSS SLIME!",
		color = C.Red,
		textSize = 24,
		height = 46,
		Position = UDim2.new(0.5, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = root,
	})

	local bannerToken = 0
	local function showBanner(roundNumber: number)
		bannerToken += 1
		local token = bannerToken
		bannerTitle.Text = `ROUND {roundNumber}`
		bannerSub.Text = describeRound(roundNumber)
		bannerCard.face.BackgroundColor3 = if isBossRound(roundNumber) then C.Red else C.Purple
		Motion.popIn(banner, 0.4, Motion.T.bannerIn)
		if isBossRound(roundNumber) then
			Sound.play("bossPop")
			task.delay(Motion.T.bannerIn, function()
				Motion.shake(banner, 10, 2)
			end)
		end
		task.delay(Motion.T.bannerIn + Motion.T.bannerHold, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end

	---------------------------------------------------------------- hotbar (bottom)
	local hotbar = UI.new("Frame", {
		Name = "Hotbar",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromOffset(0, 186),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -24),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	UI.corner(hotbar, 32)
	UI.padding(hotbar, 16, 18, 26, 18)
	UI.list(hotbar, Enum.FillDirection.Horizontal, 14)

	type Slot = {
		button: TextButton,
		face: Frame,
		cost: TextLabel,
		key: TextLabel,
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
		local button = UI.button({
			Name = def.id,
			color = C.Card,
			Size = UDim2.fromOffset(120, 144),
			LayoutOrder = i,
			radius = 24,
			Parent = hotbar,
		}, choose)
		local face = button:FindFirstChild("Face") :: Frame
		local content = face:FindFirstChild("Content") :: Frame
		content:Destroy() -- slots use their own vertical layout
		local key = UI.text({
			Text = tostring(i),
			Name = "Hotkey",
			size = 16,
			color = C.TextDark,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 6),
			Parent = face,
		})
		local icon = UI.icon(def.icon, {
			Size = UDim2.fromOffset(66, 66),
			Position = UDim2.new(0.5, 0, 0, 28),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = face,
		})
		local lock = UI.icon("lock", {
			Name = "Lock",
			Size = UDim2.fromOffset(66, 66),
			Position = UDim2.new(0.5, 0, 0, 28),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = face,
		})
		local cost = UI.text({
			Text = UI.formatCash(def.cost),
			Name = "Cost",
			size = 22,
			color = C.TextDark,
			Size = UDim2.new(1, -8, 0, 28),
			Position = UDim2.new(0, 4, 1, -36),
			Parent = face,
		})
		local slot: Slot = { button = button, face = face, cost = cost, key = key, icon = icon, lock = lock, def = def }
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

	-- Figma HotbarSlot states: Default / Selected / Too expensive / Locked
	local selectedId: string? = nil
	local function refreshSlots()
		local cashNow = Store.cash()
		for id, slot in slots do
			local allowed = isAllowed(id)
			local selected = Placement.placingId() == id
			local affordable = cashNow >= slot.def.cost
			slot.icon.Visible = allowed
			slot.lock.Visible = not allowed
			local textColor = C.TextDark
			if not allowed then
				slot.face.BackgroundColor3 = C.Disabled
				UI.setRing(slot.face, C.Ink, 4)
				slot.cost.Text = `{slot.def.unlockGoo} Goo`
				textColor = C.Text
			elseif selected then
				slot.face.BackgroundColor3 = C.Gold
				UI.setRing(slot.face, C.Ink, 6)
				slot.cost.Text = UI.formatCash(slot.def.cost)
			else
				slot.face.BackgroundColor3 = C.Card
				UI.setRing(slot.face, if affordable then C.Ink else C.Red, 4)
				slot.cost.Text = UI.formatCash(slot.def.cost)
			end
			slot.cost.TextColor3 = if allowed and not affordable and not selected then C.Red else textColor
			slot.key.TextColor3 = textColor
		end
		local nowSelected = Placement.placingId()
		if nowSelected ~= selectedId then
			-- lift the newly selected slot (Figma: lift 8 px + 1.08, 160 ms Back-Out)
			if selectedId and slots[selectedId] then
				Motion.tween(Motion.scaleOf(slots[selectedId].button), 0.12, { Scale = 1 })
			end
			if nowSelected and slots[nowSelected] then
				local s = Motion.scaleOf(slots[nowSelected].button)
				s.Scale = 1
				if not Motion.reduced() then
					Motion.tween(s, 0.16, { Scale = 1.08 }, Enum.EasingStyle.Back)
				end
			end
			selectedId = nowSelected
		end
	end

	---------------------------------------------------------------- touch / gamepad place bar
	local placeBar = UI.new("Frame", {
		Name = "PlaceBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(440, 130),
		Position = UDim2.new(0.5, 0, 1, -236),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	local hint = UI.chip({
		Name = "Hint",
		Text = "",
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = placeBar,
	})
	local placeButton = UI.button({
		Name = "Place",
		Text = "Place",
		icon = "check",
		color = C.Purple,
		Size = UDim2.fromOffset(200, 66),
		Position = UDim2.new(0, 10, 1, -70),
		Parent = placeBar,
	}, function()
		Placement.confirm()
	end)
	UI.button({
		Name = "Cancel",
		Text = "Cancel",
		icon = "close",
		color = C.Red,
		Size = UDim2.fromOffset(200, 66),
		Position = UDim2.new(1, -10, 1, -70),
		AnchorPoint = Vector2.new(1, 0),
		Parent = placeBar,
	}, function()
		Placement.cancel()
	end)
	local hintLabel = hint:FindFirstChild("Label") :: TextLabel

	-- Gamepad aim cursor
	local crosshair = UI.text({
		Text = "+",
		size = 48,
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})

	---------------------------------------------------------------- state → UI
	local teamRows: { Instance } = {}
	local lastLives, lastCash, lastRound, lastPhase = -1, -1, -1, ""
	local stopCountdownPulse: (() -> ())? = nil
	local stopLowLivesPulse: (() -> ())? = nil

	local function refreshMatch()
		local match = Store.match
		if not match then
			return
		end
		local me = Store.me()

		-- Lives: count + red flash/shake when lost, heartbeat when low.
		Motion.countTo(lives.value, match.lives, tostring)
		if lastLives >= 0 and match.lives < lastLives then
			Motion.shake(lives.holder, 4, 2)
			lives.face.BackgroundColor3 = C.Red
			task.delay(0.25, function()
				lives.face.BackgroundColor3 = C.Panel
			end)
		end
		if match.lives < 25 and match.lives > 0 and not stopLowLivesPulse then
			stopLowLivesPulse = Motion.pulse(lives.bubble, 1.15, 0.6)
		elseif match.lives >= 25 and stopLowLivesPulse then
			stopLowLivesPulse()
			stopLowLivesPulse = nil
		end
		lastLives = match.lives

		local cashNow = Store.cash()
		Motion.countTo(cash.value, cashNow, UI.formatCash)
		if lastCash >= 0 and cashNow > lastCash + 50 then
			Motion.punch(cash.holder)
		end
		lastCash = cashNow

		round.value.Text = `Round {math.max(match.round, 1)}/{match.totalRounds}`
		if match.round ~= lastRound then
			if match.round > 0 and lastRound >= 0 then
				Motion.punch(round.holder)
				showBanner(match.round)
			end
		end
		-- Round bonus toast when a wave ends.
		if lastPhase == "wave" and match.phase == "intermission" then
			showToast(`Round bonus +${Config.ROUND_BONUS_BASE + match.round}!`, "cash")
			Sound.play("cash")
		end
		lastRound = match.round
		lastPhase = match.phase

		-- Wave progress
		wave.Visible = match.phase == "wave"
		local progress = match.waveProgress or 0
		Motion.tween(waveFill, 0.25, { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) })
		waveLabel.Text = `{match.slimesLeft or 0} slimes left`

		-- Start / next round + votes
		local waiting = match.phase == "prep" or match.phase == "intermission"
		skipButton.Visible = waiting
		votesChip.Visible = waiting and match.playerCount > 1
		if waiting then
			local label = if match.phase == "prep" then "Start" else "Next round"
			local countdownText = if match.waitingForParty then "waiting…" else `{match.countdown}s`
			UI.setButtonText(skipButton, `{label} · {countdownText}`)
			UI.setButtonColor(skipButton, if me and me.skip then C.Gold else C.Green)
			local need = math.floor(match.playerCount / 2) + 1
			local before = votesLabel.Text
			votesLabel.Text = `Skip votes {match.skipVotes}/{match.playerCount} · need {need}`
			if before ~= votesLabel.Text and before ~= "" then
				Motion.punch(votesChip, 1.15)
			end
			if match.countdown <= 3 and not match.waitingForParty then
				if not stopCountdownPulse then
					stopCountdownPulse = Motion.pulse(skipButton, 1.06, 1)
				end
			elseif stopCountdownPulse then
				stopCountdownPulse()
				stopCountdownPulse = nil
			end
		elseif stopCountdownPulse then
			stopCountdownPulse()
			stopCountdownPulse = nil
		end
		local speedText = if match.playerCount > 1
			then `{match.speed}× speed · {match.speedVotes}/{match.playerCount}`
			else `{match.speed}× speed`
		UI.setButtonText(speedButton, speedText)
		UI.setButtonColor(speedButton, if me and me.fast then C.Gold else C.Blue)

		-- Bosses: warn during the intermission before a boss round.
		bossChip.Visible = waiting and isBossRound(match.round + 1)

		-- Team list (co-op only)
		for _, row in teamRows do
			row:Destroy()
		end
		table.clear(teamRows)
		team.Visible = #match.players > 1
		if team.Visible then
			for i, p in match.players do
				local row = UI.new("Frame", {
					Name = "Row",
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(0, 28),
					AutomaticSize = Enum.AutomaticSize.X,
					LayoutOrder = i,
					Parent = team,
				})
				UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
				local isMe = me ~= nil and p.userId == me.userId
				local dot = UI.new("Frame", {
					BackgroundColor3 = if isMe then C.Lime else C.Cyan,
					Size = UDim2.fromOffset(12, 12),
					LayoutOrder = 1,
					Parent = row,
				})
				UI.corner(dot, 999)
				UI.text({
					Text = if isMe then "You" else p.name,
					size = 20,
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					TextWrapped = false,
					LayoutOrder = 2,
					Parent = row,
				})
				UI.text({
					Text = UI.formatCash(p.cash),
					size = 20,
					color = C.Gold,
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					TextWrapped = false,
					LayoutOrder = 3,
					Parent = row,
				})
				table.insert(teamRows, row)
			end
		end
		refreshSlots()
	end
	Store.matchChanged:Connect(refreshMatch)
	Store.profileChanged:Connect(refreshMatch)

	local function refreshPlacement()
		local placing = Placement.isPlacing()
		local mode = Placement.inputMode()
		placeBar.Visible = placing and mode ~= "mouse"
		local ok, reason = Placement.status()
		UI.setButtonColor(placeButton, if ok then C.Purple else C.Disabled)
		hintLabel.Text = if not placing
			then ""
			elseif mode == "touch" then (if ok then "Tap the garden to aim, then Place" else reason or "")
			elseif mode == "gamepad" then (if ok then "Ⓐ Place   Ⓑ Cancel" else reason or "")
			else ""
		crosshair.Visible = mode == "gamepad"
		refreshSlots()
	end
	Placement.changed:Connect(refreshPlacement)
	Placement.inputModeChanged:Connect(refreshPlacement)
	refreshPlacement()
	refreshMatch()
end

return HUD
