--!strict
-- Slime definitions. "layers" is the leak cost (lives lost if it reaches the End) and the
-- difficulty weight used by the round generator. "hp" is how many damage points strip this
-- layer (1 for everything except bosses). Popping a slime spawns its "children" in place.

export type DamageType = "sharp" | "explosive" | "cold" | "magic" | "fire"

export type SlimeDef = {
	id: string,
	displayName: string,
	layers: number,
	hp: number,
	speed: number, -- studs per second
	children: { string },
	immune: { [DamageType]: boolean },
	isBoss: boolean,
	freezeImmune: boolean,
	color: { number }, -- r, g, b (0-255) for rendering
	size: number, -- visual diameter in studs
}

local SlimeData: { [string]: SlimeDef } = {
	Green = {
		id = "Green",
		displayName = "Green Slime",
		layers = 1,
		hp = 1,
		speed = 8,
		children = {},
		immune = {},
		isBoss = false,
		freezeImmune = false,
		color = { 96, 214, 92 },
		size = 1.4,
	},
	Blue = {
		id = "Blue",
		displayName = "Blue Slime",
		layers = 2,
		hp = 1,
		speed = 10,
		children = { "Green" },
		immune = {},
		isBoss = false,
		freezeImmune = false,
		color = { 76, 150, 255 },
		size = 1.6,
	},
	Yellow = {
		id = "Yellow",
		displayName = "Yellow Slime",
		layers = 3,
		hp = 1,
		speed = 14,
		children = { "Blue" },
		immune = {},
		isBoss = false,
		freezeImmune = false,
		color = { 255, 218, 60 },
		size = 1.75,
	},
	Pink = {
		id = "Pink",
		displayName = "Pink Slime",
		layers = 4,
		hp = 1,
		speed = 18,
		children = { "Yellow" },
		immune = {},
		isBoss = false,
		freezeImmune = false,
		color = { 255, 120, 196 },
		size = 1.9,
	},
	Black = {
		id = "Black",
		displayName = "Black Slime",
		layers = 6,
		hp = 1,
		speed = 10,
		children = { "Pink", "Pink" },
		immune = { explosive = true },
		isBoss = false,
		freezeImmune = false,
		color = { 40, 36, 52 },
		size = 1.9,
	},
	Metal = {
		id = "Metal",
		displayName = "Metal Slime",
		layers = 6,
		hp = 1,
		speed = 8,
		children = { "Pink", "Pink" },
		immune = { sharp = true },
		isBoss = false,
		freezeImmune = false,
		color = { 170, 178, 190 },
		size = 1.9,
	},
	Rainbow = {
		id = "Rainbow",
		displayName = "Rainbow Slime",
		layers = 12,
		hp = 1,
		speed = 12,
		children = { "Black", "Black", "Metal", "Metal" },
		immune = {},
		isBoss = false,
		freezeImmune = false,
		color = { 180, 110, 255 },
		size = 2.4,
	},
	Boss = {
		id = "Boss",
		displayName = "Big Boss Slime",
		layers = 200,
		hp = 200,
		speed = 4,
		children = { "Rainbow", "Rainbow", "Rainbow", "Rainbow" },
		immune = {},
		isBoss = true,
		freezeImmune = true,
		color = { 120, 220, 120 },
		size = 7,
	},
}

return SlimeData
