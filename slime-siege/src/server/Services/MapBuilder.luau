--!strict
-- Builds the "Candy Garden" match map and the lobby out of parts, from Data/MapData.
-- Ground/path are queryable so the client's placement raycast hits them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapData = require(Shared.Data.MapData)

local MapBuilder = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local CANDY = {
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(120, 230, 160),
}

local function decoration(parent: Instance, blocker: MapData.Blocker, index: number)
	local y = MapData.groundY
	local base = CFrame.new(blocker.x, y, blocker.z)
	local color = CANDY[(index - 1) % #CANDY + 1]
	local model = Instance.new("Model")
	model.Name = blocker.kind
	if blocker.kind == "Lollipop" then
		part({
			Name = "Stick",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(7, 0.6, 0.6),
			CFrame = base * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 255, 255),
			Parent = model,
		})
		part({
			Name = "Candy",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, blocker.r * 2, blocker.r * 2),
			CFrame = base * CFrame.new(0, 7 + blocker.r * 0.6, 0) * CFrame.Angles(0, math.rad(90), 0),
			Color = color,
			Parent = model,
		})
		part({
			Name = "Swirl",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.1, blocker.r * 1.1, blocker.r * 1.1),
			CFrame = base * CFrame.new(0, 7 + blocker.r * 0.6, 0) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(255, 255, 255),
			Parent = model,
		})
	elseif blocker.kind == "Cupcake" then
		part({
			Name = "Cup",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, blocker.r * 2, blocker.r * 2),
			CFrame = base * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 190, 120),
			Parent = model,
		})
		part({
			Name = "Frosting",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * blocker.r * 2.1,
			CFrame = base * CFrame.new(0, 3.4, 0),
			Color = color,
			Parent = model,
		})
		part({
			Name = "Cherry",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = base * CFrame.new(0, 3.6 + blocker.r, 0),
			Color = Color3.fromRGB(230, 40, 60),
			Parent = model,
		})
	else
		part({
			Name = "Gumdrop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * blocker.r * 2,
			CFrame = base * CFrame.new(0, blocker.r * 0.4, 0),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Parent = model,
		})
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	model.Parent = parent
end

function MapBuilder.buildMatchMap(): Model
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = Instance.new("Model")
	map.Name = "Map"
	local b = MapData.bounds
	local y = MapData.groundY
	local width, depth = b.maxX - b.minX, b.maxZ - b.minZ
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2

	part({
		Name = "Ground",
		Size = Vector3.new(width, 2, depth),
		CFrame = CFrame.new(cx, y - 1, cz),
		Color = Color3.fromRGB(160, 230, 140),
		Material = Enum.Material.Grass,
		Parent = map,
	})
	-- Frosting border so the board reads as a cake top.
	part({
		Name = "Border",
		Size = Vector3.new(width + 8, 3, depth + 8),
		CFrame = CFrame.new(cx, y - 1.6, cz),
		Color = Color3.fromRGB(255, 214, 236),
		CanQuery = false,
		Parent = map,
	})
	part({
		Name = "Cake",
		Size = Vector3.new(width + 8, 18, depth + 8),
		CFrame = CFrame.new(cx, y - 12, cz),
		Color = Color3.fromRGB(190, 120, 80),
		CanQuery = false,
		Parent = map,
	})

	local pathFolder = Instance.new("Folder")
	pathFolder.Name = "Path"
	pathFolder.Parent = map
	local w = MapData.pathWidth
	for i = 1, #MapData.waypoints - 1 do
		local a, c = MapData.waypoints[i], MapData.waypoints[i + 1]
		local from = Vector3.new(a.x, y + 0.05, a.z)
		local to = Vector3.new(c.x, y + 0.05, c.z)
		local length = (to - from).Magnitude
		part({
			Name = `Segment{i}`,
			Size = Vector3.new(w, 0.2, length + w),
			CFrame = CFrame.lookAt((from + to) / 2, to),
			Color = if i % 2 == 0 then Color3.fromRGB(255, 196, 222) else Color3.fromRGB(255, 186, 214),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = pathFolder,
		})
		-- Candy-stripe edges
		for _, side in { -1, 1 } do
			part({
				Name = "Edge",
				Size = Vector3.new(0.5, 0.35, length + w),
				CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.new(side * (w / 2 + 0.25), 0.05, 0),
				Color = Color3.fromRGB(255, 255, 255),
				CanCollide = false,
				CanQuery = false,
				Parent = pathFolder,
			})
		end
	end

	local first, last = MapData.waypoints[1], MapData.waypoints[#MapData.waypoints]
	part({
		Name = "StartPortal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 9, 9),
		CFrame = CFrame.new(first.x, y + 3.5, first.z) * CFrame.Angles(0, 0, 0),
		Color = Color3.fromRGB(110, 230, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanCollide = false,
		CanQuery = false,
		Parent = map,
	})
	part({
		Name = "EndCastle",
		Size = Vector3.new(4, 8, 10),
		CFrame = CFrame.new(last.x - 1, y + 4, last.z),
		Color = Color3.fromRGB(255, 160, 200),
		CanCollide = false,
		CanQuery = false,
		Parent = map,
	})

	local decorations = Instance.new("Folder")
	decorations.Name = "Decorations"
	decorations.Parent = map
	for i, blocker in MapData.blockers do
		decoration(decorations, blocker, i)
	end

	map.Parent = Workspace
	return map
end

export type Lobby = { model: Model, pad: BasePart, padLabel: TextLabel, spawn: SpawnLocation }

function MapBuilder.buildLobby(): Lobby
	local model = Instance.new("Model")
	model.Name = "Lobby"
	part({
		Name = "Floor",
		Size = Vector3.new(90, 2, 90),
		CFrame = CFrame.new(0, -1, 0),
		Color = Color3.fromRGB(255, 220, 238),
		Parent = model,
	})
	for i = 0, 7 do
		local a = math.rad(i * 45)
		part({
			Name = "Gumdrop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 6,
			CFrame = CFrame.new(math.cos(a) * 38, 1, math.sin(a) * 38),
			Color = CANDY[i % #CANDY + 1],
			Material = Enum.Material.Glass,
			Parent = model,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, 20)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model

	local pad = part({
		Name = "QueuePad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 14, 14),
		CFrame = CFrame.new(0, 0.3, -15) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 230, 140),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 4)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.Text = "Step here to play!"
	label.Parent = billboard

	model.Parent = Workspace
	return { model = model, pad = pad, padLabel = label, spawn = spawn }
end

return MapBuilder
