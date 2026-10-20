--!strict
-- Pooled, throttled 2D sound playback. Hundreds of pops per second become a steady
-- squish stream instead of hundreds of overlapping Sound instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Data.Theme)

local Sound = {}

local POOL_PER_SOUND = 6
local MIN_GAP = { squish = 0.045, cash = 0.12, leak = 0.25 } :: { [string]: number }

type Pool = { sounds: { Sound }, nextIndex: number, lastPlayed: number }
local pools: { [string]: Pool } = {}
local rng = Random.new()
local folder: Folder? = nil

local function getPool(key: string): Pool?
	local existing = pools[key]
	if existing then
		return existing
	end
	local def = Theme.Sounds[key]
	if not def then
		return nil
	end
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "GameSounds"
		f.Parent = SoundService
		folder = f
	end
	local pool: Pool = { sounds = {}, nextIndex = 1, lastPlayed = 0 }
	for i = 1, POOL_PER_SOUND do
		local s = Instance.new("Sound")
		s.Name = `{key}{i}`
		s.SoundId = def.id
		s.Volume = def.volume
		s.Parent = folder
		table.insert(pool.sounds, s)
	end
	pools[key] = pool
	return pool
end

function Sound.play(key: string, volumeScale: number?)
	local pool = getPool(key)
	local def = Theme.Sounds[key]
	if not pool or not def then
		return
	end
	local now = os.clock()
	if now - pool.lastPlayed < (MIN_GAP[key] or 0.02) then
		return
	end
	pool.lastPlayed = now
	local s = pool.sounds[pool.nextIndex]
	pool.nextIndex = pool.nextIndex % #pool.sounds + 1
	s.PlaybackSpeed = def.pitch + rng:NextNumber(-def.jitter, def.jitter)
	s.Volume = def.volume * (volumeScale or 1)
	s.TimePosition = 0
	s:Play()
end

return Sound
