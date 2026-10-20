--!strict
-- Every tower number lives here. Balancing is a data change, never a code change.
--
-- Upgrade "mods" are applied in order (path A tiers, then path B tiers) on top of `base`:
--   attack     = { field = n }    adds n to the primary attack's field
--   attackMul  = { field = n }    multiplies the primary attack's field by n
--   attackSet  = { field = v }    overwrites the primary attack's field
--   tower      = { field = n }    adds n to a tower-level field (income, auras, ...)
--   towerSet   = { field = v }    overwrites a tower-level field
--   addAttack  = AttackSpec       adds a secondary attack with its own cooldown
-- Five tiers per path; tier 5 is the path's ULTIMATE.
-- Crosspath rule (see Sim/Upgrades): up to tier 5 on one path and tier 2 on the other.

local SlimeData = require(script.Parent.SlimeData)

export type DamageType = SlimeData.DamageType
export type AttackKind = "projectile" | "nova"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type TargetMode = "First" | "Last" | "Strong" | "Close"

export type AttackSpec = {
	kind: AttackKind, -- projectile: hits chosen targets; nova: hits everything in range
	range: number,
	cooldown: number,
	damage: number,
	pierce: number, -- max slimes hit per projectile (or per nova pulse)
	projectiles: number, -- distinct primary targets per attack
	splash: number, -- splash radius around each primary target (0 = none)
	damageType: DamageType,
	freeze: number, -- seconds hit slimes are frozen (bosses are immune)
	stun: number, -- seconds hit slimes are stunned (bosses are immune)
	bossMultiplier: number,
	chain: number, -- extra hops to nearby slimes after each primary hit
	clusters: number, -- extra mini-splashes around each primary target
	brittle: number, -- seconds hit slimes take +1 damage from every hit
	visual: string, -- client effect key
}

export type TowerStats = {
	attacks: { AttackSpec },
	camo: boolean,
	camoAura: number, -- towers within this radius can see camo
	slowAura: number, -- slimes within this radius move at slowFactor
	slowFactor: number,
	slowBosses: boolean,
	income: number, -- cash per round for Bank Bee
	interestRate: number, -- fraction of owner's cash added at round end
	interestCap: number,
	shareIncome: boolean, -- split income evenly between all players
	teamBonus: number, -- extra cash to every teammate per round
}

export type Mods = {
	attack: { [string]: number }?,
	attackMul: { [string]: number }?,
	attackSet: { [string]: any }?,
	tower: { [string]: number }?,
	towerSet: { [string]: any }?,
	addAttack: AttackSpec?,
}

export type Tier = {
	name: string,
	cost: number,
	description: string,
	mods: Mods,
}

export type UpgradePath = {
	name: string,
	tiers: { Tier },
}

export type TowerDef = {
	id: string,
	displayName: string,
	description: string,
	cost: number,
	unlockGoo: number,
	footprint: number, -- radius in studs used for placement overlap checks
	color: { number },
	icon: string,
	order: number,
	rarity: Rarity, -- shop display only (card colour); never affects stats
	base: TowerStats,
	paths: { A: UpgradePath, B: UpgradePath },
}

local function attack(spec: { [string]: any }): AttackSpec
	return {
		kind = spec.kind or "projectile",
		range = spec.range or 10,
		cooldown = spec.cooldown or 1,
		damage = spec.damage or 1,
		pierce = spec.pierce or 1,
		projectiles = spec.projectiles or 1,
		splash = spec.splash or 0,
		damageType = spec.damageType or "sharp",
		freeze = spec.freeze or 0,
		stun = spec.stun or 0,
		bossMultiplier = spec.bossMultiplier or 1,
		chain = spec.chain or 0,
		clusters = spec.clusters or 0,
		brittle = spec.brittle or 0,
		visual = spec.visual or "dart",
	}
end

local function stats(spec: { [string]: any }): TowerStats
	return {
		attacks = spec.attacks or {},
		camo = spec.camo or false,
		camoAura = spec.camoAura or 0,
		slowAura = spec.slowAura or 0,
		slowFactor = spec.slowFactor or 1,
		slowBosses = spec.slowBosses or false,
		income = spec.income or 0,
		interestRate = spec.interestRate or 0,
		interestCap = spec.interestCap or 0,
		shareIncome = spec.shareIncome or false,
		teamBonus = spec.teamBonus or 0,
	}
end

