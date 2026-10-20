--!strict
-- `lune run tools/simulate [toRound]` — plays the reference defense (tests/ReferenceDefense)
-- through the rounds with the real engine and prints a per-round report.

local process = require("@lune/process")
local Loader = require("./lib/Loader")

local env = Loader.load(process.cwd)
local Simulator = env.require(Loader.find(env, "ServerStorage.Content.Simulator"))
local Rounds = env.require(Loader.find(env, "ReplicatedStorage.Shared.Data.Rounds"))
local ReferenceDefense = env.require(Loader.find(env, "ServerStorage.Tests.ReferenceDefense"))

local toRound = tonumber(process.args[1]) or 40
local started = os.clock()
local report = Simulator.run({ rounds = Rounds, defense = ReferenceDefense.actions, toRound = toRound })
print(Simulator.format(report))
print(string.format("simulated in %.2fs", os.clock() - started))
