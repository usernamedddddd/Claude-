--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = require(ReplicatedStorage.Shared.Sim.Engine)
local Config = require(ReplicatedStorage.Shared.Data.Config)

local function hit(damage: number, damageType: any?): Engine.HitSpec
	return { damage = damage, damageType = damageType or "magic", bossMultiplier = 1, freeze = 0, stun = 0, brittle = 0 }
end

local function newState(): Engine.State
	local state = Engine.new({ rounds = { {} } })
	Engine.addPlayer(state, 1)
	return state
end

local function aliveKinds(state: Engine.State): { [string]: number }
	local counts: { [string]: number } = {}
	for _, e in state.enemies do
		if e.alive then
			counts[e.kind] = (counts[e.kind] or 0) + 1
		end
	end
	return counts
end

return function()
	describe("slime layer splitting", function()
		it("pops a Green into nothing", function()
			local state = newState()
			local green = Engine.spawnSlime(state, "Green", false, 50)
			expect(Engine.damage(state, green, hit(1))).to.equal(1)
			expect(green.alive).to.equal(false)
			expect((next(aliveKinds(state)))).to.equal(nil)
		end)

		it("turns a Blue into a Green at the same path position", function()
			local state = newState()
			local blue = Engine.spawnSlime(state, "Blue", false, 80)
			Engine.damage(state, blue, hit(1))
			local kinds = aliveKinds(state)
			expect(kinds.Green).to.equal(1)
			expect(kinds.Blue).to.equal(nil)
			local child = state.enemies[#state.enemies]
			expect(child.distance).to.equal(80)
		end)

		it("splits a Rainbow into 2 Black and 2 Metal", function()
			local state = newState()
			Engine.damage(state, Engine.spawnSlime(state, "Rainbow", false, 100), hit(1))
			local kinds = aliveKinds(state)
			expect(kinds.Black).to.equal(2)
			expect(kinds.Metal).to.equal(2)
		end)

		it("spreads siblings slightly behind each other but never before the start", function()
			local state = newState()
			Engine.damage(state, Engine.spawnSlime(state, "Black", false, 0.1), hit(1))
			for _, e in state.enemies do
				if e.alive then
					expect(e.distance >= 0).to.equal(true)
				end
			end
			local state2 = newState()
			Engine.damage(state2, Engine.spawnSlime(state2, "Black", false, 50), hit(1))
			local d = {}
			for _, e in state2.enemies do
				if e.alive then
					table.insert(d, e.distance)
				end
			end
			table.sort(d)
			expect(d[2] - d[1]).to.be.near(Config.CHILD_SPREAD)
		end)

		it("carries extra damage into the next layer", function()
			local state = newState()
			local pink = Engine.spawnSlime(state, "Pink", false, 10)
			-- Pink -> Yellow -> Blue -> Green: 3 damage leaves a Green.
			expect(Engine.damage(state, pink, hit(3))).to.equal(3)
			local kinds = aliveKinds(state)
			expect(kinds.Green).to.equal(1)
			expect(kinds.Pink).to.equal(nil)
		end)

		it("keeps camo on children", function()
			local state = newState()
			Engine.damage(state, Engine.spawnSlime(state, "Yellow", true, 10), hit(1))
			local child = state.enemies[#state.enemies]
			expect(child.kind).to.equal("Blue")
			expect(child.camo).to.equal(true)
		end)

		it("needs 200 damage to pop a Big Boss Slime, which releases 4 Rainbows", function()
			local state = newState()
			local boss = Engine.spawnSlime(state, "Boss", false, 30)
			expect(Engine.damage(state, boss, hit(199))).to.equal(0)
			expect(boss.alive).to.equal(true)
			expect(boss.hp).to.equal(1)
			expect(Engine.damage(state, boss, hit(1))).to.equal(1)
			expect(aliveKinds(state).Rainbow).to.equal(4)
		end)

		it("costs lives equal to the remaining layers when a slime leaks", function()
			local state = Engine.new({ rounds = { {} } })
			Engine.spawnSlime(state, "Pink", false, state.path.totalLength - 0.01)
			Engine.step(state, 0.1)
			expect(state.lives).to.equal(Config.STARTING_LIVES - 4)
		end)
	end)
end
