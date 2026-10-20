--!strict
-- Generates the 40 rounds as plain data. Run `lune run tools/generate_rounds` to rewrite
-- src/shared/Data/Rounds.luau. Nothing here is used at runtime by the game itself.
--
-- How it works: each round has a palette (which slimes, what share of the layer budget).
-- The layer budget and the target difficulty grow geometrically. Counts come from the
-- budget, then one spacing value per round is solved so the difficulty metric
-- (total layers x average speed / average spacing) lands exactly on the target curve.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SlimeData = require(Shared.Data.SlimeData)
local Difficulty = require(Shared.Sim.Difficulty)

export type Group = Difficulty.Group
export type Round = { Group }

type Entry = { slime: string, share: number, camo: boolean? }

local RoundGenerator = {}

RoundGenerator.ROUNDS = 40
RoundGenerator.BOSS_ROUNDS = { [20] = true, [40] = true }
RoundGenerator.FIRST_TARGET = 160 -- difficulty of round 1 (20 greens, 1s apart)
RoundGenerator.MID_ROUND = 20
RoundGenerator.MID_TARGET = 2050 -- difficulty of round 20 (first boss)
RoundGenerator.LAST_TARGET = 120000
RoundGenerator.FIRST_BUDGET = 20 -- total layers in round 1 (excluding bosses)
RoundGenerator.BUDGET_GROWTH = 1.12
RoundGenerator.MIN_SPACING = 0.12
RoundGenerator.MAX_SPACING = 2.5

local function e(slime: string, share: number, camo: boolean?): Entry
	return { slime = slime, share = share, camo = camo }
end

-- Slime mix per round. Shares are fractions of the round's layer budget.
local PALETTES: { [number]: { Entry } } = {
	[1] = { e("Green", 1) },
	[2] = { e("Green", 1) },
	[3] = { e("Green", 0.6), e("Blue", 0.4) },
	[4] = { e("Green", 0.4), e("Blue", 0.6) },
	[5] = { e("Blue", 1) },
	[6] = { e("Green", 0.3), e("Blue", 0.5), e("Yellow", 0.2) },
	[7] = { e("Blue", 0.6), e("Yellow", 0.4) },
	[8] = { e("Blue", 0.3), e("Yellow", 0.7) },
	[9] = { e("Yellow", 1) },
	[10] = { e("Blue", 0.3), e("Yellow", 0.4), e("Pink", 0.3) },
	[11] = { e("Yellow", 0.5), e("Pink", 0.5) },
	[12] = { e("Green", 0.2, true), e("Yellow", 0.4), e("Pink", 0.4) },
	[13] = { e("Yellow", 0.4), e("Pink", 0.6) },
	[14] = { e("Pink", 0.5), e("Black", 0.5) },
	[15] = { e("Blue", 0.25, true), e("Pink", 0.45), e("Black", 0.3) },
	[16] = { e("Pink", 0.5), e("Metal", 0.5) },
	[17] = { e("Black", 0.5), e("Metal", 0.5) },
	[18] = { e("Yellow", 0.3, true), e("Black", 0.35), e("Metal", 0.35) },
	[19] = { e("Pink", 0.4), e("Black", 0.3), e("Metal", 0.3) },
	[20] = { e("Yellow", 0.5), e("Pink", 0.5) }, -- + Big Boss Slime
	[21] = { e("Pink", 0.5), e("Rainbow", 0.5) },
	[22] = { e("Black", 0.3), e("Metal", 0.3), e("Rainbow", 0.4) },
	[23] = { e("Pink", 0.3, true), e("Metal", 0.3), e("Rainbow", 0.4) },
	[24] = { e("Rainbow", 1) },
	[25] = { e("Black", 0.3, true), e("Rainbow", 0.7) },
	[26] = { e("Pink", 0.3), e("Metal", 0.3), e("Rainbow", 0.4) },
	[27] = { e("Yellow", 0.2, true), e("Black", 0.3), e("Rainbow", 0.5) },
	[28] = { e("Rainbow", 0.6), e("Metal", 0.4) },
	[29] = { e("Pink", 0.3, true), e("Rainbow", 0.7) },
	[30] = { e("Rainbow", 0.3, true), e("Rainbow", 0.4), e("Metal", 0.3) },
	[31] = { e("Black", 0.4), e("Metal", 0.2), e("Rainbow", 0.4) },
	[32] = { e("Metal", 0.3, true), e("Rainbow", 0.7) },
	[33] = { e("Pink", 0.4, true), e("Rainbow", 0.6) },
	[34] = { e("Rainbow", 1) },
	[35] = { e("Black", 0.3, true), e("Metal", 0.3), e("Rainbow", 0.4) },
	[36] = { e("Rainbow", 0.4, true), e("Rainbow", 0.6) },
	[37] = { e("Metal", 0.4), e("Rainbow", 0.6) },
	[38] = { e("Pink", 0.2, true), e("Black", 0.2, true), e("Rainbow", 0.6) },
	[39] = { e("Rainbow", 0.5, true), e("Rainbow", 0.5) },
	[40] = { e("Rainbow", 0.3, true), e("Rainbow", 0.7) }, -- + Big Boss Slime
}

