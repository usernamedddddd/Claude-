--!strict
-- Match HUD: lives, cash, round counter, tower hotbar, start/skip + fast-forward votes,
-- teammates, toasts, the touch "place / cancel" bar and the end-of-match results card.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local TowerData = require(Shared.Data.TowerData)
local Remotes = require(Shared.Net.Remotes)

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

local function statPill(parent: Instance, icon: string, order: number, color: Color3): TextLabel
	local pill =
		UI.panel({ Size = UDim2.fromScale(1, 1), color = color, LayoutOrder = order, Parent = parent, corner = 0.5 })
	UI.aspect(pill, 3, Enum.DominantAxis.Height)
	UI.icon(icon, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.04, 0.1), Parent = pill })
	return UI.text({
		Text = "",
		Size = UDim2.fromScale(0.62, 0.75),
		Position = UDim2.fromScale(0.33, 0.12),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = pill,
	})
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

function HUD.start()
	local gui = UI.screen("HUD", 1)

	-- Top-left: lives / cash / round
	local stats = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.6, 0.075),
		Position = UDim2.fromScale(0.01, 0.015),
		Parent = gui,
	})
	UI.list(stats, Enum.FillDirection.Horizontal, 0.01, Enum.HorizontalAlignment.Left)
	local livesText = statPill(stats, "heart", 1, C.Red)
	local cashText = statPill(stats, "coin", 2, C.Gold)
	local roundText = statPill(stats, "star", 3, C.Purple)

	-- Teammates (left)
	local team = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.22, 0.2),
		Position = UDim2.fromScale(0.01, 0.1),
		Parent = gui,
	})
	UI.list(team, Enum.FillDirection.Vertical, 0.04, Enum.HorizontalAlignment.Left).VerticalAlignment =
		Enum.VerticalAlignment.Top

	-- Top-right: start/skip and fast-forward
	local controls = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.3, 0.22),
		Position = UDim2.fromScale(0.99, 0.015),
		AnchorPoint = Vector2.new(1, 0),
		Parent = gui,
	})
	UI.list(controls, Enum.FillDirection.Vertical, 0.06, Enum.HorizontalAlignment.Right).VerticalAlignment =
		Enum.VerticalAlignment.Top
	local skipButton = UI.button(
		{ Text = "Start", Size = UDim2.fromScale(1, 0.45), color = C.Green, LayoutOrder = 1, Parent = controls },
		function()
			Remotes.get("VoteSkip"):FireServer()
		end
	)
	UI.aspect(skipButton, 3.4, Enum.DominantAxis.Height)
	local speedButton = UI.button(
		{ Text = "⏩ 1x", Size = UDim2.fromScale(1, 0.4), color = C.Blue, LayoutOrder = 2, Parent = controls },
		function()
			Remotes.get("VoteSpeed"):FireServer()
		end
	)
	UI.aspect(speedButton, 3.4, Enum.DominantAxis.Height)

	-- Bottom: hotbar
	local hotbar = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.7, 0.16),
		Position = UDim2.fromScale(0.5, 0.985),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = gui,
	})
	UI.list(hotbar, Enum.FillDirection.Horizontal, 0.012)
	local slots: { [string]: TextButton } = {}
	local hotkeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
	}
	for i, def in sortedTowers() do
		local function choose()
			if not isAllowed(def.id) then
				Sound.play("error")
				Store.notified:Fire("Unlock this tower in the lobby with Goo!", "info")
				return
			end
			if Placement.placingId() == def.id then
				Placement.cancel()
			else
				Placement.begin(def.id)
			end
		end
		local slot = UI.button(
			{ Size = UDim2.fromScale(1, 1), color = C.Panel, LayoutOrder = i, Name = def.id, Parent = hotbar },
			choose
		)
		UI.aspect(slot, 0.85, Enum.DominantAxis.Height)
		UI.icon(def.icon, {
			Size = UDim2.fromScale(0.62, 0.55),
			Position = UDim2.fromScale(0.5, 0.06),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = slot,
		})
		UI.text({
			Text = UI.formatCash(def.cost),
			Name = "Cost",
			Size = UDim2.fromScale(0.9, 0.26),
			Position = UDim2.fromScale(0.05, 0.66),
			color = C.Text,
			Parent = slot,
		})
		UI.text({
			Text = tostring(i),
			Size = UDim2.fromScale(0.22, 0.22),
			Position = UDim2.fromScale(0.04, 0.03),
			color = C.TextDark,
			stroke = false,
			Parent = slot,
		})
		local lock = UI.icon("lock", {
			Size = UDim2.fromScale(0.45, 0.45),
			Position = UDim2.fromScale(0.5, 0.35),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = slot,
		})
		lock.Name = "Lock"
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
	-- Gamepad: Y jumps focus to the hotbar.
	ContextActionService:BindAction("SlimeFocusHotbar", function(_, state)
		if state == Enum.UserInputState.Begin then
			GuiService.SelectedObject = if GuiService.SelectedObject then nil else slots.DartFrog
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonY)

	-- Touch / gamepad placement bar
	local placeBar = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.4, 0.09),
		Position = UDim2.fromScale(0.5, 0.8),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = gui,
	})
	UI.list(placeBar, Enum.FillDirection.Horizontal, 0.03)
	local placeButton = UI.button(
		{ Text = "✔ Place", Size = UDim2.fromScale(0.45, 1), color = C.Green, LayoutOrder = 1, Parent = placeBar },
		function()
			Placement.confirm()
		end
	)
	UI.button(
		{ Text = "✖ Cancel", Size = UDim2.fromScale(0.45, 1), color = C.Red, LayoutOrder = 2, Parent = placeBar },
		function()
			Placement.cancel()
		end
	)
	local placeHint =
		UI.text({ Text = "", Size = UDim2.fromScale(1, 0.6), Position = UDim2.fromScale(0, -0.7), Parent = placeBar })

	-- Toasts
	local toast = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.5, 0.06),
		Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	toast.Visible = false
	local toastToken = 0
	Store.notified:Connect(function(message, kind)
		toastToken += 1
		local token = toastToken
		toast.Text = message
		toast.TextColor3 = if kind == "error" then C.Red elseif kind == "success" then C.Green else C.Text
		toast.Visible = true
		if kind == "error" then
			Sound.play("error")
		end
		task.delay(2.2, function()
			if token == toastToken then
				toast.Visible = false
			end
		end)
	end)

	-- Results card
	local results = UI.panel({
		Size = UDim2.fromScale(0.42, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Name = "Results",
		Parent = gui,
	})
	UI.aspect(results, 1.3)
	local resultTitle = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.9, 0.25),
		Position = UDim2.fromScale(0.05, 0.05),
		Parent = results,
	})
	local resultBody = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.85, 0.45),
		Position = UDim2.fromScale(0.075, 0.32),
		Parent = results,
	})
	local resultFooter = UI.text({
		Text = "",
		Size = UDim2.fromScale(0.9, 0.12),
		Position = UDim2.fromScale(0.05, 0.82),
		Parent = results,
	})
	Remotes.get("MatchResult").OnClientEvent:Connect(function(result: { [string]: any })
		Placement.cancel()
		results.Visible = true
		resultTitle.Text = if result.won then "🏆 VICTORY! 🏆" else "💀 DEFEAT"
		resultTitle.TextColor3 = if result.won then C.Gold else C.Red
		resultBody.Text = `Reached round {result.round}\n+{result.goo} Goo   +{result.xp} XP`
		local seconds = tonumber(result.returnIn) or 20
		local studio = result.studio == true
		task.spawn(function()
			for s = seconds, 1, -1 do
				resultFooter.Text = if studio then `Restarting in {s}s (Studio)` else `Back to the lobby in {s}s`
				task.wait(1)
			end
			results.Visible = false
		end)
		results.Size = UDim2.fromScale(0.1, 0.1)
		TweenService:Create(results, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(0.42, 0.5),
		}):Play()
	end)

	-- Refreshers
	local teamRows: { Instance } = {}
	local function refreshMatch()
		local match = Store.match
		if not match then
			return
		end
		livesText.Text = tostring(match.lives)
		cashText.Text = UI.formatCash(Store.cash())
		roundText.Text = `Round {math.max(match.round, 1)}/{match.totalRounds}`

		local me = Store.me()
		local waiting = match.phase == "prep" or match.phase == "intermission"
		skipButton.Visible = waiting
		if waiting then
			local label = if match.phase == "prep" then "Start" else "Next round"
			local countdownText = if match.waitingForParty then "waiting for party" else `{match.countdown}s`
			UI.setButtonText(skipButton, `▶ {label} ({countdownText}) {match.skipVotes}/{match.playerCount}`)
			skipButton.BackgroundColor3 = if me and me.skip then C.Yellow else C.Green
		end
		UI.setButtonText(speedButton, `⏩ {match.speed}x  {match.speedVotes}/{match.playerCount}`)
		speedButton.BackgroundColor3 = if me and me.fast then C.Yellow else C.Blue

		for _, row in teamRows do
			row:Destroy()
		end
		table.clear(teamRows)
		if #match.players > 1 then
			for i, p in match.players do
				local row = UI.text({
					Text = `{p.name}: {UI.formatCash(p.cash)}`,
					Size = UDim2.fromScale(1, 0.2),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = i,
					Parent = team,
				})
				table.insert(teamRows, row)
			end
		end

		local cash = Store.cash()
		for id, slot in slots do
			local def = TowerData[id]
			local allowed = isAllowed(id)
			local lock = slot:FindFirstChild("Lock")
			if lock and lock:IsA("GuiObject") then
				lock.Visible = not allowed
			end
			slot.BackgroundColor3 = if not allowed
				then C.Gray
				elseif Placement.placingId() == id then C.Yellow
				elseif cash >= def.cost then C.Panel
				else Color3.fromRGB(255, 190, 200)
		end
	end
	Store.matchChanged:Connect(refreshMatch)
	Store.profileChanged:Connect(refreshMatch)

	local function refreshPlacement()
		local placing = Placement.isPlacing()
		local mode = Placement.inputMode()
		placeBar.Visible = placing and mode ~= "mouse"
		local ok, reason = Placement.status()
		placeButton.BackgroundColor3 = if ok then C.Green else C.Gray
		placeHint.Text = if not placing
			then ""
			elseif mode == "touch" then (if ok then "Tap the garden to aim, then Place" else reason or "")
			elseif mode == "gamepad" then (if ok then "Ⓐ Place   Ⓑ Cancel" else reason or "")
			else ""
		refreshMatch()
	end
	Placement.changed:Connect(refreshPlacement)
	Placement.inputModeChanged:Connect(refreshPlacement)

	-- Gamepad aim cursor
	local crosshair = UI.text({
		Text = "+",
		Size = UDim2.fromScale(0.05, 0.05),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = gui,
	})
	local function refreshCrosshair()
		crosshair.Visible = Placement.inputMode() == "gamepad"
	end
	Placement.inputModeChanged:Connect(refreshCrosshair)
	refreshCrosshair()
	refreshMatch()
end

return HUD
