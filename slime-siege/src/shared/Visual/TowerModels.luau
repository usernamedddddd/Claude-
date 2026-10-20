--!strict
-- Builds chunky, cartoony tower models out of primitive parts (no meshes needed for the MVP).
-- Used by the server for real towers and by the client for the placement ghost.

local TowerData = require(script.Parent.Parent.Data.TowerData)

local TowerModels = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(30, 30, 40)
local GOLD = Color3.fromRGB(255, 200, 60)

type Builder = {
	model: Model,
	add: (shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?) -> BasePart,
}

local function newBuilder(name: string): Builder
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root

	local builder = { model = model } :: Builder
	builder.add = function(shape, size, offset, color, material)
		local part = Instance.new("Part")
		part.Size = size
		if shape == Enum.PartType.Ball and (size.X ~= size.Y or size.Y ~= size.Z) then
			-- Ball parts are forced uniform; a sphere mesh on a block gives a squashed ellipsoid.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		else
			part.Shape = shape
		end
		part.CFrame = offset
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end
	return builder
end

local function eyes(b: Builder, y: number, z: number, spread: number, size: number)
	for _, side in { -1, 1 } do
		b.add(Enum.PartType.Ball, Vector3.one * size, CFrame.new(side * spread, y, z), WHITE)
		b.add(Enum.PartType.Ball, Vector3.one * size * 0.5, CFrame.new(side * spread, y, z - size * 0.35), BLACK)
	end
end

local function pedestal(b: Builder, radius: number, color: Color3)
	b.add(
		Enum.PartType.Cylinder,
		Vector3.new(0.6, radius * 2, radius * 2),
		CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color:Lerp(WHITE, 0.55)
	)
end

local BUILDERS: { [string]: (Builder, Color3) -> () } = {
	DartFrog = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 1.6, 0), color)
		b.add(Enum.PartType.Ball, Vector3.new(2, 1.2, 2), CFrame.new(0, 1.1, -0.3), color:Lerp(WHITE, 0.4))
		eyes(b, 2.7, -0.6, 0.6, 0.8)
		b.add(Enum.PartType.Block, Vector3.new(0.2, 0.2, 1.4), CFrame.new(0, 1.7, -1.4), Color3.fromRGB(255, 110, 140))
	end,
	CannonCrab = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(3.2, 1.8, 2.6), CFrame.new(0, 1.3, 0), color)
		for _, side in { -1, 1 } do
			b.add(Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), CFrame.new(side * 1.9, 1.3, -0.9), color)
			b.add(Enum.PartType.Block, Vector3.new(0.4, 0.3, 0.9), CFrame.new(side * 1.9, 1.6, -1.5), color)
		end
		b.add(
			Enum.PartType.Cylinder,
			Vector3.new(1.6, 1, 1),
			CFrame.new(0, 2.3, -0.3) * CFrame.Angles(0, math.rad(90), math.rad(25)),
			Color3.fromRGB(70, 70, 80),
			Enum.Material.Metal
		)
		eyes(b, 2.2, -1, 0.7, 0.55)
	end,
	IcePenguin = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(2.2, 3, 2.2), CFrame.new(0, 1.9, 0), Color3.fromRGB(40, 50, 70))
		b.add(Enum.PartType.Ball, Vector3.new(1.7, 2.4, 1.2), CFrame.new(0, 1.8, -0.55), WHITE)
		b.add(Enum.PartType.Block, Vector3.new(0.5, 0.3, 0.7), CFrame.new(0, 2.5, -1.2), Color3.fromRGB(255, 170, 40))
		eyes(b, 2.9, -0.8, 0.45, 0.5)
		b.add(Enum.PartType.Ball, Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 3.6, 0), color, Enum.Material.Ice)
	end,
	SpikeTurtle = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(3.2, 1.8, 3.2), CFrame.new(0, 1.1, 0), color)
		for i = 0, 5 do
			local a = math.rad(i * 60)
			b.add(
				Enum.PartType.Block,
				Vector3.new(0.35, 0.8, 0.35),
				CFrame.new(math.cos(a) * 1.1, 1.9, math.sin(a) * 1.1) * CFrame.Angles(0, -a, math.rad(25)),
				Color3.fromRGB(230, 230, 210),
				Enum.Material.Metal
			)
		end
		b.add(Enum.PartType.Ball, Vector3.new(1, 0.9, 1), CFrame.new(0, 0.9, -1.7), Color3.fromRGB(150, 210, 120))
		eyes(b, 1.1, -2.1, 0.25, 0.35)
	end,
	BankBee = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(2.4, 2.4, 3), CFrame.new(0, 2, 0), color)
		for _, z in { -0.2, 0.6 } do
			b.add(
				Enum.PartType.Cylinder,
				Vector3.new(0.35, 2.45, 2.45),
				CFrame.new(0, 2, z) * CFrame.Angles(0, math.rad(90), 0),
				BLACK
			)
		end
		for _, side in { -1, 1 } do
			local wing = b.add(
				Enum.PartType.Ball,
				Vector3.new(1.8, 0.2, 1.2),
				CFrame.new(side * 1.3, 3.2, 0.2) * CFrame.Angles(0, 0, math.rad(side * 25)),
				WHITE,
				Enum.Material.Glass
			)
			wing.Transparency = 0.35
		end
		eyes(b, 2.3, -1.3, 0.5, 0.55)
		b.add(Enum.PartType.Block, Vector3.new(1.4, 0.3, 1.4), CFrame.new(0, 0.75, 0), GOLD, Enum.Material.Neon)
	end,
	WizardOwl = function(b, color)
		b.add(Enum.PartType.Ball, Vector3.new(2.4, 2.8, 2.2), CFrame.new(0, 1.9, 0), color)
		b.add(Enum.PartType.Ball, Vector3.new(1.8, 1.8, 1), CFrame.new(0, 1.6, -0.75), color:Lerp(WHITE, 0.5))
		eyes(b, 2.6, -0.9, 0.5, 0.75)
		b.add(
			Enum.PartType.Cylinder,
			Vector3.new(0.3, 2.4, 2.4),
			CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color:Lerp(BLACK, 0.4)
		)
		b.add(
			Enum.PartType.Block,
			Vector3.new(1.1, 1.4, 1.1),
			CFrame.new(0, 3.9, 0) * CFrame.Angles(0, math.rad(45), math.rad(10)),
			color:Lerp(BLACK, 0.4)
		)
		b.add(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.3, 4.7, 0), GOLD, Enum.Material.Neon)
	end,
}

