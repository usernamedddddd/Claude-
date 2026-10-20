--!strict
-- Top-down angled match camera. Rotate / zoom / pan with:
--   mouse: right-drag rotate, wheel zoom, WASD / arrows pan
--   touch: pinch zoom, two-finger twist rotate, two-finger drag pan
--   gamepad: right stick rotate (X) and zoom (Y), left stick pan

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MapData = require(ReplicatedStorage:WaitForChild("Shared").Data.MapData)
local Prefs = require(script.Parent.Prefs)

local CameraController = {}

local PITCH = math.rad(55)
local MIN_ZOOM, MAX_ZOOM = 45, 175
local PAN_SPEED = 60 -- studs per second at default zoom
local DEADZONE = 0.15

local focus = Vector3.new(MapData.cameraFocus.x, MapData.groundY, MapData.cameraFocus.z)
local yaw = 0
local zoom = 130
local targetZoom = zoom
local shakeTime, shakeDuration, shakeStrength = 0, 0, 0
local rightDragging = false
local gamepadPan = Vector2.zero
local gamepadLook = Vector2.zero
local rng = Random.new()

function CameraController.shake(strength: number, duration: number)
	if not Prefs.shake then
		return
	end
	if strength >= shakeStrength * (1 - shakeTime / math.max(shakeDuration, 0.001)) then
		shakeStrength = strength
		shakeDuration = duration
		shakeTime = 0
	end
end

-- Screen-space point the gamepad cursor uses (centre of the viewport).
function CameraController.centerRay(): Ray
	local camera = Workspace.CurrentCamera
	local size = camera.ViewportSize
	return camera:ViewportPointToRay(size.X / 2, size.Y / 2)
end

local function clampFocus()
	local b = MapData.bounds
	focus = Vector3.new(math.clamp(focus.X, b.minX, b.maxX), MapData.groundY, math.clamp(focus.Z, b.minZ, b.maxZ))
end

local function pan(dx: number, dz: number)
	-- dx/dz are in camera-relative axes
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	focus += right * dx + forward * dz
	clampFocus()
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local keyX, keyZ = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			keyZ += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			keyZ -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			keyX += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			keyX -= 1
		end
	end
	local panScale = PAN_SPEED * (zoom / 120) * dt
	pan((keyX + gamepadPan.X) * panScale, (keyZ + gamepadPan.Y) * panScale)
	yaw -= gamepadLook.X * 2.2 * dt
	targetZoom = math.clamp(targetZoom - gamepadLook.Y * 90 * dt, MIN_ZOOM, MAX_ZOOM)

	zoom += (targetZoom - zoom) * math.min(dt * 10, 1)
	local offset = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-PITCH, 0, 0) * Vector3.new(0, 0, zoom)
	local cf = CFrame.lookAt(focus + offset, focus)

	if shakeTime < shakeDuration then
		shakeTime += dt
		local fade = 1 - shakeTime / shakeDuration
		local s = shakeStrength * fade
		cf *= CFrame.new(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)
	end
	camera.CFrame = cf
	camera.Focus = CFrame.new(focus)
end

function CameraController.start()
	RunService:BindToRenderStep("SlimeCamera", Enum.RenderPriority.Camera.Value + 1, update)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			rightDragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDragging = false
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadPan = Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.zero
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseMovement and rightDragging then
			yaw -= input.Delta.X * 0.008
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			targetZoom = math.clamp(targetZoom - input.Position.Z * 10, MIN_ZOOM, MAX_ZOOM)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local v = Vector2.new(input.Position.X, input.Position.Y)
			gamepadPan = if v.Magnitude > DEADZONE then v else Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, input.Position.Y)
			gamepadLook = if v.Magnitude > DEADZONE then v else Vector2.zero
		end
	end)

	local pinchStartZoom = zoom
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartZoom = targetZoom
		elseif state == Enum.UserInputState.Change then
			-- `scale` is relative to the start of the gesture.
			targetZoom = math.clamp(pinchStartZoom / math.max(scale, 0.05), MIN_ZOOM, MAX_ZOOM)
		end
	end)
	UserInputService.TouchRotate:Connect(function(_positions, rotation, _velocity, state, processed)
		if not processed and state == Enum.UserInputState.Change then
			yaw += math.rad(rotation) * 0.05
		end
	end)
	local lastPan: Vector2? = nil
	UserInputService.TouchPan:Connect(function(positions, translation, _velocity, state, processed)
		if processed or #positions < 2 then
			lastPan = nil
			return
		end
		local previous = lastPan
		if previous == nil or state == Enum.UserInputState.Begin then
			lastPan = translation
			return
		end
		local delta = (translation :: Vector2) - (previous :: Vector2)
		lastPan = translation
		local scale = zoom / 600
		pan(-delta.X * scale, delta.Y * scale)
		if state == Enum.UserInputState.End then
			lastPan = nil
		end
	end)
end

return CameraController
