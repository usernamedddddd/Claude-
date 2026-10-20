--!nocheck
-- `lune run tools/smoke [scenario]` — boots the built place in the emulator (tools/emu) and
-- plays scripted sessions through the real server Script and client LocalScript:
--   solo   one player: UI placement, upgrade panel, auto-start, boss rounds, win, Studio reset
--   fuzz   garbage arguments to every remote must never error or change state
--   coop   four players: separate cash, majority votes, ownership, a player leaving
--   data   live-mode saving: session lock, rejoin, locked profile, DataStore outage
--   lobby  live-mode lobby: queue pad -> reserved server teleport, Goo tower unlock
-- Needs `rojo` on PATH (it builds the place first). Each scenario runs in a fresh process.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SCENARIOS = { "solo", "fuzz", "coop", "data", "lobby" }
local PLACE = "build/SmokeTest.rbxl"

local scenario = process.args[1]
if scenario == nil then
	-- Run every scenario in its own process so emulator state never leaks between them.
	fs.writeDir("build")
	local build = process.spawn("rojo", { "build", "default.project.json", "-o", PLACE })
	if not build.ok then
		print(build.stderr)
		process.exit(1)
	end
	local failed = {}
	for _, name in SCENARIOS do
		local result = process.spawn("lune", { "run", "tools/smoke", name }, { stdio = "inherit" })
		if not result.ok then
			table.insert(failed, name)
		end
	end
	print(if #failed == 0 then "\nALL SMOKE SCENARIOS PASSED" else "\nFAILED: " .. table.concat(failed, ", "))
	process.exit(if #failed == 0 then 0 else 1)
end

if not fs.isFile(PLACE) then
	fs.writeDir("build")
	process.spawn("rojo", { "build", "default.project.json", "-o", PLACE })
end

local Runtime = require("./emu/Runtime")
local Enum = roblox.Enum

---------------------------------------------------------------------------
-- tiny assertion helpers
---------------------------------------------------------------------------

local checks, failures = 0, 0
local function check(cond: any, message: string)
	checks += 1
	if cond then
		print("  [+] " .. message)
	else
		failures += 1
		print("  [-] " .. message)
	end
end

local function finish()
	local errorCount = #Runtime.errors
	print(
		string.format(
			"\n[%s] %d checks, %d failed, %d script errors, %d warnings",
			scenario,
			checks,
			failures,
			errorCount,
			#Runtime.warnings
		)
	)
	for _, w in Runtime.warnings do
		print("  warn: " .. w)
	end
	if failures > 0 or errorCount > 0 then
		print("--- last log lines ---")
		for i = math.max(1, #Runtime.logs - 40), #Runtime.logs do
			print(Runtime.logs[i])
		end
		process.exit(1)
	end
	process.exit(0)
end

local function findDescendant(root: any, name: string, className: string?): any
	for _, d in root:GetDescendants() do
		if d.Name == name and (className == nil or d:IsA(className)) then
			return d
		end
	end
	return nil
end

local function findButtonWithText(root: any, needle: string, exact: boolean?): any
	for _, d in root:GetDescendants() do
		local isLabel = d:IsA("TextLabel") and d.Name == "Label"
		local matches = isLabel and (if exact then d.Text == needle else string.find(d.Text, needle, 1, true) ~= nil)
		if matches then
			local node = d.Parent
			while node and node ~= root do
				if node:IsA("GuiButton") then
					return node
				end
				node = node.Parent
			end
		end
	end
	return nil
end

local function badgesOf(profileMsg: any): any
	return profileMsg and profileMsg[1].badges or {}
end

local function matchState(player: any): any
	local args = Runtime.lastRemote("MatchState", player)
	return args and args[1]
end

local function myCash(player: any): number
	local state = matchState(player)
	if not state then
		return -1
	end
	for _, p in state.players do
		if p.userId == player.UserId then
			return p.cash
		end
	end
	return -1
end

local function towersFolder(): any
	return Runtime.game():GetService("Workspace"):FindFirstChild("Towers")
end

local function fire(ctx: any, remoteName: string, ...: any)
	local args = table.pack(...)
	Runtime.within(ctx, function()
		local remote = Runtime.game():GetService("ReplicatedStorage").Remotes:FindFirstChild(remoteName)
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
end

local function towerModelAt(x: number, z: number): any
	for _, m in towersFolder():GetChildren() do
		local p = m:GetPivot().Position
		if math.abs(p.X - x) < 0.01 and math.abs(p.Z - z) < 0.01 then
			return m
		end
	end
	return nil
end

local function waitFor(seconds: number, predicate: () -> boolean): boolean
	local deadline = Runtime.now() + seconds
	while Runtime.now() < deadline do
		Runtime.advance(0.25)
		if predicate() then
			return true
		end
	end
	return predicate()
end

local function slimeCount(ctx: any): number
	local folder = Runtime.game():GetService("Workspace"):FindFirstChild("ClientSlimes")
	if not folder then
		return 0
	end
	local n = 0
	for _, part in folder:GetChildren() do
		if part.CFrame.Position.Y > -500 then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- scenarios
---------------------------------------------------------------------------

local scenarios = {}

function scenarios.solo()
	Runtime.boot({ place = PLACE, studio = true, studioMode = "match" })
	local ana, ctx = Runtime.addPlayer("Ana")
	Runtime.advance(1)

	local state = matchState(ana)
	check(state ~= nil, "client receives MatchState after ClientReady")
	check(state and state.phase == "prep" and state.lives == 150, "match starts in prep with 150 lives")
	check(myCash(ana) == 650, "starting cash is $650")
	local hud = Runtime.findGui(ctx, "HUD")
	check(hud ~= nil, "HUD ScreenGui is created")
	check(Runtime.findGui(ctx, "TowerPanel") ~= nil, "TowerPanel ScreenGui is created")
	check(Runtime.findGui(ctx, "DebugPanel") ~= nil, "Studio debug panel exists in Studio")

	-- Place a Dart Frog through the real UI: hotbar slot, then click the garden.
	local slot = findDescendant(hud, "DartFrog", "GuiButton")
	check(slot ~= nil, "hotbar has a Dart Frog slot")
	Runtime.click(ctx, slot)
	check(Runtime.game():GetService("Workspace"):FindFirstChild("DartFrog") ~= nil, "placement ghost appears")
	Runtime.clickWorld(ctx, -40, 0) -- on the path: must be refused client-side
	Runtime.advance(0.5)
	check(#towersFolder():GetChildren() == 0, "clicking on the path does not place a tower")
	Runtime.clickWorld(ctx, -34, 19)
	Runtime.advance(0.5)
	check(#towersFolder():GetChildren() == 1, "clicking open ground places the tower")
	check(myCash(ana) == 450, "placing a $200 frog leaves $450")
	local frog = towerModelAt(-34, 19)
	check(
		frog and frog:GetAttribute("Owner") == ana.UserId and frog:GetAttribute("TowerId") == "DartFrog",
		"tower model carries owner + id attributes"
	)
	check(Runtime.game():GetService("Workspace"):FindFirstChild("DartFrog") == nil, "ghost is removed after placing")

	-- Select it and upgrade through the panel.
	Runtime.clickWorld(ctx, -34, 19)
	Runtime.advance(0.5)
	local panelGui = Runtime.findGui(ctx, "TowerPanel")
	local panel = findDescendant(panelGui, "Panel")
	check(panel and panel.Visible, "clicking a tower opens the upgrade panel")
	local upgradeA = findButtonWithText(panel, "$140", true)
	check(upgradeA ~= nil, "panel shows the $140 path A upgrade")
	if upgradeA then
		Runtime.click(ctx, upgradeA)
		Runtime.advance(0.5)
	end
	check(frog:GetAttribute("TierA") == 1, "upgrade applied (TierA = 1)")
	check(myCash(ana) == 310, "upgrade cost deducted ($310 left)")
	local lastSegment = findButtonWithText(panel, "LAST", true)
	check(lastSegment ~= nil, "targeting is a segmented control")
	if lastSegment then
		Runtime.click(ctx, lastSegment)
		Runtime.advance(0.5)
	end
	check(frog:GetAttribute("Targeting") == "Last", "tapping the Last segment sets Last targeting")

	-- Second frog with the keyboard hotkey "1".
	check(Runtime.pressAction(ctx, Enum.KeyCode.One), "hotkey 1 is bound")
	Runtime.clickWorld(ctx, -4, -29)
	Runtime.advance(0.5)
	check(#towersFolder():GetChildren() == 2, "hotkey placement works")

	-- Round 1 must start on its own after the prep countdown.
	local started = waitFor(25, function()
		local s = matchState(ana)
		return s ~= nil and s.round == 1 and s.phase == "wave"
	end)
	check(started, "round 1 starts automatically after the prep countdown")
	local banner = findDescendant(hud, "RoundBanner")
	local bannerTitle = banner and findDescendant(banner, "Title", "TextLabel")
	check(
		banner and banner.Visible and bannerTitle and string.find(bannerTitle.Text, "ROUND 1", 1, true) ~= nil,
		"round banner pops in with ROUND 1"
	)
	check(findDescendant(hud, "Progress").Visible, "wave progress bar shows during the wave")
	Runtime.advance(6)
	check(slimeCount(ctx) > 0, "client renders slimes during the wave")
	local cleared = waitFor(60, function()
		local s = matchState(ana)
		return s ~= nil and s.phase == "intermission"
	end)
	check(cleared, "round 1 ends")
	local toast = findDescendant(hud, "Toast")
	local toastLabels = {}
	for _, d in toast:GetDescendants() do
		if d:IsA("TextLabel") then
			table.insert(toastLabels, d.Text)
		end
	end
	check(
		toast.Visible and string.find(table.concat(toastLabels, " "), "ROUND BONUS +$101", 1, true) ~= nil,
		"round bonus toast slides in"
	)
	check(not findDescendant(hud, "Progress").Visible, "wave bar hides between rounds")
	state = matchState(ana)
	check(state.lives == 150, "two frogs hold round 1 without leaks")
	check(myCash(ana) >= 81 + 101 + 20 - 1, "round bonus + pop cash paid")

	-- Skip vote with one player starts the next round right away.
	fire(ctx, "VoteSkip")
	Runtime.advance(0.5)
	check(matchState(ana).round == 2, "solo skip vote starts the next round")
	-- 2x Speed is a game pass: no pass, no fast-forward; the tile opens the purchase instead.
	fire(ctx, "VoteSpeed")
	Runtime.advance(0.5)
	check(matchState(ana).speed == 1, "2x vote without the pass is ignored")
	local hudGui = Runtime.findGui(ctx, "HUD")
	local speedTile = findDescendant(hudGui, "SpeedButton", "GuiButton")
	local speedBadge = findDescendant(speedTile, "BadgeText")
	check(speedBadge and speedBadge.Text == "R$" and speedBadge.Parent.Visible, "2x tile shows R$ without the pass")
	Runtime.click(ctx, speedTile)
	Runtime.advance(1)
	check(Runtime.lastRemote("ProfileData", ana)[1].passes.FastForward == true, "2x tile buys the pass (Studio grant)")
	check(matchState(ana).speed == 2, "after buying, the vote goes through: 2x")

	-- Debug: plenty of lives and cash, then play the first boss round.
	local debugRemote = Runtime.game():GetService("ReplicatedStorage").Remotes:FindFirstChild("Debug")
	check(debugRemote ~= nil, "Debug remote exists in Studio")
	fire(ctx, "Debug", "lives", 100000)
	fire(ctx, "Debug", "cash", 50000)
	Runtime.advance(0.5)
	for _, spot in { { 26, 24 }, { 56, -4 }, { -16, 19 }, { 14, -29 }, { -28, 15 } } do
		fire(ctx, "PlaceTower", "WizardOwl", spot[1], spot[2])
	end
	Runtime.advance(0.5)
	check(#towersFolder():GetChildren() == 7, "five more towers placed via remotes")
	for _, model in towersFolder():GetChildren() do
		if model:GetAttribute("TowerId") == "WizardOwl" then
			for _, path in { "A", "B", "B", "B" } do
				fire(ctx, "UpgradeTower", model:GetAttribute("Uid"), path)
			end
		end
	end
	Runtime.advance(1.5)
	-- Take one owl to its tier-5 ULTIMATE on path B (crosspath allows tier 2 on A).
	local ultimateOwl = nil
	for _, model in towersFolder():GetChildren() do
		if model:GetAttribute("TowerId") == "WizardOwl" and not ultimateOwl then
			ultimateOwl = model
		end
	end
	for _, path in { "B", "B", "A", "A" } do
		fire(ctx, "UpgradeTower", ultimateOwl:GetAttribute("Uid"), path)
	end
	Runtime.advance(0.5)
	check(
		ultimateOwl:GetAttribute("TierB") == 5 and ultimateOwl:GetAttribute("TierA") == 2,
		"owl upgraded to B5 (ultimate) with A2"
	)
	fire(ctx, "UpgradeTower", ultimateOwl:GetAttribute("Uid"), "A")
	Runtime.advance(0.5)
	check(ultimateOwl:GetAttribute("TierA") == 2, "crosspath blocks A3 next to B5")
	local ultimatePips = 0
	for _, pip in ultimateOwl.Pips:GetChildren() do
		if pip.Size.X > 0.6 then
			ultimatePips += 1
		end
	end
	check(ultimatePips == 1, "the ultimate shows a big gold pip on the model")
	fire(ctx, "Debug", "round", 20)
	Runtime.advance(0.5)
	fire(ctx, "VoteSkip")
	local sawBoss = false
	waitFor(5, function()
		return matchState(ana).round == 20
	end)
	local bossDone = waitFor(400, function()
		for _, part in Runtime.game():GetService("Workspace").ClientSlimes:GetChildren() do
			if part.Size.X >= 6.9 and part.CFrame.Position.Y > -500 then
				sawBoss = true
			end
		end
		return matchState(ana).phase == "intermission"
	end)
	check(sawBoss, "Big Boss Slime is rendered on round 20")
	check(bossDone, "round 20 completes")
	local shakeEmits = 0
	for _, d in Runtime.game():GetService("Workspace").ClientEffects:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Parent.Name == "PopBoss" then
			shakeEmits = d:GetAttribute("__emitted") or 0
		end
	end
	check(shakeEmits > 0, "boss pop burst is emitted")
	print(`  (emulated time so far: {math.floor(Runtime.now())}s)`)

	-- Jump to round 40 and win.
	fire(ctx, "Debug", "round", 40)
	Runtime.advance(0.5)
	fire(ctx, "VoteSkip")
	local won = waitFor(600, function()
		return Runtime.lastRemote("MatchResult", ana) ~= nil
	end)
	check(won, "round 40 ends the match")
	local result = Runtime.lastRemote("MatchResult", ana)
	check(result and result[1].won == true, "match result is a win")
	check(result and result[1].goo == 40 * 2 + 60, "win pays 140 Goo")
	local profile = Runtime.lastRemote("ProfileData", ana)
	check(profile and profile[1].goo == 140 and profile[1].stats.wins == 1, "profile updated with Goo and a win")
	local stats = profile and profile[1].stats or {}
	check(stats.towersPlaced >= 3 and stats.upgradesBought >= 3, "towers placed / upgrades bought are tracked")
	check(stats.totalPops > 100 and stats.bossPops >= 1, "pops and boss pops are tracked")
	check(stats.bestRound == 40, "best round recorded")
	check((stats.perfectWins == 1) == (badgesOf(profile).Untouchable == false), "Untouchable follows perfect wins")
	local earned = profile and profile[1].badges or {}
	check(
		earned.FirstSteps == false
			and earned.Champion == false
			and earned.BossBuster == false
			and earned.Halfway == false,
		"match badges earned (unclaimed)"
	)
	check(earned.Veteran == nil and earned.TeamPlayer == nil, "badges not met stay locked")
	local notes = {}
	for _, r in Runtime.remoteLog do
		if r.name == "Notify" and r.player == ana then
			table.insert(notes, r.args[1])
		end
	end
	check(string.find(table.concat(notes, "|"), "Badge earned: Champion", 1, true) ~= nil, "badge earned toast sent")
	local resultsCard = findDescendant(Runtime.findGui(ctx, "Results"), "Results")
	check(resultsCard and resultsCard.Visible, "results card is shown")
	Runtime.advance(2)
	local gooTileLabels = {}
	for _, d in findDescendant(resultsCard, "Goo"):GetDescendants() do
		if d:IsA("TextLabel") then
			table.insert(gooTileLabels, d.Text)
		end
	end
	check(table.find(gooTileLabels, "+140") ~= nil, "Goo reward tile counts up to +140")

	-- Studio restarts the match after the results countdown.
	Runtime.advance(20)
	state = matchState(ana)
	check(
		state and state.round == 0 and state.phase == "prep" and state.lives == 150,
		"Studio resets the match after it ends"
	)
	check(#towersFolder():GetChildren() == 0, "towers are cleared on reset")
	check(myCash(ana) == 650, "cash resets to $650")
	finish()
end

function scenarios.fuzz()
	Runtime.boot({ place = PLACE, studio = true, studioMode = "match" })
	local bob, ctx = Runtime.addPlayer("Bob")
	Runtime.advance(1)
	fire(ctx, "PlaceTower", "DartFrog", -34, 19)
	Runtime.advance(0.5)
	local cashBefore = myCash(bob)
	local towersBefore = #towersFolder():GetChildren()

	local nan = 0 / 0
	local garbage = {
		nil,
		nan,
		math.huge,
		-math.huge,
		-1,
		0,
		1.5,
		1e300,
		"",
		"DartFrog",
		string.rep("x", 10000),
		true,
		{},
		{ 1, 2, 3 },
		{ x = 1 },
		buffer.create(8),
		bob,
	}
	local remotes = Runtime.game():GetService("ReplicatedStorage").Remotes:GetChildren()
	local calls = 0
	for _, remote in remotes do
		if remote.Name ~= "Debug" then
			for i = 1, #garbage + 1 do
				for j = 1, #garbage + 1, 3 do
					fire(ctx, remote.Name, garbage[i], garbage[j], garbage[(i + j) % #garbage + 1])
					calls += 1
				end
				Runtime.advance(0.05)
			end
		end
	end
	Runtime.advance(2)
	check(calls > 1000, `fired {calls} garbage remote calls`)
	check(#Runtime.errors == 0, "no server or client script errors from garbage input")
	check(#towersFolder():GetChildren() == towersBefore, "garbage did not place or sell towers")
	-- Rate limiting: a flood of real requests is mostly dropped.
	local frog = towersFolder():GetChildren()[1]
	for _ = 1, 200 do
		fire(ctx, "SetTargeting", frog:GetAttribute("Uid"), "Strong")
	end
	Runtime.advance(0.5)
	-- (Garbage VoteSkip calls legitimately start round 1, so pops may add cash.)
	check(myCash(bob) >= cashBefore, "fuzzing never spent cash")
	check(frog:GetAttribute("TierA") == 0 and frog:GetAttribute("TierB") == 0, "fuzzing bought no upgrades")
	local mode = frog:GetAttribute("Targeting")
	check(mode == "First" or mode == "Last" or mode == "Strong" or mode == "Close", "targeting is still a valid mode")
	finish()
end

function scenarios.coop()
	Runtime.boot({ place = PLACE, studio = true, studioMode = "match" })
	local players, ctxs = {}, {}
	for i, name in { "P1", "P2", "P3", "P4" } do
		players[i], ctxs[i] = Runtime.addPlayer(name)
	end
	Runtime.advance(1)
	local state = matchState(players[1])
	check(state.playerCount == 4, "four players in the match")
	for i = 1, 4 do
		check(myCash(players[i]) == 650, `P{i} has their own $650`)
	end
	fire(ctxs[1], "PlaceTower", "DartFrog", -34, 19)
	fire(ctxs[2], "PlaceTower", "DartFrog", -4, -29)
	Runtime.advance(0.5)
	check(
		myCash(players[1]) == 450 and myCash(players[2]) == 450 and myCash(players[3]) == 650,
		"cash is spent per player"
	)
	local p1Frog = towerModelAt(-34, 19)
	fire(ctxs[2], "UpgradeTower", p1Frog:GetAttribute("Uid"), "A")
	fire(ctxs[2], "SellTower", p1Frog:GetAttribute("Uid"))
	Runtime.advance(0.5)
	check(p1Frog.Parent ~= nil and p1Frog:GetAttribute("TierA") == 0, "P2 cannot upgrade or sell P1's tower")
	check(myCash(players[2]) == 450, "failed attempts cost nothing")

	-- Majority: 2 of 4 is not enough, 3 of 4 is.
	fire(ctxs[1], "VoteSkip")
	fire(ctxs[2], "VoteSkip")
	Runtime.advance(0.5)
	check(
		matchState(players[1]).round == 0 and matchState(players[1]).skipVotes == 2,
		"2 of 4 skip votes do not start the round"
	)
	fire(ctxs[3], "VoteSkip")
	Runtime.advance(0.5)
	check(matchState(players[1]).round == 1, "3 of 4 skip votes start the round")
	-- 2x Speed pass: P1, P2 and P4 own it; P3 doesn't, so P3's vote doesn't count.
	for _, i in { 1, 2, 4 } do
		fire(ctxs[i], "PurchaseRequest", "FastForward")
	end
	Runtime.advance(0.5)
	check(matchState(players[1]).speedOwners == 3, "three pass owners in the match")
	fire(ctxs[3], "VoteSpeed")
	fire(ctxs[1], "VoteSpeed")
	Runtime.advance(0.5)
	check(matchState(players[1]).speed == 1, "1 of 3 owner votes (plus a non-owner) keep 1x")
	fire(ctxs[4], "VoteSpeed")
	Runtime.advance(0.5)
	check(matchState(players[1]).speed == 2, "2 of 3 owner votes give 2x")

	-- Teammate sees P1's tower read-only in the panel.
	Runtime.clickWorld(ctxs[3], -34, 19)
	Runtime.advance(0.5)
	local panel = findDescendant(Runtime.findGui(ctxs[3], "TowerPanel"), "Panel")
	check(panel.Visible, "teammate can inspect P1's tower")
	local sell = findDescendant(panel, "Sell", "GuiButton")
	check(sell == nil or not sell.Visible, "sell button hidden for a teammate's tower")

	-- A player leaves mid-wave.
	Runtime.removePlayer(players[4])
	Runtime.advance(1)
	check(matchState(players[1]).playerCount == 3, "player count drops when someone leaves")
	check(matchState(players[1]).speed == 1, "after P4 leaves, 1 of 2 owner votes drops back to 1x")
	local roundOver = waitFor(90, function()
		return matchState(players[1]).phase == "intermission"
	end)
	check(roundOver, "round completes with three players")
	check(myCash(players[3]) == 650 + 101, "every remaining player gets the round bonus")
	finish()
end

function scenarios.data()
	local STORE = "PlayerProfiles_v1"
	Runtime.boot({ place = PLACE, studio = false, privateServerId = "ps-1", jobId = "job-A" })
	check(
		Runtime.game():GetService("ReplicatedStorage"):GetAttribute("Mode") == "match",
		"reserved server runs match mode"
	)
	check(
		Runtime.game():GetService("ReplicatedStorage").Remotes:FindFirstChild("Debug") == nil,
		"no Debug remote in live servers"
	)

	-- New player: profile created and locked.
	local cara = Runtime.addPlayer("Cara", { userId = 501 })
	Runtime.advance(2)
	local raw = Runtime.dataStores[STORE] and Runtime.dataStores[STORE]["u_501"]
	check(raw ~= nil, "a profile record is created on join")
	local serde = require("@lune/serde")
	local record = raw and serde.decode("json", raw)
	check(record and record.lock and record.lock.jobId == "job-A", "profile is session-locked by this server")
	check(
		record and record.data.unlocked.DartFrog == true and record.data.goo == 0,
		"defaults: Dart Frog unlocked, 0 Goo"
	)
	local profileMsg = Runtime.lastRemote("ProfileData", cara)
	check(profileMsg ~= nil, "client receives its profile")

	-- Leaving releases the lock and keeps data.
	Runtime.removePlayer(cara)
	Runtime.advance(2)
	record = serde.decode("json", Runtime.dataStores[STORE]["u_501"])
	check(record.lock == nil, "leaving saves and releases the lock")

	-- A profile freshly locked by another server: retry, then kick (never load over it).
	Runtime.dataStores[STORE]["u_777"] = serde.encode("json", {
		data = {
			version = 1,
			goo = 999,
			xp = 0,
			unlocked = { DartFrog = true },
			passes = {},
			receipts = {},
			stats = { matches = 0, wins = 0, bestRound = 0 },
		},
		lock = { jobId = "job-OTHER", time = 1700000000 + math.floor(Runtime.now()) },
	})
	local dan = Runtime.addPlayer("Dan", { userId = 777 })
	Runtime.advance(60)
	check(dan.kicked ~= nil, "player is kicked when another server still holds the lock")
	record = serde.decode("json", Runtime.dataStores[STORE]["u_777"])
	check(record.data.goo == 999 and record.lock.jobId == "job-OTHER", "locked profile was not overwritten")

	-- A stale lock (crashed server) is taken over.
	Runtime.dataStores[STORE]["u_888"] = serde.encode("json", {
		data = {
			version = 1,
			goo = 42,
			xp = 0,
			unlocked = { DartFrog = true },
			passes = {},
			receipts = {},
			stats = { matches = 0, wins = 0, bestRound = 0 },
		},
		lock = { jobId = "job-DEAD", time = 1600000000 },
	})
	local eve = Runtime.addPlayer("Eve", { userId = 888 })
	Runtime.advance(3)
	check(eve.kicked == nil, "stale lock is taken over")
	local eveProfile = Runtime.lastRemote("ProfileData", eve)
	check(eveProfile and eveProfile[1].goo == 42, "existing Goo loads")

	-- DataStore outage on join: kick, never play on a default profile.
	Runtime.dataStoreFailures = 1000
	local fay = Runtime.addPlayer("Fay", { userId = 999 })
	Runtime.advance(60)
	check(fay.kicked ~= nil, "DataStore outage on load kicks the player")
	check(Runtime.dataStores[STORE]["u_999"] == nil, "nothing written for the failed load")
	Runtime.dataStoreFailures = 0

	-- Shutdown flushes everyone still in the server.
	Runtime.shutdown()
	Runtime.advance(2)
	record = serde.decode("json", Runtime.dataStores[STORE]["u_888"])
	check(record.lock == nil, "BindToClose saves and releases remaining players")
	finish()
end

function scenarios.lobby()
	local serde = require("@lune/serde")
	Runtime.dataStores.PlayerProfiles_v1 = {
		u_301 = serde.encode("json", {
			data = {
				version = 1,
				goo = 500,
				xp = 2000,
				unlocked = { DartFrog = true },
				passes = {},
				receipts = {},
				stats = { matches = 0, wins = 0, bestRound = 0 },
			},
		}),
	}
	Runtime.boot({ place = PLACE, studio = false, privateServerId = "", jobId = "job-lobby" })
	check(
		Runtime.game():GetService("ReplicatedStorage"):GetAttribute("Mode") == "lobby",
		"public server runs lobby mode"
	)
	local ws = Runtime.game():GetService("Workspace")
	local pad = ws.Lobby.QueuePad
	check(pad ~= nil, "lobby has a queue pad")

	local gil, gilCtx = Runtime.addPlayer("Gil", { userId = 301 })
	local hal = Runtime.addPlayer("Hal", { userId = 302 })
	Runtime.advance(2)

	-- v1 save migrated to v2; level 5 (2000 XP) earns the Level 5 badge on load.
	local profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.stats.totalPops == 0 and profile.equippedBadge == "", "v1 profile migrates to v2")
	check(profile.badges.Level5 == false, "Level 5 badge earned on load")

	-- Badges window: claimable dot, claim pays once, equip shows a head tag.
	local lobbyGui = Runtime.findGui(gilCtx, "Lobby")
	check(lobbyGui ~= nil, "lobby UI exists")
	local bubble = findDescendant(lobbyGui, "ClaimCount")
	check(bubble and bubble.Visible, "Badges tile shows a claim bubble")
	Runtime.click(gilCtx, findDescendant(lobbyGui, "BadgesButton", "GuiButton"))
	local badgesWindow = findDescendant(lobbyGui, "Badges", "Frame")
	check(badgesWindow and badgesWindow.Visible, "Badges window opens")
	local tile = findDescendant(badgesWindow, "Level5", "GuiButton")
	check(tile and findDescendant(tile, "Claimable").Visible, "Level 5 tile shows the claim dot")
	local lockedTile = findDescendant(badgesWindow, "Champion", "GuiButton")
	check(lockedTile and findDescendant(lockedTile, "Question") ~= nil, "locked badges show ?")
	local claimButton = findDescendant(badgesWindow, "Claim", "GuiButton")
	check(claimButton and claimButton.Visible, "detail strip opens on the claimable badge")
	Runtime.click(gilCtx, claimButton)
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.badges.Level5 == true and profile.goo == 550, "claim pays 50 Goo")
	fire(gilCtx, "ClaimBadge", "Level5")
	fire(gilCtx, "ClaimBadge", "Champion")
	fire(gilCtx, "ClaimBadge", { "junk" })
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.goo == 550, "double claims, locked and junk claims pay nothing")
	check(not bubble.Visible, "claim bubble hides when nothing is left")

	local character = roblox.Instance.new("Model")
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Parent = character
	character.Parent = ws
	gil.Character = character
	fire(gilCtx, "EquipBadge", "Champion")
	Runtime.advance(0.5)
	check(Runtime.lastRemote("ProfileData", gil)[1].equippedBadge == "", "can't equip a locked badge")
	Runtime.click(gilCtx, findDescendant(badgesWindow, "Equip", "GuiButton"))
	Runtime.advance(0.5)
	check(Runtime.lastRemote("ProfileData", gil)[1].equippedBadge == "Level5", "equip from the window")
	local tag = head:FindFirstChild("BadgeTag")
	check(tag and tag.Label.Text == "LEVEL 5", "equipped badge shows over the head")
	check(findButtonWithText(badgesWindow, "UNEQUIP", true) ~= nil, "button flips to Unequip")
	Runtime.click(gilCtx, findDescendant(badgesWindow, "Close", "GuiButton"))
	check(not badgesWindow.Visible, "Badges window closes")

	-- Shop: rarity cards, featured = cheapest unowned, buy from the featured card.
	Runtime.click(gilCtx, findDescendant(lobbyGui, "ShopButton", "GuiButton"))
	local shop = findDescendant(lobbyGui, "Shop", "Frame")
	check(shop and shop.Visible, "Shop opens")
	local unowned = 0
	for _, card in findDescendant(shop, "Grid"):GetChildren() do
		if card:IsA("GuiButton") and findDescendant(card, "Label").Text ~= "Owned" then
			unowned += 1
		end
	end
	check(unowned == 5, "five locked towers show a Goo price")
	check(findDescendant(shop, "Rarity").Text == "COMMON", "cards show rarity")
	check(findDescendant(shop, "TowerName").Text == "Spike Turtle", "featured tower is the cheapest unowned")
	check(#findDescendant(shop, "Rows"):GetChildren() >= 5, "Goo & Passes lists every product")
	Runtime.click(gilCtx, findDescendant(findDescendant(shop, "Featured"), "Buy", "GuiButton"))
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.unlocked.SpikeTurtle == true and profile.goo == 470, "featured Buy unlocks Spike Turtle for 80")
	check(findDescendant(shop, "TowerName").Text == "Ice Penguin", "spotlight moves to the next cheapest")
	Runtime.click(gilCtx, findDescendant(shop, "CannonCrab", "GuiButton"))
	check(findDescendant(shop, "TowerName").Text == "Cannon Crab", "clicking a card features it")
	Runtime.click(gilCtx, findDescendant(findDescendant(shop, "Featured"), "Buy", "GuiButton"))
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.unlocked.CannonCrab == true and profile.goo == 320, "Cannon Crab unlocked for 150 Goo")
	fire(gilCtx, "UnlockTower", "WizardOwl")
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.unlocked.WizardOwl == true and profile.goo == 120, "Wizard Owl unlocked for 200 Goo")
	fire(gilCtx, "UnlockTower", "BankBee")
	Runtime.advance(0.5)
	profile = Runtime.lastRemote("ProfileData", gil)[1]
	check(profile.unlocked.BankBee == nil and profile.goo == 120, "can't unlock without enough Goo")

	-- Stub purchase in a live server: refused as "coming soon", nothing granted.
	fire(gilCtx, "PurchaseRequest", "DoubleGoo")
	Runtime.advance(0.5)
	local purchase = Runtime.lastRemote("PurchaseResult", gil)
	check(purchase and purchase[2] == false, "unconfigured products are refused live")

	-- Gil presses PLAY (the server moves him onto the pad); Hal walks onto it.
	for i, p in { gil, hal } do
		local character = roblox.Instance.new("Model")
		local root = roblox.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = if i == 1
			then roblox.CFrame.new(0, 3, 20)
			else roblox.CFrame.new(pad.CFrame.Position + roblox.Vector3.new(1, 3, 0))
		root.Parent = character
		character.PrimaryPart = root
		character.Parent = ws
		p.Character = character
	end
	local playButton = findDescendant(lobbyGui, "PlayButton", "GuiButton")
	check(playButton ~= nil, "lobby has a PLAY button")
	Runtime.click(gilCtx, playButton)
	Runtime.advance(0.5)
	local gilPos = gil.Character.PrimaryPart.CFrame.Position
	local padPos = pad.CFrame.Position
	local flat = roblox.Vector3.new(gilPos.X - padPos.X, 0, gilPos.Z - padPos.Z)
	check(flat.Magnitude < 7, "PLAY moves the character onto the queue pad")
	local teleported = waitFor(15, function()
		return #Runtime.teleports > 0
	end)
	check(teleported, "queue launches after the countdown")
	local tp = Runtime.teleports[1]
	check(tp and #tp.players == 2, "both players teleport together")
	check(tp and tp.code ~= nil and tp.data and #tp.data.party == 2, "reserved server code + party teleport data")
	finish()
end

local run = scenarios[scenario]
if not run then
	print("unknown scenario " .. tostring(scenario))
	process.exit(1)
end
print(`=== smoke: {scenario} ===`)
run()
