--!strict
-- UI theme, icon and sound tables. Swapping art or audio is a data change here.
--
-- Design source of truth: Figma "Slime Siege UI" (Design System page: tokens, text styles,
-- components, icons; Screens page: HUD, tower panel, results, lobby, phone, motion spec).
-- Colors below are the Figma color variables. Contrast (WCAG): white on green 5.2:1, blue 5.4,
-- red 5.0, purple 6.7, panel 13.7; ink on gold 10.5, on card 15.2.
--
-- Icons: export the Figma "Icons" frame (Icon/* components) as PNG @2x, upload them to Roblox
-- and paste the asset ids below; until then a glyph is drawn instead.

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

Theme.Colors = {
	Ink = hex("#2A1446"), -- outlines, dark text, chunky shadows
	Panel = hex("#3B1F5C"), -- HUD panels
	PanelRaised = hex("#4E2A7A"), -- icon bubbles, tracks, segmented control
	Card = hex("#FFF4FA"), -- light cards (hotbar slots, upgrade columns, shop cards)
	Scrim = hex("#1A0B2E"),
	Text = hex("#FFFFFF"), -- text on dark / saturated fills
	TextMuted = hex("#E6D9F5"),
	TextDark = hex("#2A1446"), -- text on light / gold
	Green = hex("#0F7A37"),
	Blue = hex("#1E66D0"),
	Red = hex("#D12F4C"),
	Purple = hex("#6A3CCB"),
	Gold = hex("#FFC733"),
	Pink = hex("#FF6FB5"), -- upgrade path A
	Cyan = hex("#47C6FF"), -- upgrade path B
	Disabled = hex("#6F6480"),
	Lime = hex("#7CFF8A"), -- progress fills, "you" marker
}

-- v2 style (Figma page "Style v2 (reference)"): dark translucent gradient panels with thick
-- bright borders, white UPPERCASE labels with black outlines, illustrated icons, big green
-- PLAY-style buttons. Every label sits on a dark panel or carries a black outline.
Theme.V2 = {
	PanelTop = hex("#2E2350"),
	PanelBottom = hex("#130E22"),
	PanelTransparency = 0.06,
	Slot = hex("#0B0816"),
	SlotTransparency = 0.4,
	SlotRing = hex("#D9D4E6"),
	Outline = hex("#000000"),
	Red = hex("#FF4157"),
	Cyan = hex("#35C8FF"),
	Purple = hex("#9A5BFF"),
	Green = hex("#2FCB4E"),
	GreenTop = hex("#5BEF74"),
	GreenBottom = hex("#15A332"),
	RedTop = hex("#FF7A8A"),
	RedBottom = hex("#D61F3A"),
	Gold = hex("#FFC83D"),
	Blue = hex("#2F7BFF"),
	Xp = hex("#3FA2FF"),
	CoinText = hex("#FFD447"),
	GooText = hex("#8CFF6B"),
	LivesText = hex("#FF8FA3"),
	Muted = hex("#C9C2D6"),
	PathA = hex("#FF6FB5"),
	PathB = hex("#35C8FF"),
	Badge = hex("#FF2E4D"),
}

-- Labels: heavy uppercase Montserrat. Numbers and titles: Fredoka One.
Theme.LabelFont = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
Theme.NumberFont = Font.fromEnum(Enum.Font.FredokaOne)

-- Animation timings from the Figma motion spec (seconds).
Theme.Motion = {
	press = 0.08,
	release = 0.18,
	punch = 0.22,
	toastIn = 0.3,
	toastOut = 0.2,
	toastHold = 2.2,
	bannerIn = 0.45,
	bannerHold = 1.2,
	panelIn = 0.26,
	panelOut = 0.15,
	countUp = 0.25,
	resultsCard = 0.5,
	resultsStagger = 0.12,
	xpFill = 0.8,
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
	skull = { image = "", glyph = "💀" },
	lock = { image = "", glyph = "🔒" },
	sell = { image = "", glyph = "💲" },
	target = { image = "", glyph = "🎯" },
	towers = { image = "", glyph = "🐸" },
	skip = { image = "", glyph = "⏭️" },
	store = { image = "", glyph = "🧺" },
	frog = { image = "", glyph = "🐸" },
	crab = { image = "", glyph = "🦀" },
	penguin = { image = "", glyph = "🐧" },
	turtle = { image = "", glyph = "🐢" },
	bee = { image = "", glyph = "🐝" },
	owl = { image = "", glyph = "🦉" },
} :: { [string]: Icon }

-- Optional meshes made with art/blender/*.py. Leave ids empty to use the built-in primitives.
-- slime: one white-bodied mesh + face texture; the game tints it per slime (VertexColor).
Theme.Meshes = {
	slime = { meshId = "", textureId = "", nativeSize = 2 },
}

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
