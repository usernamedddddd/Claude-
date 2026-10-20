--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RoundGenerator = require(ServerStorage.Content.RoundGenerator)
local Difficulty = require(ReplicatedStorage.Shared.Sim.Difficulty)
local Rounds = require(ReplicatedStorage.Shared.Data.Rounds)
local SlimeData = require(ReplicatedStorage.Shared.Data.SlimeData)

return function()
	describe("round generator", function()
		local rounds = RoundGenerator.generate()

		it("produces 40 rounds", function()
			expect(#rounds).to.equal(40)
		end)

		it("only uses known slimes with sane counts and spacing", function()
			for _, groups in rounds do
				expect(#groups > 0).to.equal(true)
				for _, g in groups do
					expect(SlimeData[g.slimeType]).to.be.ok()
					expect(g.count >= 1 and g.count == math.floor(g.count)).to.equal(true)
					expect(g.spacingSeconds > 0).to.equal(true)
					expect(g.delay >= 0).to.equal(true)
				end
			end
		end)

		it("raises difficulty every round, never by more than 30%", function()
			for r = 2, #rounds do
				local prev = Difficulty.metric(rounds[r - 1])
				local cur = Difficulty.metric(rounds[r])
				expect(cur > prev).to.equal(true)
				expect(cur / prev <= 1.3).to.equal(true)
			end
		end)

		it("puts the Big Boss Slime in rounds 20 and 40 only", function()
			for r, groups in rounds do
				local hasBoss = false
				for _, g in groups do
					if g.slimeType == "Boss" then
						hasBoss = true
					end
				end
				expect(hasBoss).to.equal(r == 20 or r == 40)
			end
		end)

		it("matches the exported Rounds module (run tools/generate_rounds after edits)", function()
			expect(#Rounds).to.equal(#rounds)
			for r, groups in rounds do
				expect(#Rounds[r]).to.equal(#groups)
				for i, g in groups do
					local exported = Rounds[r][i]
					expect(exported.slimeType).to.equal(g.slimeType)
					expect(exported.count).to.equal(g.count)
					expect(exported.spacingSeconds).to.be.near(g.spacingSeconds, 1e-6)
					expect(exported.delay).to.be.near(g.delay, 1e-6)
					expect(exported.camo == true).to.equal(g.camo == true)
				end
			end
		end)
	end)

	describe("difficulty metric", function()
		it("is total layers x average speed / spacing", function()
			local metric = Difficulty.metric({ { slimeType = "Blue", count = 10, spacingSeconds = 0.5, delay = 0 } })
			expect(metric).to.be.near(20 * 10 / 0.5)
		end)
	end)
end