local TowerData: { [string]: TowerDef } = {
	DartFrog = {
		id = "DartFrog",
		displayName = "Dart Frog",
		description = "Spits sharp darts. Cheap and reliable.",
		cost = 200,
		unlockGoo = 0,
		footprint = 1.5,
		color = { 92, 200, 110 },
		icon = "frog",
		order = 1,
		rarity = "Common",
		base = stats({
			attacks = {
				attack({ range = 12, cooldown = 0.9, damage = 1, pierce = 2, damageType = "sharp", visual = "dart" }),
			},
		}),
		paths = {
			A = {
				name = "Volley",
				tiers = {
					{
						name = "Pierce +2",
						cost = 140,
						description = "Darts pop 2 more slimes.",
						mods = { attack = { pierce = 2 } },
					},
					{
						name = "Triple Shot",
						cost = 310,
						description = "Throws 3 darts at 3 different slimes.",
						mods = { attack = { projectiles = 2 } },
					},
					{
						name = "Rapid Volley",
						cost = 680,
						description = "Attacks nearly 3x faster with extra pierce.",
						mods = { attackMul = { cooldown = 0.35 }, attack = { pierce = 2 } },
					},
					{
						name = "Dart Storm",
						cost = 1500,
						description = "Throws 3 more darts with +2 pierce.",
						mods = { attack = { projectiles = 3, pierce = 2 } },
					},
					{
						name = "Frog Monsoon",
						cost = 3300,
						description = "ULTIMATE: a storm of darts. 2x attack speed, +2 damage, 2 more darts, +4 pierce.",
						mods = { attack = { damage = 2, projectiles = 2, pierce = 4 }, attackMul = { cooldown = 0.5 } },
					},
				},
			},
			B = {
				name = "Marksman",
				tiers = {
					{
						name = "Range + Camo",
						cost = 120,
						description = "+4 range and can see camo slimes.",
						mods = { attack = { range = 4 }, towerSet = { camo = true } },
					},
					{
						name = "Long Shot",
						cost = 265,
						description = "+8 range and +1 damage.",
						mods = { attack = { range = 8, damage = 1 } },
					},
					{
						name = "Sniper Darts",
						cost = 585,
						description = "Huge range, 5 damage per dart, double damage to bosses.",
						mods = { attack = { range = 20, damage = 3 }, attackSet = { bossMultiplier = 2 } },
					},
					{
						name = "Deadeye",
						cost = 1290,
						description = "+4 damage per dart, triple damage to bosses.",
						mods = { attack = { damage = 4 }, attackSet = { bossMultiplier = 3 } },
					},
					{
						name = "Legendary Sniper",
						cost = 2840,
						description = "ULTIMATE: +10 damage, 2x attack speed, darts pierce 3 more, 5x damage to bosses.",
						mods = {
							attack = { damage = 10, pierce = 3 },
							attackMul = { cooldown = 0.5 },
							attackSet = { bossMultiplier = 5 },
						},
					},
				},
			},
		},
	},

	CannonCrab = {
		id = "CannonCrab",
		displayName = "Cannon Crab",
		description = "Lobs bombs that splash. Can't hurt Black slimes.",
		cost = 500,
		unlockGoo = 150,
		footprint = 2,
		color = { 240, 110, 80 },
		icon = "crab",
		order = 2,
		rarity = "Epic",
		base = stats({
			attacks = {
				attack({
					range = 14,
					cooldown = 1.4,
					damage = 1,
					pierce = 14,
					splash = 3,
					damageType = "explosive",
					visual = "bomb",
				}),
			},
		}),
		paths = {
			A = {
				name = "Demolition",
				tiers = {
					{
						name = "Bigger Splash",
						cost = 300,
						description = "+1.5 splash radius, hits 8 more slimes.",
						mods = { attack = { splash = 1.5, pierce = 8 } },
					},
					{
						name = "Cluster Bombs",
						cost = 660,
						description = "Each bomb scatters 4 mini-bombs.",
						mods = { attack = { clusters = 4 } },
					},
					{
						name = "Megablast",
						cost = 1450,
						description = "Massive blasts: +3 damage, +2 splash.",
						mods = { attack = { damage = 3, splash = 2, pierce = 20 } },
					},
					{
						name = "Bomb Barrage",
						cost = 3190,
						description = "Fires 2 more bombs, each with 4 more mini-bombs.",
						mods = { attack = { projectiles = 2, clusters = 4 } },
					},
					{
						name = "Doomsday Crab",
						cost = 7020,
						description = "ULTIMATE: +6 damage, +3 splash, huge pierce, fires 40% faster.",
						mods = { attack = { damage = 6, splash = 3, pierce = 40 }, attackMul = { cooldown = 0.6 } },
					},
				},
			},
			B = {
				name = "Artillery",
				tiers = {
					{
						name = "Faster Reload",
						cost = 250,
						description = "Fires 30% faster.",
						mods = { attackMul = { cooldown = 0.7 } },
					},
					{
						name = "Stun Shock",
						cost = 550,
						description = "Blasts stun slimes for 0.6s.",
						mods = { attack = { stun = 0.6 } },
					},
					{
						name = "Boss Shells",
						cost = 1210,
						description = "+2 damage and 6x damage to bosses.",
						mods = { attack = { damage = 2 }, attackSet = { bossMultiplier = 6 } },
					},
					{
						name = "Shockwave Shells",
						cost = 2660,
						description = "Stuns 0.6s longer, fires 30% faster, +4 range.",
						mods = { attack = { stun = 0.6, range = 4 }, attackMul = { cooldown = 0.7 } },
					},
					{
						name = "Titan Mortar",
						cost = 5850,
						description = "ULTIMATE: +8 damage, +10 range and 10x damage to bosses.",
						mods = { attack = { damage = 8, range = 10 }, attackSet = { bossMultiplier = 10 } },
					},
				},
			},
		},
	},

	IcePenguin = {
		id = "IcePenguin",
		displayName = "Ice Penguin",
		description = "Freezes every slime in range.",
		cost = 400,
		unlockGoo = 120,
		footprint = 1.75,
		color = { 150, 220, 255 },
		icon = "penguin",
		order = 3,
		rarity = "Rare",
		base = stats({
			attacks = {
				attack({
					kind = "nova",
					range = 9,
					cooldown = 2.5,
					damage = 1,
					pierce = 40,
					freeze = 1.2,
					damageType = "cold",
					visual = "frost",
				}),
			},
		}),
		paths = {
			A = {
				name = "Deep Freeze",
				tiers = {
					{
						name = "Longer Freeze",
						cost = 200,
						description = "Freeze lasts 0.8s longer.",
						mods = { attack = { freeze = 0.8 } },
					},
					{
						name = "Shatter",
						cost = 440,
						description = "Freezing pulses deal +2 damage.",
						mods = { attack = { damage = 2 } },
					},
					{
						name = "Blizzard",
						cost = 970,
						description = "+5 range, pulses 40% faster, +2 damage.",
						mods = { attack = { range = 5, damage = 2, pierce = 40 }, attackMul = { cooldown = 0.6 } },
					},
					{
						name = "Glacier",
						cost = 2130,
						description = "+3 damage, freeze 1s longer, +3 range.",
						mods = { attack = { damage = 3, freeze = 1, range = 3, pierce = 40 } },
					},
					{
						name = "Absolute Zero",
						cost = 4690,
						description = "ULTIMATE: +12 range, +4 damage, pulses 40% faster.",
						mods = { attack = { range = 12, damage = 4, pierce = 80 }, attackMul = { cooldown = 0.6 } },
					},
				},
			},
			B = {
				name = "Chill",
				tiers = {
					{
						name = "Slow Aura",
						cost = 180,
						description = "Slimes in range move 40% slower.",
						mods = { towerSet = { slowAura = 9, slowFactor = 0.6 } },
					},
					{
						name = "Brittle",
						cost = 395,
						description = "Frozen slimes take +1 damage from every hit for 3s.",
						mods = { attack = { brittle = 3 } },
					},
					{
						name = "Permafrost",
						cost = 870,
						description = "Aura slows to 35% speed (even bosses), freeze +1s.",
						mods = { attack = { freeze = 1 }, towerSet = { slowFactor = 0.35, slowBosses = true } },
					},
					{
						name = "Ice Shards",
						cost = 1910,
						description = "Also fires 3 ice shards at once.",
						mods = {
							addAttack = attack({
								range = 14,
								cooldown = 0.6,
								damage = 2,
								pierce = 3,
								projectiles = 3,
								damageType = "cold",
								visual = "orb",
							}),
						},
					},
					{
						name = "Frozen Heart",
						cost = 4200,
						description = "ULTIMATE: aura slows to 20% speed and reaches further; frozen slimes stay brittle longer.",
						mods = {
							attack = { brittle = 3, freeze = 1 },
							tower = { slowAura = 4 },
							towerSet = { slowFactor = 0.2 },
						},
					},
				},
			},
		},
	},

	SpikeTurtle = {
		id = "SpikeTurtle",
		displayName = "Spike Turtle",
		description = "Spinning blades shred slimes up close.",
		cost = 350,
		unlockGoo = 80,
		footprint = 1.75,
		color = { 70, 160, 120 },
		icon = "turtle",
		order = 4,
		rarity = "Common",
		base = stats({
			attacks = {
				attack({
					kind = "nova",
					range = 6,
					cooldown = 0.5,
					damage = 1,
					pierce = 4,
					damageType = "sharp",
					visual = "blades",
				}),
			},
		}),
		paths = {
			A = {
				name = "Spin",
				tiers = {
					{
						name = "Blade Count",
						cost = 160,
						description = "4 more blades.",
						mods = { attack = { pierce = 4 } },
					},
					{
						name = "Sawstorm",
						cost = 350,
						description = "Spins 40% faster with 4 more blades.",
						mods = { attack = { pierce = 4 }, attackMul = { cooldown = 0.6 } },
					},
					{
						name = "Tornado Shell",
						cost = 770,
						description = "+4 range, +2 damage, many more blades.",
						mods = { attack = { range = 4, damage = 2, pierce = 12 } },
					},
					{
						name = "Blade Cyclone",
						cost = 1690,
						description = "16 more blades, spins 30% faster.",
						mods = { attack = { pierce = 16 }, attackMul = { cooldown = 0.7 } },
					},
					{
						name = "Maelstrom Shell",
						cost = 3720,
						description = "ULTIMATE: +5 range, +4 damage, 30 more blades, spins 40% faster.",
						mods = { attack = { range = 5, damage = 4, pierce = 30 }, attackMul = { cooldown = 0.6 } },
					},
				},
			},
			B = {
				name = "Forge",
				tiers = {
					{
						name = "Pierce",
						cost = 150,
						description = "+2 blades and +1 range.",
						mods = { attack = { pierce = 2, range = 1 } },
					},
					{
						name = "Hot Blades",
						cost = 330,
						description = "Glowing blades can pop Metal slimes.",
						mods = { attackSet = { damageType = "fire", visual = "hotblades" } },
					},
					{
						name = "Molten Shell",
						cost = 725,
						description = "+3 damage and 30% faster spin.",
						mods = { attack = { damage = 3 }, attackMul = { cooldown = 0.7 } },
					},
					{
						name = "Lava Blades",
						cost = 1600,
						description = "+3 damage, and hit slimes turn brittle for 2s.",
						mods = { attack = { damage = 3, brittle = 2 } },
					},
					{
						name = "Volcano Shell",
						cost = 3520,
						description = "ULTIMATE: also erupts lava bombs at 2 slimes every 1.5s.",
						mods = {
							addAttack = attack({
								range = 14,
								cooldown = 1.5,
								damage = 6,
								pierce = 30,
								splash = 5,
								projectiles = 2,
								bossMultiplier = 3,
								damageType = "fire",
								visual = "firewall",
							}),
						},
					},
				},
			},
		},
	},

	BankBee = {
		id = "BankBee",
		displayName = "Bank Bee",
		description = "Makes $80 at the end of every round.",
		cost = 1000,
		unlockGoo = 300,
		footprint = 2,
		color = { 255, 200, 40 },
		icon = "bee",
		order = 5,
		rarity = "Mythic",
		base = stats({ income = 80 }),
		paths = {
			A = {
				name = "Honey",
				tiers = {
					{
						name = "More Honey",
						cost = 400,
						description = "+$60 per round.",
						mods = { tower = { income = 60 } },
					},
					{
						name = "Honey Interest",
						cost = 880,
						description = "Also earns 5% of your cash each round (max $300).",
						mods = { towerSet = { interestRate = 0.05, interestCap = 300 } },
					},
					{
						name = "Hive Bank",
						cost = 1935,
						description = "+$400 per round, interest cap $1000.",
						mods = { tower = { income = 400 }, towerSet = { interestCap = 1000 } },
					},
					{
						name = "Golden Comb",
						cost = 4260,
						description = "+$700 per round, 8% interest, interest cap $2000.",
						mods = { tower = { income = 700 }, towerSet = { interestRate = 0.08, interestCap = 2000 } },
					},
					{
						name = "Honey Empire",
						cost = 9370,
						description = "ULTIMATE: +$1600 per round, interest cap $5000.",
						mods = { tower = { income = 1600 }, towerSet = { interestCap = 5000 } },
					},
				},
			},
			B = {
				name = "Colony",
				tiers = {
					{
						name = "Share the Honey",
						cost = 350,
						description = "+$40 per round, and income is split with all teammates.",
						mods = { tower = { income = 40 }, towerSet = { shareIncome = true } },
					},
					{
						name = "Team Bonus",
						cost = 770,
						description = "Every player also gets +$75 per round.",
						mods = { tower = { teamBonus = 75 } },
					},
					{
						name = "Royal Hive",
						cost = 1695,
						description = "+$350 income and +$150 more team bonus.",
						mods = { tower = { income = 350, teamBonus = 150 } },
					},
					{
						name = "Queen's Court",
						cost = 3730,
						description = "+$300 income and +$250 more team bonus.",
						mods = { tower = { income = 300, teamBonus = 250 } },
					},
					{
						name = "Hive Mind",
						cost = 8200,
						description = "ULTIMATE: +$700 income and +$600 more team bonus for everyone.",
						mods = { tower = { income = 700, teamBonus = 600 } },
					},
				},
			},
		},
	},

	WizardOwl = {
		id = "WizardOwl",
		displayName = "Wizard Owl",
		description = "Magic orbs pop any slime type.",
		cost = 450,
		unlockGoo = 200,
		footprint = 1.6,
		color = { 150, 110, 230 },
		icon = "owl",
		order = 6,
		rarity = "Legendary",
		base = stats({
			attacks = {
				attack({ range = 13, cooldown = 1.1, damage = 1, pierce = 3, damageType = "magic", visual = "orb" }),
			},
		}),
		paths = {
			A = {
				name = "Pyromancy",
				tiers = {
					{
						name = "Fire Bolts",
						cost = 250,
						description = "Fire bolts deal +1 damage.",
						mods = { attack = { damage = 1 }, attackSet = { damageType = "fire", visual = "firebolt" } },
					},
					{
						name = "Wall of Fire",
						cost = 550,
						description = "Every 3s, sets the path ablaze.",
						mods = {
							addAttack = attack({
								range = 13,
								cooldown = 3,
								damage = 1,
								pierce = 25,
								splash = 4,
								damageType = "fire",
								visual = "firewall",
							}),
						},
					},
					{
						name = "Phoenix",
						cost = 1210,
						description = "Summons a phoenix that rains fire across the map.",
						mods = {
							addAttack = attack({
								range = 40,
								cooldown = 0.25,
								damage = 2,
								pierce = 4,
								damageType = "fire",
								visual = "phoenix",
							}),
						},
					},
					{
						name = "Inferno Orbs",
						cost = 2660,
						description = "Fire bolts explode: +3 damage, +3 splash, +3 pierce.",
						mods = { attack = { damage = 3, splash = 3, pierce = 3 } },
					},
					{
						name = "Sun God",
						cost = 5850,
						description = "ULTIMATE: calls down a sun that scorches every slime nearby each second.",
						mods = {
							addAttack = attack({
								range = 20,
								cooldown = 1,
								damage = 8,
								pierce = 60,
								splash = 8,
								damageType = "fire",
								visual = "firewall",
							}),
						},
					},
				},
			},
			B = {
				name = "Arcana",
				tiers = {
					{
						name = "Camo Vision",
						cost = 220,
						description = "Sees camo, and nearby towers can too.",
						mods = { towerSet = { camo = true, camoAura = 13 } },
					},
					{
						name = "Arcane Chain",
						cost = 485,
						description = "Orbs jump to 4 more slimes.",
						mods = { attack = { chain = 4 } },
					},
					{
						name = "Archmage",
						cost = 1065,
						description = "+2 damage, double speed, longer chains, +5 range.",
						mods = { attack = { damage = 2, chain = 4, range = 5 }, attackMul = { cooldown = 0.5 } },
					},
					{
						name = "Storm Weaver",
						cost = 2340,
						description = "Orbs jump to 6 more slimes, +2 damage.",
						mods = { attack = { chain = 6, damage = 2 } },
					},
					{
						name = "Grand Archmage",
						cost = 5150,
						description = "ULTIMATE: 3 more orbs, 6 more chain jumps, +4 damage, triple damage to bosses.",
						mods = {
							attack = { projectiles = 3, chain = 6, damage = 4 },
							attackSet = { bossMultiplier = 3 },
						},
					},
				},
			},
		},
	},
}

return TowerData
