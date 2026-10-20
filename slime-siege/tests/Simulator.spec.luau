--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Simulator = require(ServerStorage.Content.Simulator)
local ReferenceDefense = require(ServerStorage.Tests.ReferenceDefense)
local Rounds = require(ReplicatedStorage.Shared.Data.Rounds)

return function()
	describe("headless simulator", function()
		it("reference defense beats rounds 1-20 with zero leaks", function()
			local report = Simulator.run({
				rounds = Rounds,
				defense = ReferenceDefense.actions,
				toRound = ReferenceDefense.MUST_CLEAR_ROUND,
			})
			expect(#report.errors).to.equal(0)
			expect(report.result).to.equal("won")
			expect(#report.rounds).to.equal(ReferenceDefense.MUST_CLEAR_ROUND)
			for _, r in report.rounds do
				if r.leaks ~= 0 then
					error(`round {r.round} leaked {r.leaks} slimes`)
				end
				expect(r.pops > 0).to.equal(true)
				expect(r.cashEarned > 0).to.equal(true)
			end
		end)

		it("reports pops, leaks and cash for a single round against a fixed setup", function()
			local empty = Simulator.runRound(Rounds, 1, {})
			expect(empty.pops).to.equal(0)
			expect(empty.leaks).to.equal(20)
			expect(empty.leakedLayers).to.equal(20)

			local defended = Simulator.runRound(Rounds, 1, {
				{ round = 1, place = "DartFrog", x = -70, z = -24, name = "a" },
				{ round = 1, place = "DartFrog", x = -34, z = 19, name = "b" },
			})
			expect(defended.leaks).to.equal(0)
			expect(defended.pops).to.equal(20)
		end)

		it("is deterministic", function()
			local a = Simulator.run({ rounds = Rounds, defense = ReferenceDefense.actions, toRound = 8 })
			local b = Simulator.run({ rounds = Rounds, defense = ReferenceDefense.actions, toRound = 8 })
			for i, r in a.rounds do
				expect(b.rounds[i].pops).to.equal(r.pops)
				expect(b.rounds[i].cashAfter).to.equal(r.cashAfter)
			end
		end)
	end)
end
