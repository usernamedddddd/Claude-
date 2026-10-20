--!strict
-- Upgrade rules: crosspath limit, upgrade costs, sell refunds and effective stat calculation.

local Config = require(script.Parent.Parent.Data.Config)
local TowerData = require(script.Parent.Parent.Data.TowerData)

export type PathKey = "A" | "B"
export type Tiers = { A: number, B: number }

local MAX_TIER = 5
local MAX_OTHER_TIER = 2

local Upgrades = {}

Upgrades.MAX_TIER = MAX_TIER
Upgrades.MAX_OTHER_TIER = MAX_OTHER_TIER

function Upgrades.otherPath(path: PathKey): PathKey
	return if path == "A" then "B" else "A"
end

-- Crosspath rule: up to tier 5 on one path and tier 2 on the other.
function Upgrades.canUpgrade(tiers: Tiers, path: PathKey): (boolean, string?)
	local current = tiers[path]
	local other = tiers[Upgrades.otherPath(path)]
	if current >= MAX_TIER then
		return false, "Path maxed"
	end
	local nextTier = current + 1
	if nextTier > MAX_OTHER_TIER and other > MAX_OTHER_TIER then
		return false, `Other path is above tier {MAX_OTHER_TIER}`
	end
	return true, nil
end

function Upgrades.nextTier(def: TowerData.TowerDef, tiers: Tiers, path: PathKey): TowerData.Tier?
	local ok = Upgrades.canUpgrade(tiers, path)
	if not ok then
		return nil
	end
	return def.paths[path].tiers[tiers[path] + 1]
end

function Upgrades.sellValue(totalSpent: number): number
	return math.floor(totalSpent * Config.SELL_REFUND)
end

local function copyAttack(a: TowerData.AttackSpec): TowerData.AttackSpec
	return table.clone(a)
end

local function copyStats(s: TowerData.TowerStats): TowerData.TowerStats
	local out = table.clone(s)
	out.attacks = {}
	for i, a in s.attacks do
		out.attacks[i] = copyAttack(a)
	end
	return out
end

local function applyMods(stats: TowerData.TowerStats, mods: TowerData.Mods)
	local primary = stats.attacks[1] :: any
	if mods.attack and primary then
		for field, n in mods.attack do
			primary[field] += n
		end
	end
	if mods.attackMul and primary then
		for field, n in mods.attackMul do
			primary[field] *= n
		end
	end
	if mods.attackSet and primary then
		for field, v in mods.attackSet do
			primary[field] = v
		end
	end
	local towerFields = stats :: any
	if mods.tower then
		for field, n in mods.tower do
			towerFields[field] += n
		end
	end
	if mods.towerSet then
		for field, v in mods.towerSet do
			towerFields[field] = v
		end
	end
	if mods.addAttack then
		table.insert(stats.attacks, copyAttack(mods.addAttack))
	end
end

function Upgrades.computeStats(def: TowerData.TowerDef, tiers: Tiers): TowerData.TowerStats
	local stats = copyStats(def.base)
	for _, path: PathKey in { "A", "B" } :: { PathKey } do
		local tierList = def.paths[path].tiers
		for i = 1, tiers[path] do
			applyMods(stats, tierList[i].mods)
		end
	end
	return stats
end

-- Total cost of a tower bought fresh at the given tiers (used by tests and the simulator).
function Upgrades.totalCost(def: TowerData.TowerDef, tiers: Tiers): number
	local total = def.cost
	for _, path: PathKey in { "A", "B" } :: { PathKey } do
		for i = 1, tiers[path] do
			total += def.paths[path].tiers[i].cost
		end
	end
	return total
end

return Upgrades
