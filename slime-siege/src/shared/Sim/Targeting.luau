--!strict
-- Target priority modes. Works on any record with distance/layers/x/z so it is easy to unit test.

export type Mode = "First" | "Last" | "Strong" | "Close"

export type Candidate = {
	distance: number,
	layers: number,
	x: number,
	z: number,
}

local Targeting = {}

Targeting.MODES = { "First", "Last", "Strong", "Close" } :: { Mode }

function Targeting.isMode(value: unknown): boolean
	return value == "First" or value == "Last" or value == "Strong" or value == "Close"
end

-- True when `a` should be targeted before `b`.
function Targeting.better(mode: Mode, a: Candidate, b: Candidate, towerX: number, towerZ: number): boolean
	if mode == "First" then
		return a.distance > b.distance
	elseif mode == "Last" then
		return a.distance < b.distance
	elseif mode == "Strong" then
		if a.layers ~= b.layers then
			return a.layers > b.layers
		end
		return a.distance > b.distance
	else
		local adx, adz = a.x - towerX, a.z - towerZ
		local bdx, bdz = b.x - towerX, b.z - towerZ
		return adx * adx + adz * adz < bdx * bdx + bdz * bdz
	end
end

-- Picks up to `count` distinct candidates in priority order (count is tiny, so repeated scans are cheap).
function Targeting.pick<T>(candidates: { T }, mode: Mode, count: number, towerX: number, towerZ: number): { T }
	local picked: { T } = {}
	local used: { [number]: boolean } = {}
	for _ = 1, math.min(count, #candidates) do
		local bestIndex: number? = nil
		for i, c in candidates do
			if not used[i] then
				if
					bestIndex == nil or Targeting.better(mode, c :: any, candidates[bestIndex] :: any, towerX, towerZ)
				then
					bestIndex = i
				end
			end
		end
		if bestIndex == nil then
			break
		end
		used[bestIndex] = true
		table.insert(picked, candidates[bestIndex])
	end
	return picked
end

return Targeting
