--!strict
-- Pure badge rules (no Roblox APIs; unit-tested). Profile facts come from saved stats plus a
-- few derived values (level, towers unlocked).

local BadgeData = require(script.Parent.Parent.Data.BadgeData)
local Config = require(script.Parent.Parent.Data.Config)

export type Facts = { [BadgeData.Fact]: number }

-- The subset of a profile the rules read.
export type ProfileLike = {
	xp: number,
	unlocked: { [string]: boolean },
	stats: { [string]: number },
	badges: { [string]: boolean }, -- present = earned; true = reward claimed
}

local Badges = {}

function Badges.level(xp: number): number
	return 1 + xp // Config.XP_PER_LEVEL
end

function Badges.facts(profile: ProfileLike): Facts
	local unlocked = 0
	for _, owned in profile.unlocked do
		if owned then
			unlocked += 1
		end
	end
	local s = profile.stats
	return {
		matches = s.matches or 0,
		wins = s.wins or 0,
		bestRound = s.bestRound or 0,
		totalPops = s.totalPops or 0,
		bossPops = s.bossPops or 0,
		towersPlaced = s.towersPlaced or 0,
		upgradesBought = s.upgradesBought or 0,
		towersUnlocked = unlocked,
		level = Badges.level(profile.xp),
		fullTeamMatches = s.fullTeamMatches or 0,
		perfectWins = s.perfectWins or 0,
	}
end

-- (current clamped to goal, goal)
function Badges.progress(def: BadgeData.BadgeDef, facts: Facts): (number, number)
	return math.min(facts[def.fact] or 0, def.goal), def.goal
end

function Badges.meets(def: BadgeData.BadgeDef, facts: Facts): boolean
	return (facts[def.fact] or 0) >= def.goal
end

-- Badges whose goal is met but that aren't recorded as earned yet, in catalog order.
function Badges.newlyEarned(profile: ProfileLike): { BadgeData.BadgeDef }
	local facts = Badges.facts(profile)
	local out = {}
	for _, def in BadgeData.list do
		if profile.badges[def.id] == nil and Badges.meets(def, facts) then
			table.insert(out, def)
		end
	end
	return out
end

-- "locked" | "claimable" | "claimed"
function Badges.status(profile: ProfileLike, id: string): string
	local entry = profile.badges[id]
	if entry == nil then
		return "locked"
	end
	return if entry then "claimed" else "claimable"
end

function Badges.earnedCount(badges: { [string]: boolean }): number
	local n = 0
	for id in badges do
		if BadgeData.byId[id] then
			n += 1
		end
	end
	return n
end

return Badges
