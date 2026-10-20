--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BadgeData = require(ReplicatedStorage.Shared.Data.BadgeData)
local Badges = require(ReplicatedStorage.Shared.Sim.Badges)
local Config = require(ReplicatedStorage.Shared.Data.Config)
local TowerData = require(ReplicatedStorage.Shared.Data.TowerData)

-- Theme needs Color3 (not available headless), so mirror the keys the UI provides.
local ICONS = {
	trophy = true,
	star = true,
	skull = true,
	heart = true,
	goo = true,
	frog = true,
	fast = true,
	towers = true,
	target = true,
}
local TINTS = { gold = true, blue = true, red = true, green = true, purple = true }
local RARITIES = { Common = true, Rare = true, Epic = true, Legendary = true, Mythic = true }

local function profile(stats: { [string]: number }?, xp: number?): Badges.ProfileLike
	return { xp = xp or 0, unlocked = { DartFrog = true }, stats = stats or {}, badges = {} }
end

return function()
	describe("catalog", function()
		it("has 16 badges with unique ids, positive goals and rewards, and known icons/tints", function()
			expect(#BadgeData.list).to.equal(16)
			local seen = {}
			for _, def in BadgeData.list do
				expect(seen[def.id]).to.equal(nil)
				seen[def.id] = true
				expect(def.goal > 0).to.equal(true)
				expect(def.reward > 0).to.equal(true)
				expect(ICONS[def.icon]).to.equal(true)
				expect(TINTS[def.tint]).to.equal(true)
				expect(BadgeData.byId[def.id]).to.equal(def)
			end
		end)

		it("Collector's goal matches the number of towers", function()
			local count = 0
			for _ in TowerData do
				count += 1
			end
			expect(BadgeData.byId.Collector.goal).to.equal(count)
		end)
	end)

	describe("rules", function()
		it("a fresh profile has earned nothing", function()
			expect(#Badges.newlyEarned(profile())).to.equal(0)
		end)

		it("earns from stats, level and unlocks", function()
			local p = profile({ matches = 1, bestRound = 12, totalPops = 1500 }, Config.XP_PER_LEVEL * 4)
			local ids = {}
			for _, def in Badges.newlyEarned(p) do
				ids[def.id] = true
			end
			expect(ids.FirstSteps).to.equal(true)
			expect(ids.Wave10).to.equal(true)
			expect(ids.Pop1K).to.equal(true)
			expect(ids.Level5).to.equal(true) -- xp 4 levels in = level 5
			expect(ids.Halfway).to.equal(nil)
			expect(ids.Pop10K).to.equal(nil)
			expect(ids.Level10).to.equal(nil)
		end)

		it("never re-reports badges already earned", function()
			local p = profile({ matches = 3 })
			p.badges.FirstSteps = false
			for _, def in Badges.newlyEarned(p) do
				expect(def.id ~= "FirstSteps").to.equal(true)
			end
		end)

		it("reports progress clamped to the goal", function()
			local facts = Badges.facts(profile({ totalPops = 250 }))
			local current, goal = Badges.progress(BadgeData.byId.Pop1K, facts)
			expect(current).to.equal(250)
			expect(goal).to.equal(1000)
			facts = Badges.facts(profile({ totalPops = 5000 }))
			current = Badges.progress(BadgeData.byId.Pop1K, facts)
			expect(current).to.equal(1000)
		end)

		it("tracks locked -> claimable -> claimed", function()
			local p = profile()
			expect(Badges.status(p, "Champion")).to.equal("locked")
			p.badges.Champion = false
			expect(Badges.status(p, "Champion")).to.equal("claimable")
			p.badges.Champion = true
			expect(Badges.status(p, "Champion")).to.equal("claimed")
			p.badges.NotABadge = true
			expect(Badges.earnedCount(p.badges)).to.equal(1)
		end)

		it("counts all unlocked towers for Collector", function()
			local p = profile()
			for id in TowerData do
				p.unlocked[id] = true
			end
			local ids = {}
			for _, def in Badges.newlyEarned(p) do
				ids[def.id] = true
			end
			expect(ids.Collector).to.equal(true)
		end)
	end)

	describe("shop data", function()
		it("every tower has a rarity with a shop colour", function()
			for _, def in TowerData do
				expect(RARITIES[def.rarity]).to.equal(true)
			end
		end)
	end)
end
