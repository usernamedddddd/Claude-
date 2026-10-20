--!strict
-- Majority voting for "start next round" and fast-forward.

local Votes = {}

-- Strict majority of the players currently in the match.
function Votes.hasMajority(yesVotes: number, playerCount: number): boolean
	return playerCount > 0 and yesVotes * 2 > playerCount
end

function Votes.count(votes: { [number]: boolean }, present: { [number]: any }): number
	local n = 0
	for key, yes in votes do
		if yes and present[key] ~= nil then
			n += 1
		end
	end
	return n
end

return Votes
