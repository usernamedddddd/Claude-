--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Shared.Net.Packet)
local Rewards = require(ReplicatedStorage.Shared.Sim.Rewards)
local Config = require(ReplicatedStorage.Shared.Data.Config)

return function()
	describe("snapshot packet", function()
		it("round-trips events and enemy positions", function()
			local events: { { [string]: any } } = {
				{ t = "spawn", id = 70000, slime = "Rainbow", camo = true, distance = 12.5 },
				{ t = "pop", id = 5, tower = 3 },
				{ t = "leak", id = 9 },
				{ t = "attack", tower = 2, visual = "bomb", x = -40.25, z = 18.5 },
				{ t = "chain", x1 = 1, z1 = 2, x2 = -3, z2 = 4 },
				{ t = "roundStart", round = 4 }, -- not a render event: skipped
				{ t = "clear" },
			}
			local enemies = {
				{ id = 1, distance = 100.5, frozen = 0.5, stunned = 0, slow = 1 },
				{ id = 2, distance = 0, frozen = 0, stunned = 0, slow = 0.6 },
			}
			local buf = Packet.encodeSnapshot(events, enemies)
			local outEvents, outEnemies = {}, {}
			Packet.decodeSnapshot(buf, outEvents, outEnemies)
			expect(#outEvents).to.equal(6)
			expect(outEvents[1].id).to.equal(70000)
			expect(outEvents[1].kind).to.equal("Rainbow")
			expect(outEvents[1].camo).to.equal(true)
			expect(outEvents[1].distance).to.equal(12.5)
			expect(outEvents[2].tower).to.equal(3)
			expect(outEvents[4].visual).to.equal("bomb")
			expect(outEvents[4].x).to.be.near(-40.25)
			expect(outEvents[5].x2).to.be.near(-3)
			expect(outEvents[6].t).to.equal(Packet.CLEAR)
			expect(#outEnemies).to.equal(2)
			expect(outEnemies[1].distance).to.equal(100.5)
			expect(outEnemies[1].flags).to.equal(1)
			expect(outEnemies[2].flags).to.equal(2)
		end)

		it("stays small for 300 slimes", function()
			local enemies = {}
			for i = 1, 300 do
				table.insert(enemies, { id = i, distance = i, frozen = 0, stunned = 0, slow = 1 })
			end
			local buf = Packet.encodeSnapshot({}, enemies)
			expect(buffer.len(buf)).to.equal(4 + 300 * 7)
		end)

		it("survives garbage input", function()
			local outEvents, outEnemies = {}, {}
			local junk = buffer.create(16)
			buffer.writeu16(junk, 0, 3)
			buffer.writeu8(junk, 2, 200)
			Packet.decodeSnapshot(junk, outEvents, outEnemies)
			expect(#outEnemies).to.equal(0)
		end)
	end)

	describe("match rewards", function()
		it("pays Goo and XP per cleared round plus a win bonus", function()
			local lose = Rewards.compute(15, false, false)
			expect(lose.roundsCleared).to.equal(14)
			expect(lose.goo).to.equal(14 * Config.GOO_PER_ROUND)
			local win = Rewards.compute(40, true, false)
			expect(win.goo).to.equal(40 * Config.GOO_PER_ROUND + Config.GOO_WIN_BONUS)
			expect(win.xp).to.equal(40 * Config.XP_PER_ROUND + Config.XP_WIN_BONUS)
		end)

		it("doubles Goo (not XP) with the 2x Goo pass", function()
			local normal = Rewards.compute(10, false, false)
			local doubled = Rewards.compute(10, false, true)
			expect(doubled.goo).to.equal(normal.goo * 2)
			expect(doubled.xp).to.equal(normal.xp)
		end)
	end)
end
