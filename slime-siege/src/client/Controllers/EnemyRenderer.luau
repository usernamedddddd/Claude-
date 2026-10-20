--!strict
-- Renders slimes from the server's 10 Hz snapshots. Slimes are pooled Ball parts moved in one
-- Workspace:BulkMoveTo call per frame; positions are interpolated between snapshots using
-- the shared path math, so the client never simulates gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Data.Config)
local MapData = require(Shared.Data.MapData)
local SlimeData = require(Shared.Data.SlimeData)
local Path = require(Shared.Sim.Path)
local Packet = require(Shared.Net.Packet)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(Shared.Data.Theme)

local Effects = require(script.Parent.Effects)

local EnemyRenderer = {}

local HIDDEN = CFrame.new(0, -1000, 0)
local SNAPSHOT_INTERVAL = 1 / Config.NET_SNAPSHOT_HZ
local FACE_TEXTURE = "rbxasset://textures/face.png"
local SLIME_MESH = Theme.Meshes.slime
local USE_MESH = SLIME_MESH.meshId ~= "" -- art/blender/make_slime.py, once uploaded

type Record = {
	id: number,
	kind: string,
	part: BasePart,
	size: number,
	prevDistance: number,
	nextDistance: number,
	flags: number,
	phase: number,
	camo: boolean,
}

local path = Path.build(MapData.waypoints)
local records: { [number]: Record } = {}
local pool: { BasePart } = {}
local folder: Folder
local lastSnapshotAt = os.clock()
local decodedEvents: { Packet.DecodedEvent } = {}
local decodedEnemies: { Packet.DecodedEnemy } = {}
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local hideQueue: { BasePart } = {}
local elapsed = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local meshOf: { [BasePart]: SpecialMesh } = {}

local function newPart(): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = HIDDEN
	if USE_MESH then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = SLIME_MESH.meshId
		mesh.TextureId = SLIME_MESH.textureId
		mesh.Parent = part
		meshOf[part] = mesh
	else
		part.Shape = Enum.PartType.Ball
		local face = Instance.new("Decal")
		face.Name = "Face"
		face.Texture = FACE_TEXTURE
		face.Face = Enum.NormalId.Front
		face.Parent = part
	end
	part.Parent = folder
	return part
end

-- With a textured mesh, the slime colour tints the texture so the face stays dark.
local function setColor(part: BasePart, color: Color3)
	part.Color = color
	local mesh = meshOf[part]
	if mesh then
		mesh.VertexColor = Vector3.new(color.R, color.G, color.B)
	end
end

local function styleFor(record: Record)
	local part = record.part
	local def = SlimeData[record.kind]
	setColor(part, rgb(def.color))
	part.Size = Vector3.one * def.size
	local mesh = meshOf[part]
	if mesh then
		mesh.Scale = Vector3.one * (def.size / SLIME_MESH.nativeSize)
	end
	local frozen = bit32.band(record.flags, 1) ~= 0
	if record.camo then
		part.Material = Enum.Material.ForceField
		part.Transparency = 0
	elseif frozen then
		part.Material = Enum.Material.Ice
		part.Transparency = 0
	elseif record.kind == "Metal" then
		part.Material = Enum.Material.DiamondPlate
		part.Transparency = 0
	elseif record.kind == "Rainbow" then
		part.Material = Enum.Material.Neon
		part.Transparency = 0
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0.05
	end
end

local function spawnRecord(id: number, kind: string, camo: boolean, distance: number)
	local def = SlimeData[kind]
	if not def or records[id] then
		return
	end
	local part = table.remove(pool) or newPart()
	local record: Record = {
		id = id,
		kind = kind,
		part = part,
		size = def.size,
		prevDistance = distance,
		nextDistance = distance,
		flags = 0,
		phase = (id * 0.618) % 1 * math.pi * 2,
		camo = camo,
	}
	records[id] = record
	styleFor(record)
end

local function currentDistance(record: Record, alpha: number): number
	return record.prevDistance + (record.nextDistance - record.prevDistance) * alpha
end

local function worldPosition(record: Record): Vector3
	local x, z = Path.positionAt(path, record.nextDistance)
	return Vector3.new(x, MapData.groundY, z)
end

local function release(record: Record)
	records[record.id] = nil
	-- The part returns to the pool only after render() has parked it out of sight.
	table.insert(hideQueue, record.part)
end

local function clearAll()
	for _, record in records do
		release(record)
	end
end

local function onSnapshot(packet: unknown)
	if typeof(packet) ~= "buffer" then
		return
	end
	local now = os.clock()
	local alpha = math.clamp((now - lastSnapshotAt) / SNAPSHOT_INTERVAL, 0, 1)
	Packet.decodeSnapshot(packet :: buffer, decodedEvents, decodedEnemies)

	for _, ev in decodedEvents do
		local t = ev.t
		if t == Packet.SPAWN then
			spawnRecord(ev.id, ev.kind or "Green", ev.camo == true, ev.distance or 0)
		elseif t == Packet.POP then
			local record = records[ev.id]
			if record then
				Effects.pop(record.kind, worldPosition(record), ev.tower or 0)
				release(record)
			end
		elseif t == Packet.LEAK then
			local record = records[ev.id]
			if record then
				Effects.leak()
				release(record)
			end
		elseif t == Packet.ATTACK then
			Effects.attack(ev.tower or 0, ev.visual or "dart", ev.x or 0, ev.z or 0)
		elseif t == Packet.CHAIN then
			Effects.chain(ev.x or 0, ev.z or 0, ev.x2 or 0, ev.z2 or 0)
		elseif t == Packet.CLEAR then
			clearAll()
		end
	end

	for _, e in decodedEnemies do
		local record = records[e.id]
		if record then
			record.prevDistance = currentDistance(record, alpha)
			record.nextDistance = e.distance
			if record.flags ~= e.flags then
				record.flags = e.flags
				styleFor(record)
			end
		end
	end
	lastSnapshotAt = now
end

local function render(dt: number)
	elapsed += dt
	local alpha = math.clamp((os.clock() - lastSnapshotAt) / SNAPSHOT_INTERVAL, 0, 1)
	table.clear(parts)
	table.clear(cframes)
	for _, part in hideQueue do
		table.insert(parts, part)
		table.insert(cframes, HIDDEN)
		table.insert(pool, part)
	end
	table.clear(hideQueue)

	local y0 = MapData.groundY
	for _, record in records do
		local d = currentDistance(record, alpha)
		local x, z, dx, dz = Path.positionAt(path, d)
		local frozen = bit32.band(record.flags, 1) ~= 0
		local hop = if frozen then 0 else math.abs(math.sin(elapsed * 7 + record.phase)) * record.size * 0.35
		local pos = Vector3.new(x, y0 + record.size * 0.5 + hop, z)
		table.insert(parts, record.part)
		table.insert(cframes, CFrame.lookAt(pos, pos + Vector3.new(dx, 0, dz)))
		if record.kind == "Rainbow" and not record.camo then
			setColor(record.part, Color3.fromHSV((elapsed * 0.4 + record.phase / 6.283) % 1, 0.65, 1))
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer.count(): number
	local n = 0
	for _ in records do
		n += 1
	end
	return n
end

function EnemyRenderer.start()
	local f = Instance.new("Folder")
	f.Name = "ClientSlimes"
	f.Parent = Workspace
	folder = f
	-- Pre-warm the pool so the first big wave doesn't hitch.
	for _ = 1, 150 do
		table.insert(pool, newPart())
	end
	Remotes.get("Snapshot").OnClientEvent:Connect(onSnapshot)
	RunService.RenderStepped:Connect(render)
end

return EnemyRenderer
