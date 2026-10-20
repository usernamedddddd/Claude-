--!strict
-- Match-wide tuning numbers. Tower stats live in TowerData, slime stats in SlimeData.

local Config = {
	GAME_NAME = "Slime Siege",
	MAP_THEME = "Candy Garden",

	MAX_PLAYERS = 4,
	STARTING_LIVES = 150,
	STARTING_CASH = 650,
	TOTAL_ROUNDS = 40,
	CASH_PER_LAYER = 1,
	ROUND_BONUS_BASE = 100, -- end-of-round bonus = base + round number, to every player
	SELL_REFUND = 0.7,

	PREP_SECONDS = 20, -- countdown before round 1
	INTERMISSION_SECONDS = 5, -- countdown between rounds
	FAST_FORWARD_MULTIPLIER = 2,

	SIM_DT = 1 / 30, -- fixed simulation step (seconds of game time)
	NET_SNAPSHOT_HZ = 10, -- enemy position batches sent to clients

	-- Placement
	MAX_TOWERS_PER_PLAYER = 40,
	PATH_CLEARANCE = 0.25, -- extra gap between tower footprint and path edge

	-- Combat geometry
	PIERCE_RADIUS = 2.0, -- extra targets for a piercing shot must be this close to the primary target
	CHAIN_RADIUS = 7.0,
	CLUSTER_RADIUS = 1.75,
	CHILD_SPREAD = 0.6, -- children of a popped slime are spread this far behind each other

	-- Meta rewards (Goo / XP)
	GOO_PER_ROUND = 2,
	GOO_WIN_BONUS = 60,
	XP_PER_ROUND = 10,
	XP_WIN_BONUS = 150,
	XP_PER_LEVEL = 500,

	-- Lobby
	QUEUE_COUNTDOWN = 10,
	RETURN_TO_LOBBY_SECONDS = 20,
	WAIT_FOR_PARTY_SECONDS = 15,
}

return Config
