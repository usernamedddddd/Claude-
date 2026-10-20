--!strict
-- Player profiles: Goo, XP, unlocked towers, owned passes, stats.
--
-- * Every DataStore call is pcall'd with exponential backoff.
-- * UpdateAsync only (no Get+Set), with a session lock (JobId + timestamp) so two servers
--   never own a profile at once (lobby <-> match teleports hand the lock over cleanly).
-- * Saves on autosave, PlayerRemoving and BindToClose; the final save releases the lock.
-- * A failed load kicks the player live (never play on a default profile over real data).
--   In Studio without API access, a temporary unsaved profile is used instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Config = require(Shared.Data.Config)
local TowerData = require(Shared.Data.TowerData)

export type Profile = {
	version: number,
	goo: number,
	xp: number,
	unlocked: { [string]: boolean },
	passes: { [string]: boolean },
	receipts: { string }, -- recent dev product receipt ids (dedupe)
	stats: { matches: number, wins: number, bestRound: number },
}

type Record = {
	data: Profile,
	lock: { jobId: string, time: number }?,
}

type Session = {
	profile: Profile,
	dirty: boolean,
	persistent: boolean, -- false for Studio fallback profiles
	released: boolean,
	lastSave: number,
}

local CURRENT_VERSION = 1
local STORE_NAME = "PlayerProfiles_v1"
local AUTOSAVE_SECONDS = 60
local LOCK_STALE_SECONDS = AUTOSAVE_SECONDS * 2.5
local LOAD_ATTEMPTS = 8
local MAX_RECEIPTS = 50

local IS_STUDIO = RunService:IsStudio()
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio"

local DataService = {}

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local store: DataStore? = nil

local MIGRATIONS: { [number]: (any) -> any } = {
	-- [1] = function(data) ... return data end, -- v1 -> v2
}

local function defaultProfile(): Profile
	local unlocked: { [string]: boolean } = {}
	for id, def in TowerData do
		if def.unlockGoo == 0 then
			unlocked[id] = true
		end
	end
	return {
		version = CURRENT_VERSION,
		goo = 0,
		xp = 0,
		unlocked = unlocked,
		passes = {},
		receipts = {},
		stats = { matches = 0, wins = 0, bestRound = 0 },
	}
end

local function migrate(data: any): Profile
	local defaults = defaultProfile()
	while (data.version or 0) < CURRENT_VERSION do
		local step = MIGRATIONS[data.version or 0]
		if not step then
			error(`missing migration from v{data.version}`)
		end
		data = step(data)
		data.version = (data.version or 0) + 1
	end
	-- Fill any missing fields with defaults (forward-compatible).
	for k, v in defaults :: any do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

local function keyFor(userId: number): string
	return `u_{userId}`
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return result
	end
	warn(`[DataService] DataStore unavailable: {result}`)
	return nil
end

