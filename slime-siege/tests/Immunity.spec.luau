--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = require(ReplicatedStorage.Shared.Sim.Engine)
local SlimeData = require(ReplicatedStorage.Shared.Data.SlimeData)

local function hit(damageType: any): Engine.HitSpec
	return { damage = 1, damageType = damageType, bossMultiplier = 1, freeze = 0, stun = 0, brittle = 0 }
end

local function popsFor(kind: string, damageType: string): number
	local state = Engine.new({ rounds = { {} } })
	return Engine.damage(state, Engine.spawnSlime(state, kind, false, 20), hit(damageType))
end

return function()
	describe("damage immunities", function()
		it("Black slimes ignore explosions", function()
			expect(Engine.isImmune(SlimeData.Black, "explosive")).to.equal(true)
			expect(popsFor("Black", "explosive")).to.equal(0)
			expect(popsFor("Black", "sharp")).to.equal(1)
		end)

		it("Metal slimes ignore sharp darts and blades", function()
			expect(Engine.isImmune(SlimeData.Metal, "sharp")).to.equal(true)
			expect(popsFor("Metal", "sharp")).to.equal(0)
			expect(popsFor("Metal", "explosive")).to.equal(1)
		end)

		it("hot blades (fire) and magic pop Metal", function()
			expect(popsFor("Metal", "fire")).to.equal(1)
			expect(popsFor("Metal", "magic")).to.equal(1)
		end)

		it("non-armored slimes take every damage type", function()
			for _, damageType in { "sharp", "explosive", "cold", "magic", "fire" } do
				expect(popsFor("Pink", damageType)).to.equal(1)
			end
		end)

		it("stops overflow damage at an immune child layer", function()
			-- A Rainbow hit by 3 explosive damage: the Rainbow pops, but its first child is a
			-- Black, which is immune, so the remaining damage is lost.
			local state = Engine.new({ rounds = { {} } })
			local rainbow = Engine.spawnSlime(state, "Rainbow", false, 20)
			local h = hit("explosive")
			h.damage = 3
			expect(Engine.damage(state, rainbow, h)).to.equal(1)
		end)

		it("camo slimes are invisible to towers without detection", function()
			local state = Engine.new({ rounds = { {} } })
			Engine.addPlayer(state, 1, 10000)
			local tower = assert(Engine.placeTower(state, 1, "DartFrog", -34, 19))
			local enemy = Engine.spawnSlime(state, "Green", true, 75)
			for _ = 1, 60 do
				Engine.step(state, 1 / 30)
			end
			expect(enemy.alive).to.equal(true)
			Engine.upgradeTower(state, 1, tower.uid, "B") -- Range + Camo
			expect(tower.seesCamo).to.equal(true)
			for _ = 1, 60 do
				Engine.step(state, 1 / 30)
			end
			expect(enemy.alive).to.equal(false)
		end)
	end)
end
