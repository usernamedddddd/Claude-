--!strict
-- Placement validity, shared by the client ghost preview and the server's authoritative check.

local Config = require(script.Parent.Parent.Data.Config)
local MapData = require(script.Parent.Parent.Data.MapData)
local Path = require(script.Parent.Path)

export type Footprint = { x: number, z: number, footprint: number }

local Placement = {}

function Placement.check(
	map: MapData.MapDef,
	path: Path.Path,
	towers: { Footprint },
	footprint: number,
	x: number,
	z: number
): (boolean, string?)
	if x ~= x or z ~= z then
		return false, "Invalid position"
	end
	local b = map.bounds
	if x - footprint < b.minX or x + footprint > b.maxX or z - footprint < b.minZ or z + footprint > b.maxZ then
		return false, "Out of bounds"
	end
	if Path.distanceToPath(path, x, z) < map.pathWidth / 2 + footprint + Config.PATH_CLEARANCE then
		return false, "Too close to the path"
	end
	for _, blocker in map.blockers do
		local dx, dz = x - blocker.x, z - blocker.z
		local minDist = blocker.r + footprint
		if dx * dx + dz * dz < minDist * minDist then
			return false, "Blocked by decoration"
		end
	end
	for _, t in towers do
		local dx, dz = x - t.x, z - t.z
		local minDist = t.footprint + footprint
		if dx * dx + dz * dz < minDist * minDist then
			return false, "Overlaps another tower"
		end
	end
	return true, nil
end

return Placement
