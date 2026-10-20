--!strict
-- "Candy Garden": the single MVP map. All coordinates are on the XZ ground plane (Y = GROUND_Y).

export type Point = { x: number, z: number }
export type Blocker = { x: number, z: number, r: number, kind: string }

export type MapDef = {
	id: string,
	displayName: string,
	groundY: number,
	pathWidth: number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	waypoints: { Point },
	blockers: { Blocker },
	cameraFocus: Point,
}

local MapData: MapDef = {
	id = "CandyGarden",
	displayName = "Candy Garden",
	groundY = 0,
	pathWidth = 6,
	bounds = { minX = -76, maxX = 76, minZ = -46, maxZ = 46 },
	waypoints = {
		{ x = -76, z = -30 },
		{ x = -40, z = -30 },
		{ x = -40, z = 25 },
		{ x = -10, z = 25 },
		{ x = -10, z = -35 },
		{ x = 20, z = -35 },
		{ x = 20, z = 30 },
		{ x = 50, z = 30 },
		{ x = 50, z = -10 },
		{ x = 76, z = -10 },
	},
	-- Decorations that towers cannot be placed on.
	blockers = {
		{ x = -58, z = 10, r = 3, kind = "Lollipop" },
		{ x = 5, z = 0, r = 2.5, kind = "Gumdrop" },
		{ x = 35, z = -30, r = 3, kind = "Lollipop" },
		{ x = -25, z = 40, r = 3, kind = "Cupcake" },
		{ x = 63, z = 30, r = 3, kind = "Lollipop" },
		{ x = -62, z = -42, r = 2.5, kind = "Gumdrop" },
		{ x = 35, z = 42, r = 2.5, kind = "Gumdrop" },
	},
	cameraFocus = { x = 0, z = 0 },
}

return MapData
