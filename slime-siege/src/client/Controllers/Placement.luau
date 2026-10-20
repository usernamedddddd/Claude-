--!strict
-- World input: tower placement (ghost preview + range circle, green = valid / red = invalid)
-- and tower selection. Works with mouse, touch (tap to aim, then confirm) and gamepad
-- (aim with the screen-centre cursor, A to place, B to cancel, X to select a tower).
-- The client check is only a preview; the server re-validates every placement.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapData = require(Shared.Data.MapData)
local TowerData = require(Shared.Data.TowerData)
local Path = require(Shared.Sim.Path)
local Placement = require(Shared.Sim.Placement)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local TowerModels = require(Shared.Visual.TowerModels)

local CameraController = require(script.Parent.CameraController)
local Sound = require(script.Parent.Sound)
local Store = require(script.Parent.Store)
local Towers = require(script.Parent.Towers)

local PlacementController = {}

export type InputMode = "mouse" | "touch" | "gamepad"

PlacementController.changed = Signal.new() -- placing state / validity changed
PlacementController.selected = Signal.new() :: Signal.Signal<Model?>
PlacementController.inputModeChanged = Signal.new() :: Signal.Signal<InputMode>

local path = Path.build(MapData.waypoints)
local placingId: string? = nil
local ghost: Model? = nil
local rangeDisc: Part
local selectionDisc: Part
local aimPoint: Vector3? = nil
local valid = false
local reason: string? = nil
local selectedModel: Model? = nil
local inputMode: InputMode = "mouse"
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local towerRayParams = RaycastParams.new()
towerRayParams.FilterType = Enum.RaycastFilterType.Include

local VALID_COLOR = Color3.fromRGB(90, 230, 110)
local INVALID_COLOR = Color3.fromRGB(255, 80, 90)

local function classify(inputType: Enum.UserInputType): InputMode?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	elseif string.find(inputType.Name, "Gamepad") then
		return "gamepad"
	elseif
		inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.Keyboard
	then
		return "mouse"
	end
	return nil
end

function PlacementController.inputMode(): InputMode
	return inputMode
end

function PlacementController.isPlacing(): boolean
	return placingId ~= nil
end

function PlacementController.placingId(): string?
	return placingId
end

function PlacementController.status(): (boolean, string?)
	return valid, reason
end

local function makeDisc(name: string): Part
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.75
	disc.Size = Vector3.new(0.15, 1, 1)
	disc.CFrame = CFrame.new(0, -1000, 0)
	disc.Parent = Workspace
	return disc
end

