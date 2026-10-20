--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = require(ReplicatedStorage.Shared.Sim.Engine)
local Upgrades = require(ReplicatedStorage.Shared.Sim.Upgrades)
local Config = require(ReplicatedStorage.Shared.Data.Config)
local TowerData = require(ReplicatedStorage.Shared.Data.TowerData)

local ONE_GREEN = { { { slimeType = "Green", count = 1, spacingSeconds = 1, delay = 0 } } }

local function runRound(state: Engine.State)
	Engine.startRound(state)
	local guard = 0
	while state.phase == "wave" and guard < 100000 do
		Engine.step(state, 1 / 30)
		guard += 1
	end
end

return function()
	describe("sell refunds", function()
		it("refunds 70% of everything spent, rounded down", function()
			expect(Upgrades.sellValue(200)).to.equal(140)
			expect(Upgrades.sellValue(345)).to.equal(241)
			expect(Upgrades.sellValue(0)).to.equal(0)
		end)

		it("counts upgrades in the refund", function()
			local state = Engine.new({ rounds = ONE_GREEN })
			local player = Engine.addPlayer(state, 1, 1000)
			local tower = assert(Engine.placeTower(state, 1, "DartFrog", -34, 19))
			Engine.upgradeTower(state, 1, tower.uid, "A")
			local spent = TowerData.DartFrog.cost + TowerData.DartFrog.paths.A.tiers[1].cost
			expect(player.cash).to.equal(1000 - spent)
			local refund = Engine.sellTower(state, 1, tower.uid)
			expect(refund).to.equal(math.floor(spent * 0.7))
			expect(player.cash).to.equal(1000 - spent + math.floor(spent * 0.7))
			expect(#state.towers).to.equal(0)
		end)

		it("won't sell another player's tower", function()
			local state = Engine.new({ rounds = ONE_GREEN })
			Engine.addPlayer(state, 1)
			Engine.addPlayer(state, 2)
			local tower = assert(Engine.placeTower(state, 1, "DartFrog", -34, 19))
			expect((Engine.sellTower(state, 2, tower.uid))).to.equal(nil)
		end)
	end)

	describe("cash", function()
		it("starts every player at $650", function()
			local state = Engine.new({ rounds = ONE_GREEN })
			expect(Engine.addPlayer(state, 1).cash).to.equal(650)
		end)

		it("rejects towers the player can't afford", function()
			local state = Engine.new({ rounds = ONE_GREEN })
			Engine.addPlayer(state, 1, 100)
			local tower, err = Engine.placeTower(state, 1, "DartFrog", -34, 19)
			expect(tower).to.equal(nil)
			expect(err).to.equal("Not enough cash")
		end)

		it("pays $1 per layer to the popping tower's owner and the round bonus to everyone", function()
			local state = Engine.new({ rounds = ONE_GREEN })
			local p1 = Engine.addPlayer(state, 1)
			local p2 = Engine.addPlayer(state, 2)
			-- Put the frog right next to the start so the green is popped.
			assert(Engine.placeTower(state, 1, "DartFrog", -70, -24))
			local p1Before, p2Before = p1.cash, p2.cash
			runRound(state)
			expect(state.stats.pops).to.equal(1)
			local bonus = Config.ROUND_BONUS_BASE + 1
			expect(p1.cash).to.equal(p1Before + 1 + bonus)
			expect(p2.cash).to.equal(p2Before + bonus)
		end)

		it("Bank Bee pays its owner each round, and shares only with path B", function()
			local state = Engine.new({ rounds = { {}, {} } })
			local p1 = Engine.addPlayer(state, 1, 5000)
			local p2 = Engine.addPlayer(state, 2, 0)
			local bee = assert(Engine.placeTower(state, 1, "BankBee", -60, 30))
			local before1 = p1.cash
			runRound(state)
			expect(p1.cash).to.equal(before1 + Config.ROUND_BONUS_BASE + 1 + 80)
			expect(p2.cash).to.equal(Config.ROUND_BONUS_BASE + 1)

			Engine.upgradeTower(state, 1, bee.uid, "B") -- share, +$40
			local mid1, mid2 = p1.cash, p2.cash
			runRound(state)
			local share = math.floor(120 / 2)
			expect(p1.cash).to.equal(mid1 + Config.ROUND_BONUS_BASE + 2 + share)
			expect(p2.cash).to.equal(mid2 + Config.ROUND_BONUS_BASE + 2 + share)
		end)
	end)
end
