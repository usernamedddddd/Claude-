--!strict
-- Badge catalog (Figma "Badges window"). Each badge is earned when one profile fact reaches
-- its goal (see Sim/Badges); earning is permanent, and claiming pays the Goo reward once.
-- `robloxBadgeId` stays 0 until a real Roblox badge exists; non-zero ids are also awarded via
-- BadgeService so they show on the player's Roblox profile.
-- Pure data (no Roblox types) so headless tests and the simulator can load it.

export type Fact =
	"matches"
	| "wins"
	| "bestRound"
	| "totalPops"
	| "bossPops"
	| "towersPlaced"
	| "upgradesBought"
	| "towersUnlocked"
	| "level"
	| "fullTeamMatches"
	| "perfectWins"

export type Tint = "gold" | "blue" | "red" | "green" | "purple" -- Theme.BadgeTint key

export type BadgeDef = {
	id: string,
	name: string,
	description: string,
	icon: string, -- Theme.Icons key
	tint: Tint, -- medallion colour
	fact: Fact,
	goal: number,
	reward: number, -- Goo paid on claim
	order: number,
	robloxBadgeId: number,
}

local list: { BadgeDef } = {}

local function badge(
	id: string,
	name: string,
	description: string,
	icon: string,
	tint: Tint,
	fact: Fact,
	goal: number,
	reward: number
)
	table.insert(list, {
		id = id,
		name = name,
		description = description,
		icon = icon,
		tint = tint,
		fact = fact,
		goal = goal,
		reward = reward,
		order = #list + 1,
		robloxBadgeId = 0,
	})
end

badge("FirstSteps", "First Steps", "Finish your first match", "trophy", "gold", "matches", 1, 25)
badge("Wave10", "Wave 10", "Survive to round 10", "star", "gold", "bestRound", 10, 40)
badge("Halfway", "Halfway", "Survive to round 20", "star", "blue", "bestRound", 20, 60)
badge("BossBuster", "Boss Buster", "Pop a big Boss slime", "skull", "red", "bossPops", 1, 100)
badge("Champion", "Champion", "Win a match", "heart", "gold", "wins", 1, 150)
badge("Veteran", "Veteran", "Win 5 matches", "trophy", "purple", "wins", 5, 300)
badge("Pop1K", "Pop 1K", "Pop 1,000 slime layers", "goo", "gold", "totalPops", 1000, 50)
badge("Pop10K", "Pop 10K", "Pop 10,000 slime layers", "goo", "blue", "totalPops", 10000, 150)
badge("Builder", "Builder", "Place 100 towers", "frog", "gold", "towersPlaced", 100, 60)
badge("Pop100K", "Pop 100K", "Pop 100,000 slime layers", "goo", "purple", "totalPops", 100000, 400)
badge("Upgrader", "Upgrader", "Buy 50 upgrades", "fast", "green", "upgradesBought", 50, 60)
badge("Collector", "Collector", "Unlock all 6 towers", "towers", "purple", "towersUnlocked", 6, 200)
badge("Level5", "Level 5", "Reach level 5", "star", "green", "level", 5, 50)
badge("Level10", "Level 10", "Reach level 10", "star", "red", "level", 10, 150)
badge("TeamPlayer", "Team Player", "Finish a match with a full team of 4", "target", "blue", "fullTeamMatches", 1, 80)
badge("Untouchable", "Untouchable", "Win without losing a single life", "heart", "red", "perfectWins", 1, 500)

local byId: { [string]: BadgeDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
}
