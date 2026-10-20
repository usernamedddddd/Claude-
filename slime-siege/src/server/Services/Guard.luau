--!strict
-- Remote argument validation and per-player rate limiting. Every remote handler starts with
-- Guard.allow(...) and validates each argument with the helpers below before use.

local Players = game:GetService("Players")

local Guard = {}

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local strikes: { [Player]: number } = {}

-- Token bucket: `ratePerSec` sustained, `burst` short-term.
function Guard.allow(player: Player, key: string, ratePerSec: number, burst: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local b = playerBuckets[key]
	if not b then
		b = { tokens = burst, last = now }
		playerBuckets[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * ratePerSec)
	b.last = now
	if b.tokens < 1 then
		local count = (strikes[player] or 0) + 1
		strikes[player] = count
		if count % 100 == 0 then
			warn(`[Guard] {player.Name} hit rate limits {count} times (last: {key})`)
		end
		return false
	end
	b.tokens -= 1
	return true
end

function Guard.isFiniteNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Guard.number(v: unknown, min: number, max: number): number?
	if not Guard.isFiniteNumber(v) then
		return nil
	end
	local n = v :: number
	if n < min or n > max then
		return nil
	end
	return n
end

function Guard.integer(v: unknown, min: number, max: number): number?
	local n = Guard.number(v, min, max)
	if n == nil or n ~= math.floor(n) then
		return nil
	end
	return n
end

-- Only accepts strings that are keys of `set` (and short, so we never hash huge strings).
function Guard.key<T>(v: unknown, set: { [string]: T }): string?
	if type(v) ~= "string" or #v > 64 then
		return nil
	end
	if set[v] == nil then
		return nil
	end
	return v
end

function Guard.oneOf(v: unknown, options: { string }): string?
	if type(v) ~= "string" then
		return nil
	end
	if table.find(options, v) then
		return v
	end
	return nil
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	strikes[player] = nil
end)

return Guard