local function withRetry<T>(attempts: number, label: string, fn: () -> T): (boolean, T?)
	local delaySeconds = 1
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] {label} attempt {attempt}/{attempts} failed: {result}`)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 8)
		end
	end
	return false, nil
end

-- Sends the client-visible part of the profile.
local function pushToClient(player: Player, profile: Profile)
	local remote = Remotes.find("ProfileData")
	if remote then
		remote:FireClient(player, {
			goo = profile.goo,
			xp = profile.xp,
			level = 1 + profile.xp // Config.XP_PER_LEVEL,
			unlocked = profile.unlocked,
			passes = profile.passes,
			stats = profile.stats,
		})
	end
end

-- Claims the session lock and loads. Returns profile or nil + reason ("locked" | "error").
local function claim(ds: DataStore, userId: number): (Profile?, string?)
	local lockedByOther = false
	local loaded: Profile? = nil
	local ok = pcall(function()
		ds:UpdateAsync(keyFor(userId), function(old: any): any
			-- Never yield in here: compute synchronously from `old`.
			local record: Record
			if old == nil then
				record = { data = defaultProfile(), lock = nil }
			else
				record = old
			end
			local lock = record.lock
			if lock and lock.jobId ~= JOB_ID and os.time() - lock.time < LOCK_STALE_SECONDS then
				lockedByOther = true
				return nil -- abort the write
			end
			lockedByOther = false
			record.data = migrate(record.data or defaultProfile())
			record.lock = { jobId = JOB_ID, time = os.time() }
			loaded = record.data
			return record
		end)
	end)
	if not ok then
		return nil, "error"
	end
	if lockedByOther then
		return nil, "locked"
	end
	return loaded, nil
end

local function save(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session or not session.persistent or session.released then
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	local profile = session.profile
	local userId = player.UserId
	local ok = withRetry(if release then 5 else 2, `save {userId}`, function()
		ds:UpdateAsync(keyFor(userId), function(old: any): any
			local record: Record? = old
			if record and record.lock and record.lock.jobId ~= JOB_ID then
				-- Someone else owns this profile now; never overwrite their data.
				return nil
			end
			return {
				data = profile,
				lock = if release then nil else { jobId = JOB_ID, time = os.time() },
			}
		end)
		return true
	end)
	if ok then
		session.dirty = false
		session.lastSave = os.clock()
		if release then
			session.released = true
		end
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local profile: Profile? = nil
	local persistent = true
	local ds = getStore()
	if ds then
		for attempt = 1, LOAD_ATTEMPTS do
			if not player.Parent then
				return
			end
			local result, reason = claim(ds, player.UserId)
			if result then
				profile = result
				break
			end
			if reason == "error" and IS_STUDIO then
				break -- probably no Studio API access; fall back below
			end
			task.wait(math.min(2 ^ attempt * 0.5, 6))
		end
	end
	if not profile then
		if IS_STUDIO then
			warn("[DataService] Using a temporary profile (enable Studio API access to test saving).")
			profile = defaultProfile()
			persistent = false
		else
			player:Kick(
				"Your data couldn't load (it may still be saving from another server). Please rejoin in a moment."
			)
			return
		end
	end
	if not player.Parent then
		-- Left while loading: release the lock we just took.
		sessions[player] =
			{ profile = profile :: Profile, dirty = false, persistent = persistent, released = false, lastSave = 0 }
		save(player, true)
		sessions[player] = nil
		return
	end
	local loadedProfile = profile :: Profile
	sessions[player] = {
		profile = loadedProfile,
		dirty = false,
		persistent = persistent,
		released = false,
		lastSave = os.clock(),
	}
	pushToClient(player, loadedProfile)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, loadedProfile)
	end
end

local function onPlayerRemoving(player: Player)
	if sessions[player] then
		save(player, true)
		sessions[player] = nil
	end
end

function DataService.get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

-- Mutates the in-memory profile; persistence happens on autosave / leave / shutdown.
function DataService.update(player: Player, mutator: (Profile) -> ()): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	mutator(session.profile)
	session.dirty = true
	pushToClient(player, session.profile)
	return true
end

function DataService.onLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, session in sessions do
		task.spawn(callback, player, session.profile)
	end
end

function DataService.hasPass(player: Player, key: string): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profile.passes[key] == true
end

-- Records a receipt id; returns false if it was already processed.
function DataService.recordReceipt(profile: Profile, receiptId: string): boolean
	if table.find(profile.receipts, receiptId) then
		return false
	end
	table.insert(profile.receipts, receiptId)
	while #profile.receipts > MAX_RECEIPTS do
		table.remove(profile.receipts, 1)
	end
	return true
end

-- Forces a save now (e.g. right before teleporting players away).
function DataService.saveNow(player: Player, release: boolean): boolean
	return save(player, release)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Staggered autosave: each player saves on their own offset within the interval.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, session in sessions do
				local offset = (player.UserId % AUTOSAVE_SECONDS)
				if session.persistent and now - session.lastSave >= AUTOSAVE_SECONDS + offset % 5 then
					task.spawn(save, player, false)
					session.lastSave = now -- avoid double-scheduling while the save runs
				end
			end
		end
	end)

	game:BindToClose(function()
		if IS_STUDIO then
			for player in sessions do
				task.spawn(save, player, true)
			end
			return
		end
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
