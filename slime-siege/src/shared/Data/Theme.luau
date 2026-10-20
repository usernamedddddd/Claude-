--!strict
-- UI theme, icon and sound tables. Swapping art or audio is a data change here.
--
-- Icons: the target style is "Free Icon Pack 3.0.1 Basic" by gvesster (chunky simulator icons).
-- Upload the PNGs to Roblox and paste the asset ids below; until then a glyph is drawn instead.

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne

Theme.Colors = {
	Panel = Color3.fromRGB(255, 246, 252),
	PanelDark = Color3.fromRGB(92, 54, 120),
	Stroke = Color3.fromRGB(58, 30, 80),
	Text = Color3.fromRGB(255, 255, 255),
	TextDark = Color3.fromRGB(58, 30, 80),
	Green = Color3.fromRGB(88, 214, 104),
	Red = Color3.fromRGB(255, 90, 110),
	Blue = Color3.fromRGB(80, 170, 255),
	Yellow = Color3.fromRGB(255, 208, 60),
	Pink = Color3.fromRGB(255, 130, 200),
	Purple = Color3.fromRGB(160, 110, 240),
	Gray = Color3.fromRGB(150, 150, 165),
	Gold = Color3.fromRGB(255, 200, 40),
}

export type Icon = { image: string, glyph: string }

Theme.Icons = {
	coin = { image = "", glyph = "💰" },
	goo = { image = "", glyph = "🟢" },
	heart = { image = "", glyph = "❤️" },
	settings = { image = "", glyph = "⚙️" },
	shop = { image = "", glyph = "🛒" },
	star = { image = "", glyph = "⭐" },
	trophy = { image = "", glyph = "🏆" },
	close = { image = "", glyph = "✖" },
	check = { image = "", glyph = "✔" },
	play = { image = "", glyph = "▶" },
	fast = { image = "", glyph = "⏩" },
	lock = { image = "", glyph = "🔒" },
	sell = { image = "", glyph = "💲" },
	target = { image = "", glyph = "🎯" },
	frog = { image = "", glyph = "🐸" },
	crab = { image = "", glyph = "🦀" },
	penguin = { image = "", glyph = "🐧" },
	turtle = { image = "", glyph = "🐢" },
	bee = { image = "", glyph = "🐝" },
	owl = { image = "", glyph = "🦉" },
} :: { [string]: Icon }

-- Built-in engine sounds so the game makes noise with zero uploads; replace with your own ids.
Theme.Sounds = {
	squish = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, pitch = 1.6, jitter = 0.25 },
	bossPop = { id = "rbxasset://sounds/collide.wav", volume = 0.9, pitch = 0.6, jitter = 0.05 },
	thump = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, pitch = 0.7, jitter = 0.05 },
	sparkle = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.4, jitter = 0.1 },
	cash = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, pitch = 2, jitter = 0.1 },
	click = { id = "rbxasset://sounds/button.wav", volume = 0.5, pitch = 1, jitter = 0.05 },
	leak = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.4, pitch = 1.3, jitter = 0.05 },
	error = { id = "rbxasset://sounds/button.wav", volume = 0.5, pitch = 0.6, jitter = 0 },
} :: { [string]: { id: string, volume: number, pitch: number, jitter: number } }

return Theme
