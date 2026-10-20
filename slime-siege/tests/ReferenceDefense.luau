--!strict
-- The "reference defense": a scripted single-player build used by the content pipeline.
-- Acceptance (M0): it must clear rounds 1-20 with zero leaks while paying for everything
-- from normal income (starting cash, pops, round bonuses). Actions run in order; each waits
-- until its round and until it is affordable.

local ServerStorage = game:GetService("ServerStorage")
local Simulator = require(ServerStorage.Content.Simulator)

type Action = Simulator.Action

local actions: { Action } = {
	{ round = 1, place = "DartFrog", x = -4, z = -29, name = "frogCorner" },
	{ round = 1, place = "DartFrog", x = -34, z = 19, name = "frogStart" },
	{ round = 2, name = "frogCorner", upgrade = "A" },
	{ round = 3, place = "DartFrog", x = -4, z = 10, name = "sniper" },
	{ round = 4, name = "frogStart", upgrade = "A" },
	{ round = 5, place = "SpikeTurtle", x = -16, z = 19, name = "turtle" },
	{ round = 6, name = "frogCorner", upgrade = "B" },
	{ round = 7, place = "DartFrog", x = 56, z = -4, name = "frogExit" },
	{ round = 8, name = "sniper", upgrade = "B" },
	{ round = 9, name = "frogExit", upgrade = "A" },
	{ round = 10, name = "sniper", upgrade = "B" },
	{ round = 11, name = "frogCorner", upgrade = "A" },
	{ round = 12, name = "sniper", upgrade = "A" },
	{ round = 13, name = "turtle", upgrade = "B" },
	{ round = 14, name = "turtle", upgrade = "B" },
	{ round = 15, place = "WizardOwl", x = 26, z = 24, name = "owl" },
	{ round = 16, name = "sniper", upgrade = "B" },
	{ round = 16, name = "sniper", target = "Strong" },
	{ round = 17, name = "frogExit", upgrade = "A" },
	{ round = 18, name = "owl", upgrade = "A" },
	{ round = 19, name = "frogStart", upgrade = "A" },
	{ round = 20, place = "CannonCrab", x = -28, z = 15, name = "crab" },
	-- Late game (rounds 21-40 are not part of the acceptance gate, but keep the curve honest).
	{ round = 21, place = "BankBee", x = -60, z = 30, name = "bank" },
	{ round = 22, name = "crab", upgrade = "B" },
	{ round = 22, name = "crab", upgrade = "B" },
	{ round = 23, name = "frogCorner", upgrade = "A" },
	{ round = 24, name = "bank", upgrade = "A" },
	{ round = 25, place = "IcePenguin", x = 14, z = -29, name = "penguin" },
	{ round = 25, name = "penguin", upgrade = "B" },
	{ round = 26, name = "owl", upgrade = "A" },
	{ round = 27, name = "penguin", upgrade = "A" },
	{ round = 27, name = "penguin", upgrade = "A" },
	{ round = 28, place = "WizardOwl", x = 26, z = 0, name = "owl2" },
	{ round = 28, name = "owl2", upgrade = "B" },
	{ round = 29, name = "owl2", upgrade = "B" },
	{ round = 30, name = "owl2", upgrade = "B" },
	{ round = 32, name = "frogStart", upgrade = "B" },
	{ round = 32, place = "CannonCrab", x = 44, z = 5, name = "crab2" },
	{ round = 33, name = "crab2", upgrade = "A" },
	{ round = 34, name = "crab2", upgrade = "A" },
	{ round = 35, name = "crab2", upgrade = "A" },
	{ round = 36, name = "crab2", upgrade = "B" },
	{ round = 36, name = "penguin", upgrade = "A" },
	{ round = 37, name = "turtle", upgrade = "B" },
}

return {
	actions = actions,
	-- Acceptance gate for the content pipeline.
	MUST_CLEAR_ROUND = 20,
}
