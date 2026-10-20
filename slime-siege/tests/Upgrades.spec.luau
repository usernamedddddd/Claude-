--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Upgrades = require(ReplicatedStorage.Shared.Sim.Upgrades)
local TowerData = require(ReplicatedStorage.Shared.Data.TowerData)
local Engine = require(ReplicatedStorage.Shared.Sim.Engine)

return function()
	describe("crosspath rule", function()
		it("allows tier 5 on one path and tier 2 on the other", function()
			expect((Upgrades.canUpgrade({ A = 0, B = 0 }, "A"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 4, B = 2 }, "A"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 5, B = 1 }, "B"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 2, B = 1 }, "B"))).to.equal(true)
		end)

		it("blocks a second path above tier 2", function()
			expect((Upgrades.canUpgrade({ A = 3, B = 2 }, "B"))).to.equal(false)
			expect((Upgrades.canUpgrade({ A = 2, B = 2 }, "B"))).to.equal(true)
			expect((Upgrades.canUpgrade({ A = 2, B = 3 }, "A"))).to.equal(false)
			expect((Upgrades.canUpgrade({ A = 5, B = 2 }, "B"))).to.equal(false)
		end)

		it("blocks going past tier 5", function()
			local ok, reason = Upgrades.canUpgrade({ A = 5, B = 2 }, "A")
			expect(ok).to.equal(false)
			expect(reason).to.equal("Path maxed")
		end)

		it("is enforced by the engine", function()
			local state = Engine.new({ rounds = { {} } })
			Engine.addPlayer(state, 1, 100000)
			local tower = assert(Engine.placeTower(state, 1, "DartFrog", -34, 19))
			for _ = 1, 3 do
				expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			end
			expect((Engine.upgradeTower(state, 1, tower.uid, "B"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "B"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "B"))).to.equal(false)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(true)
			expect((Engine.upgradeTower(state, 1, tower.uid, "A"))).to.equal(false)
			expect(tower.tiers.A).to.equal(5)
			expect(tower.tiers.B).to.equal(2)
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
		it("has exactly 6 towers with two 5-tier paths", function()
			local count = 0
			for _, def in TowerData do
				count += 1
				expect(#def.paths.A.tiers).to.equal(Upgrades.MAX_TIER)
				expect(#def.paths.B.tiers).to.equal(Upgrades.MAX_TIER)
			end
			expect(count).to.equal(6)
		end)

		it("scales tier costs by about 2.2x", function()
			for _, def in TowerData do
				for _, path in { def.paths.A, def.paths.B } do
					for i = 2, Upgrades.MAX_TIER do
						local ratio = path.tiers[i].cost / path.tiers[i - 1].cost
						expect(ratio > 2.0 and ratio < 2.4).to.equal(true)
					end
				end
			end
		end)

		it("every upgrade on every path improves the tower", function()
			-- Each tier must change at least one stat (no dead upgrades), and stats must stay sane.
			for _, def in TowerData do
				for _, key: Upgrades.PathKey in { "A", "B" } :: { Upgrades.PathKey } do
					for tier = 1, Upgrades.MAX_TIER do
						local before = Upgrades.computeStats(
							def,
							{ A = if key == "A" then tier - 1 else 0, B = if key == "B" then tier - 1 else 0 }
						)
						local after = Upgrades.computeStats(
							def,
							{ A = if key == "A" then tier else 0, B = if key == "B" then tier else 0 }
						)
						local changed = #after.attacks ~= #before.attacks
						for field, v in after :: any do
							if field ~= "attacks" and (before :: any)[field] ~= v then
								changed = true
							end
						end
						for i, attack in after.attacks do
							local old = before.attacks[i] :: any
							for field, v in attack :: any do
								if old and old[field] ~= v then
									changed = true
								end
								if type(v) == "number" then
									expect(v == v and v >= 0).to.equal(true)
								end
							end
							expect(attack.cooldown > 0.05).to.equal(true)
						end
						expect(changed).to.equal(true)
					end
				end
			end
		end)

		it("ultimates are reachable with the crosspath rule", function()
			for _, def in TowerData do
				local stats = Upgrades.computeStats(def, { A = 5, B = 2 })
				expect(stats ~= nil).to.equal(true)
				expect(Upgrades.totalCost(def, { A = 5, B = 2 }) > Upgrades.totalCost(def, { A = 3, B = 1 })).to.equal(
					true
				)
			end
		end)
	end)
end
