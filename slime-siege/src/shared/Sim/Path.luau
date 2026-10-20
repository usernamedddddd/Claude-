--!strict
-- Polyline path math. Enemies are stored as "distance along the path"; this converts to XZ.

local MapData = require(script.Parent.Parent.Data.MapData)

export type Segment = {
	ax: number,
	az: number,
	dx: number, -- unit direction
	dz: number,
	length: number,
	startDistance: number,
}

export type Path = {
	segments: { Segment },
	totalLength: number,
}

local Path = {}

function Path.build(waypoints: { MapData.Point }): Path
	assert(#waypoints >= 2, "a path needs at least two waypoints")
	local segments: { Segment } = {}
	local total = 0
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local ex, ez = b.x - a.x, b.z - a.z
		local length = math.sqrt(ex * ex + ez * ez)
		if length > 0 then
			table.insert(segments, {
				ax = a.x,
				az = a.z,
				dx = ex / length,
				dz = ez / length,
				length = length,
				startDistance = total,
			})
			total += length
		end
	end
	return { segments = segments, totalLength = total }
end

-- Binary search for the segment containing `distance`.
local function segmentAt(path: Path, distance: number): Segment
	local segments = path.segments
	local lo, hi = 1, #segments
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if segments[mid].startDistance <= distance then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return segments[lo]
end

-- Returns x, z, and the unit heading (dx, dz) at a distance along the path.
function Path.positionAt(path: Path, distance: number): (number, number, number, number)
	local d = math.clamp(distance, 0, path.totalLength)
	local seg = segmentAt(path, d)
	local t = d - seg.startDistance
	return seg.ax + seg.dx * t, seg.az + seg.dz * t, seg.dx, seg.dz
end

-- Shortest distance from a point to the path polyline.
function Path.distanceToPath(path: Path, x: number, z: number): number
	local best = math.huge
	for _, seg in path.segments do
		local px, pz = x - seg.ax, z - seg.az
		local t = math.clamp(px * seg.dx + pz * seg.dz, 0, seg.length)
		local cx, cz = seg.ax + seg.dx * t, seg.az + seg.dz * t
		local ox, oz = x - cx, z - cz
		local d = math.sqrt(ox * ox + oz * oz)
		if d < best then
			best = d
		end
	end
	return best
end

return Path
