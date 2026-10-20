--!strict
-- End-of-match card from the Figma "Results — Victory / Defeat" frames: scrim fade, card pop,
-- badge, reward tiles that stagger in and count up, and the level bar filling.

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

local C = UI.Colors

function Results.start()
	local gui = UI.screen("Results", 5)
	local root = UI.root(gui)
	local scrim = UI.new("Frame", {
		Name = "Scrim",
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})

	local card = UI.surface({
		Name = "Results",
		Size = UDim2.fromOffset(720, 700),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		color = C.Panel,
		radius = 36,
		Visible = false,
		Parent = root,
	})
	local face = card.face
	local badge = UI.surface({
		Name = "Badge",
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(0.5, 0, 0, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		color = C.Gold,
		radius = 999,
		Parent = face,
	})
	local badgeIcon = UI.icon("trophy", {
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = badge.face,
	})
	local title = UI.text({
		Name = "Title",
		Text = "VICTORY!",
		size = 88,
		color = C.Gold,
		Size = UDim2.new(1, 0, 0, 100),
		Position = UDim2.fromOffset(0, 196),
		Parent = face,
		strokeThickness = 4,
	})
	local subtitle = UI.text({
		Text = "",
		size = 22,
		color = C.TextMuted,
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.new(0, 30, 0, 296),
		Parent = face,
		stroke = false,
	})

	local tiles = UI.new("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -80, 0, 150),
		Position = UDim2.new(0, 40, 0, 344),
		Parent = face,
	})
	UI.list(tiles, Enum.FillDirection.Horizontal, 16)
	type Tile = { holder: GuiObject, value: TextLabel }
	local function tile(order: number, icon: string, label: string): Tile
		local t = UI.surface({
			Name = label,
			Size = UDim2.fromOffset(190, 140),
			color = C.Card,
			radius = 24,
			LayoutOrder = order,
			Parent = tiles,
		})
		UI.icon(icon, {
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.new(0.5, 0, 0, 14),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = t.face,
		})
		local value = UI.text({
			Text = "0",
			size = 38,
			color = C.TextDark,
			Size = UDim2.new(1, 0, 0, 42),
			Position = UDim2.fromOffset(0, 66),
			Parent = t.face,
		})
		UI.text({
			Text = label,
			size = 16,
			color = C.TextDark,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 108),
			Parent = t.face,
		})
		return { holder = t.holder, value = value }
	end
	local roundTile = tile(1, "star", "Round")
	local gooTile = tile(2, "goo", "Goo")
	local xpTile = tile(3, "trophy", "XP")

	local levelLabel = UI.text({
		Text = "Level 1",
		size = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -40, 0, 28),
		Position = UDim2.new(0, 40, 0, 512),
		Parent = face,
	})
	local xpLabel = UI.text({
		Text = "",
		size = 22,
		color = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.5, -40, 0, 28),
		Position = UDim2.new(0.5, 0, 0, 512),
		Parent = face,
		stroke = false,
	})
	local xpBar, xpFill = UI.bar({ Size = UDim2.new(1, -80, 0, 22), outline = true, Parent = face })
	xpBar.Position = UDim2.new(0, 40, 0, 546)

	local footer = UI.button({
		Name = "Footer",
		Text = "Back to lobby",
		icon = "play",
		color = C.Green,
		Size = UDim2.fromOffset(380, 66),
		Position = UDim2.new(0.5, 0, 1, -96),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = face,
	}, function() end)
	footer.Active = false

	Remotes.get("MatchResult").OnClientEvent:Connect(function(result: { [string]: any })
		Placement.cancel()
		local won = result.won == true
		local roundReached = tonumber(result.round) or 0
		badge.face.BackgroundColor3 = if won then C.Gold else C.Red
		badgeIcon:Destroy()
		badgeIcon = UI.icon(if won then "trophy" else "skull", {
			Size = UDim2.fromScale(0.72, 0.72),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = badge.face,
		})
		title.Text = if won then "VICTORY!" else "DEFEAT"
		title.TextColor3 = if won then C.Gold else C.Text
		subtitle.Text = if won
			then `You held the Candy Garden through all {Config.TOTAL_ROUNDS} rounds`
			else `The slimes broke through on round {roundReached}`

		-- Scrim fade + card pop (Figma motion: 300 ms, 500 ms Back-Out)
		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.tween(scrim, 0.3, { BackgroundTransparency = 0.28 })
		Motion.popIn(card.holder, 0.6, Motion.T.resultsCard)
		Sound.play(if won then "sparkle" else "leak")

		-- Reward tiles stagger in and count up.
		type Reward = { tile: Tile, target: number, format: (number) -> string }
		local rewards: { Reward } = {
			{
				tile = roundTile,
				target = roundReached,
				format = function(n: number): string
					return `{n}/{Config.TOTAL_ROUNDS}`
				end,
			},
			{
				tile = gooTile,
				target = tonumber(result.goo) or 0,
				format = function(n: number): string
					return `+{n}`
				end,
			},
			{
				tile = xpTile,
				target = tonumber(result.xp) or 0,
				format = function(n: number): string
					return `+{n}`
				end,
			},
		}
		for i, reward in rewards do
			reward.tile.value.Text = reward.format(0)
			Motion.countTo(reward.tile.value, 0, reward.format)
			task.delay(Motion.T.resultsCard + (i - 1) * Motion.T.resultsStagger, function()
				Motion.popIn(reward.tile.holder, 0.7, 0.3)
				Motion.countTo(reward.tile.value, reward.target, reward.format, 0.6)
			end)
		end

		-- Level bar (profile arrives right after the result).
		local function refreshLevel()
			local profile = Store.profile
			if not profile then
				return
			end
			local inLevel = profile.xp % Config.XP_PER_LEVEL
			levelLabel.Text = `Level {profile.level}`
			xpLabel.Text = `{inLevel} / {Config.XP_PER_LEVEL} XP`
			Motion.tween(xpFill, Motion.T.xpFill, { Size = UDim2.fromScale(inLevel / Config.XP_PER_LEVEL, 1) })
		end
		xpFill.Size = UDim2.fromScale(0, 1)
		task.delay(Motion.T.resultsCard + 0.4, refreshLevel)

		local seconds = tonumber(result.returnIn) or 20
		local studio = result.studio == true
		task.spawn(function()
			for s = seconds, 1, -1 do
				UI.setButtonText(footer, if studio then `Restarting · {s}s` else `Back to lobby · {s}s`)
				task.wait(1)
			end
			card.holder.Visible = false
			scrim.Visible = false
		end)
	end)
end

return Results
