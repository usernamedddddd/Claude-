--!strict
-- End-of-match card from the Figma "Results v2" frame: dark scrim, gold-bordered panel that
-- pops in, trophy/skull, outlined VICTORY!/DEFEAT title, rewards that stagger in and count up
-- (round, Goo, XP), the level bar filling, and a green lobby button with a countdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local Remotes = require(Shared.Net.Remotes)

local Motion = require(script.Parent.Motion)
local Placement = require(script.Parent.Placement)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local Results = {}

local V = UI.V2

function Results.start()
	local gui = UI.screen("Results", 5)
	local root = UI.root(gui)
	local scrim = UI.new("Frame", {
		Name = "Scrim",
		BackgroundColor3 = V.Slot,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})

	local card = UI.panel({
		Name = "Results",
		Size = UDim2.fromOffset(820, 640),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		accent = V.Gold,
		strokeWidth = 6,
		radius = 28,
		Visible = false,
		Parent = root,
	})
	local face = card.face
	local badgeHolder = UI.new("Frame", {
		Name = "Badge",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(140, 140),
		Position = UDim2.new(0.5, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = face,
	})
	local badgeIcon = UI.icon("trophy", { Size = UDim2.fromScale(1, 1), Parent = badgeHolder })
	local title = UI.text({
		Name = "Title",
		Text = "VICTORY!",
		size = 96,
		color = V.Gold,
		strokeThickness = 6,
		Position = UDim2.new(0.5, 0, 0, 168),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = face,
	})
	local subtitle = UI.text({
		Text = "",
		font = "label",
		size = 18,
		Position = UDim2.new(0.5, 0, 0, 286),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = face,
	})

	local rewards = UI.new("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -80, 0, 64),
		Position = UDim2.new(0, 40, 0, 330),
		Parent = face,
	})
	UI.list(rewards, Enum.FillDirection.Horizontal, 48)
	local roundFrame, roundValue =
		UI.currency({ Name = "Round", icon = "star", color = Color3.new(1, 1, 1), LayoutOrder = 1, Parent = rewards })
	local gooFrame, gooValue =
		UI.currency({ Name = "Goo", icon = "goo", color = V.GooText, LayoutOrder = 2, Parent = rewards })
	local xpFrame = UI.new("Frame", {
		Name = "XP",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = rewards,
	})
	local xpValue = UI.text({
		Name = "Value",
		Text = "+0 XP",
		size = 40,
		color = V.Xp,
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = xpFrame,
	})

	local xpBar = UI.xpBar({ Position = UDim2.new(0.5, 0, 0, 418), AnchorPoint = Vector2.new(0.5, 0), Parent = face })

	local footer = UI.button({
		Name = "Footer",
		Text = "Lobby",
		style = "green",
		Size = UDim2.fromOffset(380, 80),
		Position = UDim2.new(0.5, 0, 1, -110),
		AnchorPoint = Vector2.new(0.5, 0),
		textSize = 32,
		strokeWidth = 6,
		Parent = face,
	}, function() end)
	footer.Active = false

	Remotes.get("MatchResult").OnClientEvent:Connect(function(result: { [string]: any })
		Placement.cancel()
		local won = result.won == true
		local roundReached = tonumber(result.round) or 0
		card.stroke.Color = if won then V.Gold else V.Red
		badgeIcon:Destroy()
		badgeIcon = UI.icon(if won then "trophy" else "skull", { Size = UDim2.fromScale(1, 1), Parent = badgeHolder })
		UI.setText(title, if won then "VICTORY!" else "DEFEAT")
		title.TextColor3 = if won then V.Gold else V.Red
		UI.setText(
			subtitle,
			if won
				then `You held the Candy Garden through all {Config.TOTAL_ROUNDS} rounds`
				else `The slimes broke through on round {roundReached}`
		)

		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.tween(scrim, 0.3, { BackgroundTransparency = 0.3 })
		Motion.popIn(card.holder, 0.6, Motion.T.resultsCard)
		Sound.play(if won then "sparkle" else "leak")

		type Reward = { frame: GuiObject, value: TextLabel, target: number, format: (number) -> string }
		local list: { Reward } = {
			{
				frame = roundFrame,
				value = roundValue,
				target = roundReached,
				format = function(n: number): string
					return `{n}/{Config.TOTAL_ROUNDS}`
				end,
			},
			{
				frame = gooFrame,
				value = gooValue,
				target = tonumber(result.goo) or 0,
				format = function(n: number): string
					return `+{n}`
				end,
			},
			{
				frame = xpFrame,
				value = xpValue,
				target = tonumber(result.xp) or 0,
				format = function(n: number): string
					return `+{n} XP`
				end,
			},
		}
		for i, reward in list do
			reward.value.Text = reward.format(0)
			Motion.countTo(reward.value, 0, reward.format)
			task.delay(Motion.T.resultsCard + (i - 1) * Motion.T.resultsStagger, function()
				Motion.popIn(reward.frame, 0.7, 0.3)
				Motion.countTo(reward.value, reward.target, reward.format, 0.6)
			end)
		end

		xpBar.fill.Size = UDim2.fromScale(0, 1)
		task.delay(Motion.T.resultsCard + 0.4, function()
			local profile = Store.profile
			if not profile then
				return
			end
			local inLevel = profile.xp % Config.XP_PER_LEVEL
			UI.setText(xpBar.level, tostring(profile.level))
			UI.setText(xpBar.nextLevel, tostring(profile.level + 1))
			UI.setText(xpBar.exp, `{inLevel} Exp`)
			UI.setText(xpBar.max, tostring(Config.XP_PER_LEVEL))
			Motion.tween(xpBar.fill, Motion.T.xpFill, { Size = UDim2.fromScale(inLevel / Config.XP_PER_LEVEL, 1) })
		end)

		local seconds = tonumber(result.returnIn) or 20
		local studio = result.studio == true
		task.spawn(function()
			for s = seconds, 1, -1 do
				UI.setButtonText(footer, if studio then `Restart · {s}s` else `Lobby · {s}s`)
				task.wait(1)
			end
			card.holder.Visible = false
			scrim.Visible = false
		end)
	end)
end

return Results
