--!strict
-- Headless test runner: `lune run tools/test` from the project root.
-- Runs every *.spec module in ServerStorage.Tests with the TestEZ-compatible runner.

local process = require("@lune/process")
local Loader = require("./lib/Loader")
local TestEZLite = require("./lib/TestEZLite")

local env = Loader.load(process.cwd)
TestEZLite.install(env.extraGlobals)

local filter = process.args[1]
local specs = {}
for _, inst in Loader.find(env, "ServerStorage.Tests"):GetDescendants() do
	local name: string = inst.Name
	if string.sub(name, -5) == ".spec" and (filter == nil or string.find(name, filter, 1, true)) then
		table.insert(specs, { name = name, fn = env.require(inst) })
	end
end

local result = TestEZLite.run(specs)
print(`\n{result.passed} passed, {result.failed} failed`)
for _, failure in result.failures do
	print("FAIL " .. failure)
end
process.exit(if result.failed == 0 and result.passed > 0 then 0 else 1)
