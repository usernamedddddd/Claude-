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
-- Crosspath rule (see Sim/Upgrades): up to tier 3 on one path and tier 1 on the other.

local SlimeData = require(script.Parent.SlimeData)

export type DamageType = SlimeData.DamageType
export type AttackKind = "projectile" | "nova"
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
				},
			},
		},
	},
}

return TowerData
