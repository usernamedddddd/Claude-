--!strict
-- UI animation helpers implementing the Figma "Motion spec": short (<= 0.5 s), Back-Out for
-- pops, Quad-Out for movement, never blocking input. When the player has Reduced Motion on,
-- scale overshoots and shakes are skipped and only fades / instant changes remain.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Data.Theme)

local Motion = {}

Motion.T = Theme.Motion

function Motion.reduced(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function info(seconds: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

function Motion.tween(
	inst: Instance,
	seconds: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(inst, info(seconds, style, direction), props)
	tween:Play()
	return tween
end

-- Returns (creating if needed) the UIScale that animations drive on a GuiObject.
function Motion.scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("MotionScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Parent = gui
	return scale
end

-- Quick "punch": scale up then spring back (stat changes, vote chips).
function Motion.punch(gui: GuiObject, amount: number?)
	if Motion.reduced() then
		return
	end
	local scale = Motion.scaleOf(gui)
	scale.Scale = amount or 1.12
	Motion.tween(scale, Motion.T.punch, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Pop in from small (banners, result cards, new elements).
function Motion.popIn(gui: GuiObject, from: number?, seconds: number?)
	gui.Visible = true
	local scale = Motion.scaleOf(gui)
	if Motion.reduced() then
		scale.Scale = 1
		return
	end
	scale.Scale = from or 0.6
	Motion.tween(scale, seconds or Motion.T.resultsCard, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Horizontal shake (locked tap, life lost). Restores the original position.
function Motion.shake(gui: GuiObject, pixels: number?, cycles: number?)
	if Motion.reduced() then
		return
	end
	local origin = gui:GetAttribute("MotionOrigin")
	if typeof(origin) ~= "UDim2" then
		origin = gui.Position
		gui:SetAttribute("MotionOrigin", origin)
	end
	local base = origin :: UDim2
	local px = pixels or 6
	task.spawn(function()
		for i = 1, (cycles or 3) * 2 do
			local dir = if i % 2 == 0 then -1 else 1
			gui.Position = base + UDim2.fromOffset(px * dir, 0)
			task.wait(0.04)
		end
		gui.Position = base
	end)
end

-- Slide a panel in from an offset while fading its GroupTransparency (CanvasGroup) or simply
-- moving it (Frame). `hidden` is the off-screen position, `shown` the resting one.
function Motion.slide(gui: GuiObject, hidden: UDim2, shown: UDim2, visible: boolean)
	if visible then
		gui.Visible = true
		if Motion.reduced() then
			gui.Position = shown
			return
		end
		gui.Position = hidden
		Motion.tween(gui, Motion.T.panelIn, { Position = shown }, Enum.EasingStyle.Back)
	else
		if Motion.reduced() then
			gui.Visible = false
			return
		end
		local tween =
			Motion.tween(gui, Motion.T.panelOut, { Position = hidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				gui.Visible = false
			end
		end)
	end
end

-- Counts a number label up/down to `target` using `format`.
local counters: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
function Motion.countTo(label: TextLabel, target: number, format: (number) -> string, seconds: number?)
	local from = counters[label]
	counters[label] = target
	if from == nil or from == target or Motion.reduced() then
		label.Text = format(target)
		return
	end
	local token = (tokens[label] or 0) + 1
	tokens[label] = token
	local duration = seconds or Motion.T.countUp
	local start = os.clock()
	task.spawn(function()
		while tokens[label] == token do
			local t = math.min((os.clock() - start) / duration, 1)
			local eased = 1 - (1 - t) * (1 - t)
			label.Text = format(math.floor((from :: number) + (target - (from :: number)) * eased + 0.5))
			if t >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Gentle repeating pulse; returns a stop function.
function Motion.pulse(gui: GuiObject, amount: number?, period: number?): () -> ()
	local scale = Motion.scaleOf(gui)
	if Motion.reduced() then
		return function() end
	end
	local running = true
	task.spawn(function()
		while running and gui.Parent do
			Motion.tween(
				scale,
				(period or 0.6) / 2,
				{ Scale = amount or 1.06 },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			task.wait((period or 0.6) / 2)
			Motion.tween(scale, (period or 0.6) / 2, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait((period or 0.6) / 2)
		end
	end)
	return function()
		running = false
		scale.Scale = 1
	end
end

return Motion