local function placeDisc(disc: Part, position: Vector3, radius: number, color: Color3)
	disc.Size = Vector3.new(0.15, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(position.X, MapData.groundY + 0.25, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = color
end

local function hideDisc(disc: Part)
	disc.CFrame = CFrame.new(0, -1000, 0)
end

local function groundFromScreen(x: number, y: number): Vector3?
	local ray = Workspace.CurrentCamera:ViewportPointToRay(x, y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	return if result then result.Position else nil
end

local function groundFromRay(ray: Ray): Vector3?
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	return if result then result.Position else nil
end

local function towerFromScreen(x: number, y: number): Model?
	local ray = Workspace.CurrentCamera:ViewportPointToRay(x, y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, towerRayParams)
	return if result then Towers.modelFromPart(result.Instance) else nil
end

function PlacementController.select(model: Model?)
	selectedModel = model
	if model then
		local range = model:GetAttribute("Range")
		placeDisc(
			selectionDisc,
			model:GetPivot().Position,
			if type(range) == "number" then range else 0,
			Color3.fromRGB(255, 255, 255)
		)
	else
		hideDisc(selectionDisc)
	end
	PlacementController.selected:Fire(model)
end

function PlacementController.cancel()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	placingId = nil
	aimPoint = nil
	hideDisc(rangeDisc)
	ContextActionService:UnbindAction("SlimePlaceConfirm")
	ContextActionService:UnbindAction("SlimePlaceCancel")
	PlacementController.changed:Fire()
end

function PlacementController.confirm()
	if not placingId or not aimPoint then
		return
	end
	if not valid then
		Sound.play("error")
		return
	end
	local point = aimPoint :: Vector3
	Remotes.get("PlaceTower"):FireServer(placingId, point.X, point.Z)
	local keepPlacing = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	if not keepPlacing then
		PlacementController.cancel()
	end
end

function PlacementController.begin(towerId: string)
	if not TowerData[towerId] then
		return
	end
	PlacementController.cancel()
	PlacementController.select(nil)
	placingId = towerId
	local model = TowerModels.build(towerId)
	TowerModels.makeGhost(model)
	model.Parent = Workspace
	ghost = model
	if inputMode == "gamepad" then
		GuiService.SelectedObject = nil
	end
	ContextActionService:BindActionAtPriority("SlimePlaceConfirm", function(_, state)
		if state == Enum.UserInputState.Begin then
			PlacementController.confirm()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("SlimePlaceCancel", function(_, state)
		if state == Enum.UserInputState.Begin then
			PlacementController.cancel()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape, Enum.KeyCode.Q)
	PlacementController.changed:Fire()
end

local function updateGhost()
	if not placingId or not ghost then
		return
	end
	if inputMode == "mouse" then
		-- GetMouseLocation is in viewport space, which is what ViewportPointToRay expects.
		local mouse = UserInputService:GetMouseLocation()
		aimPoint = groundFromScreen(mouse.X, mouse.Y)
	elseif inputMode == "gamepad" then
		aimPoint = groundFromRay(CameraController.centerRay())
	end
	local def = TowerData[placingId :: string]
	local wasValid, oldReason = valid, reason
	if aimPoint then
		local p = aimPoint :: Vector3
		valid, reason = Placement.check(MapData, path, Towers.footprints(), def.footprint, p.X, p.Z)
		if valid and Store.cash() < def.cost then
			valid, reason = false, "Not enough cash"
		end
		ghost:PivotTo(CFrame.new(p.X, MapData.groundY, p.Z))
		placeDisc(
			rangeDisc,
			p,
			def.base.attacks[1] and def.base.attacks[1].range or def.footprint,
			if valid then VALID_COLOR else INVALID_COLOR
		)
	else
		valid, reason = false, "Aim at the garden"
		ghost:PivotTo(CFrame.new(0, -1000, 0))
		hideDisc(rangeDisc)
	end
	if valid ~= wasValid or reason ~= oldReason then
		PlacementController.changed:Fire()
	end
end

local function setInputMode(mode: InputMode)
	if mode ~= inputMode then
		inputMode = mode
		PlacementController.inputModeChanged:Fire(mode)
	end
end

function PlacementController.start()
	rangeDisc = makeDisc("PlacementRange")
	selectionDisc = makeDisc("SelectionRange")
	local map = Workspace:WaitForChild("Map")
	rayParams.FilterDescendantsInstances = { map }
	towerRayParams.FilterDescendantsInstances = { Workspace:WaitForChild("Towers") }

	setInputMode(classify(UserInputService:GetLastInputType()) or "mouse")
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local mode: InputMode? = classify(inputType)
		if mode then
			setInputMode(mode)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if placingId then
				PlacementController.confirm()
			else
				local mouse = UserInputService:GetMouseLocation()
				PlacementController.select(towerFromScreen(mouse.X, mouse.Y))
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and placingId then
			PlacementController.cancel()
		elseif input.KeyCode == Enum.KeyCode.ButtonX and not placingId then
			-- Gamepad: select the tower nearest the screen-centre cursor.
			local point = groundFromRay(CameraController.centerRay())
			local best: Model? = nil
			local bestDist = 8
			if point then
				for _, model in Towers.byUid do
					local d = (model:GetPivot().Position - point).Magnitude
					if d < bestDist then
						best, bestDist = model, d
					end
				end
			end
			PlacementController.select(best)
		end
	end)

	UserInputService.TouchTapInWorld:Connect(function(position, processed)
		if processed then
			return
		end
		if placingId then
			aimPoint = groundFromScreen(position.X, position.Y)
			updateGhost()
		else
			PlacementController.select(towerFromScreen(position.X, position.Y))
		end
	end)

	Towers.removed:Connect(function(uid)
		if selectedModel and selectedModel:GetAttribute("Uid") == uid then
			PlacementController.select(nil)
		end
	end)
	RunService.RenderStepped:Connect(function()
		updateGhost()
		if selectedModel and selectedModel.Parent then
			local range = selectedModel:GetAttribute("Range")
			placeDisc(
				selectionDisc,
				selectedModel:GetPivot().Position,
				if type(range) == "number" then range else 0,
				Color3.fromRGB(255, 255, 255)
			)
		end
	end)
end

return PlacementController
