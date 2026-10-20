--!strict
-- `lune run tools/generate_rounds` — regenerates src/shared/Data/Rounds.luau and prints the
-- difficulty curve. Exits non-zero if the curve breaks the pipeline rules.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("./lib/Loader")

local env = Loader.load(process.cwd)
local RoundGenerator = env.require(Loader.find(env, "ServerStorage.Content.RoundGenerator"))
local Difficulty = env.require(Loader.find(env, "ReplicatedStorage.Shared.Sim.Difficulty"))

local rounds = RoundGenerator.generate()
fs.writeFile("src/shared/Data/Rounds.luau", RoundGenerator.toLuau(rounds))

local ok = #rounds == 40
local previous = 0
print("round  difficulty  growth  layers  avgSpeed  spacing  groups")
for r, groups in rounds do
	local layers, avgSpeed, avgSpacing = Difficulty.breakdown(groups)
	local d = Difficulty.metric(groups)
	local growth = if previous > 0 then d / previous else 1
	if r > 1 and (d <= previous or growth > 1.3) then
		ok = false
	end
	local names = {}
	for _, g in groups do
		table.insert(names, `{g.count}x{g.slimeType}{if g.camo then "(camo)" else ""}`)
	end
	print(
		string.format(
			"%5d %11.1f %7.3f %7d %9.2f %8.3f  %s",
			r,
			d,
			growth,
			layers,
			avgSpeed,
			avgSpacing,
			table.concat(names, " ")
		)
	)
	previous = d
end
print(if ok then "OK: 40 rounds, strictly rising, max step <= 30%" else "FAILED pipeline rules")
process.exit(if ok then 0 else 1)
