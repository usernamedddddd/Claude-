--!strict
-- Round difficulty metric: total layers x average speed / average spacing.
-- Averages are weighted by slime count, so a round with several groups is one number.

local SlimeData = require(script.Parent.Parent.Data.SlimeData)

export type Group = {
	slimeType: string,
	count: number,
	spacingSeconds: number,
	delay: number,
	camo: boolean?,
}

local MIN_SPACING = 0.05

local Difficulty = {}

function Difficulty.breakdown(round: { Group }): (number, number, number)
	local layers, count, speedSum, spacingSum = 0, 0, 0, 0
	for _, g in round do
		local def = SlimeData[g.slimeType]
		assert(def, `unknown slime {g.slimeType}`)
		layers += def.layers * g.count
		count += g.count
		speedSum += def.speed * g.count
		spacingSum += math.max(g.spacingSeconds, MIN_SPACING) * g.count
	end
	if count == 0 then
		return 0, 0, 1
	end
	return layers, speedSum / count, spacingSum / count
end

function Difficulty.metric(round: { Group }): number
	local layers, avgSpeed, avgSpacing = Difficulty.breakdown(round)
	return layers * avgSpeed / avgSpacing
end

return Difficulty
