--!strict
-- Meta rewards for finishing a match (pure, so it can be unit tested).

local Config = require(script.Parent.Parent.Data.Config)

export type Reward = { goo: number, xp: number, roundsCleared: number }

local Rewards = {}

-- `roundReached` is the round being played when the match ended (or the last round on a win).
function Rewards.compute(roundReached: number, won: boolean, doubleGoo: boolean): Reward
	local cleared = if won then roundReached else math.max(roundReached - 1, 0)
	local goo = cleared * Config.GOO_PER_ROUND + (if won then Config.GOO_WIN_BONUS else 0)
	if doubleGoo then
		goo *= Config.DOUBLE_GOO_MULTIPLIER
	end
	local xp = cleared * Config.XP_PER_ROUND + (if won then Config.XP_WIN_BONUS else 0)
	return { goo = goo, xp = xp, roundsCleared = cleared }
end

return Rewards