-- Builds a model at the origin facing -Z. Caller sets the pivot.
function TowerModels.build(towerId: string, options: { vip: boolean? }?): Model
	local def = TowerData[towerId]
	assert(def, `unknown tower {towerId}`)
	local color = rgb(def.color)
	if options and options.vip then
		color = GOLD
	end
	local b = newBuilder(towerId)
	pedestal(b, def.footprint, color)
	local build = BUILDERS[towerId]
	if build then
		build(b, color)
	end
	if options and options.vip then
		for _, part in b.model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Root" and part.Color == GOLD then
				part.Material = Enum.Material.Foil
			end
		end
	end
	return b.model
end

-- Small glowing pips above the tower show upgrade tiers (left = path A, right = path B).
function TowerModels.setTierPips(model: Model, tierA: number, tierB: number)
	local existing = model:FindFirstChild("Pips")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pips"
	local pivot = model:GetPivot()
	for path, tiers in { tierA, tierB } do
		for i = 1, tiers do
			local pip = Instance.new("Part")
			pip.Shape = Enum.PartType.Ball
			pip.Size = Vector3.one * 0.45
			pip.Material = Enum.Material.Neon
			pip.Color = if path == 1 then Color3.fromRGB(255, 120, 200) else Color3.fromRGB(110, 200, 255)
			pip.Anchored = true
			pip.CanCollide = false
			pip.CanTouch = false
			pip.CanQuery = false
			local x = (if path == 1 then -1 else 1) * (0.5 + (i - 1) * 0.55)
			pip.CFrame = pivot * CFrame.new(x, 5, 0)
			pip.Parent = folder
		end
	end
	folder.Parent = model
end

-- Makes every part of a model semi-transparent and non-queryable (placement ghost).
function TowerModels.makeGhost(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CastShadow = false
			if part.Name ~= "Root" then
				part.Transparency = math.max(part.Transparency, 0.45)
			end
		end
	end
end

return TowerModels
