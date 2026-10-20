--!strict
-- Analytics stub. One interface for every event; swap the sink for a real backend later
-- (e.g. AnalyticsService custom events). Events: match_start, round_complete, match_win,
-- match_lose, tower_placed, tower_upgraded, purchase_prompted, session_start, session_end.

local RunService = game:GetService("RunService")

export type EventName =
	"match_start"
	| "round_complete"
	| "match_win"
	| "match_lose"
	| "tower_placed"
	| "tower_upgraded"
	| "purchase_prompted"
	| "session_start"
	| "session_end"

local Analytics = {}

local VERBOSE = RunService:IsStudio()
local history: { { event: EventName, data: { [string]: any }, time: number } } = {}
local MAX_HISTORY = 200

local function describe(data: { [string]: any }): string
	local parts = {}
	for k, v in data do
		table.insert(parts, `{k}={tostring(v)}`)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

function Analytics.track(event: EventName, data: { [string]: any }?)
	local payload = data or {}
	table.insert(history, { event = event, data = payload, time = os.time() })
	if #history > MAX_HISTORY then
		table.remove(history, 1)
	end
	if VERBOSE then
		print(`[Analytics] {event} {describe(payload)}`)
	end
end

-- Recent events, for tests and the debug panel.
function Analytics.recent(): { { event: EventName, data: { [string]: any }, time: number } }
	return history
end

return Analytics