local function round3(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

-- Two geometric segments: a gentle ramp to the first boss, then a steeper late game.
function RoundGenerator.targetDifficulty(round: number): number
	local mid, last = RoundGenerator.MID_ROUND, RoundGenerator.ROUNDS
	if round <= mid then
		local growth = (RoundGenerator.MID_TARGET / RoundGenerator.FIRST_TARGET) ^ (1 / (mid - 1))
		return RoundGenerator.FIRST_TARGET * growth ^ (round - 1)
	end
	local growth = (RoundGenerator.LAST_TARGET / RoundGenerator.MID_TARGET) ^ (1 / (last - mid))
	return RoundGenerator.MID_TARGET * growth ^ (round - mid)
end

function RoundGenerator.layerBudget(round: number): number
	return RoundGenerator.FIRST_BUDGET * RoundGenerator.BUDGET_GROWTH ^ (round - 1)
end

local function buildRound(round: number): Round
	local palette = PALETTES[round]
	assert(palette, `no palette for round {round}`)
	local budget = RoundGenerator.layerBudget(round)
	local groups: Round = {}
	for _, entry in palette do
		local def = SlimeData[entry.slime]
		local count = math.max(1, math.floor(budget * entry.share / def.layers + 0.5))
		table.insert(groups, {
			slimeType = entry.slime,
			count = count,
			spacingSeconds = 1,
			delay = 0,
			camo = if entry.camo then true else nil,
		})
	end
	if RoundGenerator.BOSS_ROUNDS[round] then
		table.insert(groups, { slimeType = "Boss", count = 1, spacingSeconds = 1, delay = 0 })
	end

	-- Solve one spacing for the round so the metric hits the target exactly.
	local target = RoundGenerator.targetDifficulty(round)
	local layers, avgSpeed = Difficulty.breakdown(groups)
	local spacing = layers * avgSpeed / target
	if spacing < RoundGenerator.MIN_SPACING or spacing > RoundGenerator.MAX_SPACING then
		-- Scale counts toward the allowed band, then re-solve.
		local clamped = math.clamp(spacing, RoundGenerator.MIN_SPACING, RoundGenerator.MAX_SPACING)
		local scale = clamped / spacing
		for _, g in groups do
			if g.slimeType ~= "Boss" then
				g.count = math.max(1, math.floor(g.count * scale + 0.5))
			end
		end
		layers, avgSpeed = Difficulty.breakdown(groups)
		spacing = layers * avgSpeed / target
	end
	spacing = round3(spacing)

	-- Groups play back to back with a little overlap; the boss arrives after the escorts start.
	local delay = 0
	for _, g in groups do
		g.spacingSeconds = spacing
		g.delay = round3(delay)
		delay += g.count * spacing * 0.6
	end
	return groups
end

function RoundGenerator.generate(): { Round }
	local rounds: { Round } = {}
	for r = 1, RoundGenerator.ROUNDS do
		rounds[r] = buildRound(r)
	end
	return rounds
end

-- Serializes rounds as a Luau module returning a plain table.
function RoundGenerator.toLuau(rounds: { Round }): string
	local lines = {
		"--!strict",
		"-- GENERATED by tools/generate_rounds.luau (src/content/RoundGenerator.luau). Do not edit by hand.",
		"-- Each round is a list of groups: { slimeType, count, spacingSeconds, delay, camo? }.",
		"",
		"export type Group = { slimeType: string, count: number, spacingSeconds: number, delay: number, camo: boolean? }",
		"",
		"local Rounds: { { Group } } = {",
	}
	for r, groups in rounds do
		table.insert(lines, `\t-- Round {r}: difficulty {string.format("%.1f", Difficulty.metric(groups))}`)
		table.insert(lines, "\t{")
		for _, g in groups do
			local camo = if g.camo then ", camo = true" else ""
			table.insert(
				lines,
				`\t\t\{ slimeType = "{g.slimeType}", count = {g.count}, spacingSeconds = {g.spacingSeconds}, delay = {g.delay}{camo} },`
			)
		end
		table.insert(lines, "\t},")
	end
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, "return Rounds")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

return RoundGenerator
