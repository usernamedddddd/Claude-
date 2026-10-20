--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Upgrades = require(ReplicatedStorage.Shared.Sim.Upgrades)
local TowerData = require(ReplicatedStorage.Shared.Data.TowerData)
local Engine = require(ReplicatedStorage.Shared.Sim.Engine)

return function()
	describe("crosspath rule", function()
		it("allows tier 3 on one path and tier 1 on the other", function()
			expect((Upgrades.canUpgrade({ A = 0, B = 0 }, "A"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 2, B = 1 }, "A"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 3, B = 0 }, "B"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 1, B = 0 }, "B"))).to.equal(true)
		end)

		it("blocks a second path above tier 1", function()
			expect((Upgrades.canUpgrade({ A = 2, B = 1 }, "B"))).to.equal(false)
			expect((Upgrades.canUpgrade({ A = 1, B = 1 }, "B"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 1, B = 2 }, "A"))).to.equal(false)
			expect((Upgrades.canUpgrade({ A = 3, B = 1 }, "B"))).to.equal(false)
		end)

		it("blocks going past tier 3", function()
			local ok, reason = Upgrades.canUpgrade({ A = 3, B = 1 }, "A")
			expect(ok).to.equal(false)
			expect(reason).to.equal("Path maxed")
		end)

		it("is enforced by the engine", function()
			local state = Engine.new({ rounds = { {} } })
			Engine.addPlayer(state, 1, 100000)
			local tower = assert(Engine.placeTower(state, 1, "DartFrog", -34, 19))
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "B"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "B"))).to.equal(false)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(false)
			expect(tower.tiers.A).to.equal(3)
			expect(tower.tiers.B).to.equal(1)
		end)
	end)

	describe("upgrade stats", function()
		it("applies additive, multiplicative and set mods", function()
			local def = TowerData.DartFrog
			local base = Upgrades.computeStats(def, { A = 0, B = 0 })
			local a3 = Upgrades.computeStats(def, { A = 3, B = 1 })
			expect(a3.attacks[1].pierce).to.equal(base.attacks[1].pierce + 4)
			expect(a3.attacks[1].cooldown).to.be.near(base.attacks[1].cooldown * 0.35)
			expect(a3.attacks[1].projectiles).to.equal(3)
			expect(a3.camo).to.equal(true)
			expect(base.camo).to.equal(false)
		end)

		it("never mutates the base data", function()
			local before = TowerData.WizardOwl.base.attacks[1].damage
			Upgrades.computeStats(TowerData.WizardOwl, { A = 3, B = 1 })
			expect(TowerData.WizardOwl.base.attacks[1].damage).to.equal(before)
			expect(#TowerData.WizardOwl.base.attacks).to.equal(1)
		end)

		it("adds secondary attacks", function()
			local stats = Upgrades.computeStats(TowerData.WizardOwl, { A = 3, B = 0 })
			expect(#stats.attacks).to.equal(3)
		end)
	end)

	describe("tower data", function()
		it("has exactly 6 towers with two 3-tier paths", function()
			local count = 0
			for _, def in TowerData do
				count += 1
				expect(#def.paths.A.tiers).to.equal(3)
				expect(#def.paths.B.tiers).to.equal(3)
			end
			expect(count).to.equal(6)
		end)

		it("scales tier costs by about 2.2x", function()
			for _, def in TowerData do
				for _, path in { def.paths.A, def.paths.B } do
					for i = 2, 3 do
						local ratio = path.tiers[i].cost / path.tiers[i - 1].cost
						expect(ratio > 2.0 and ratio < 2.4).to.equal(true)
					end
				end
			end
		end)
	end)
end
