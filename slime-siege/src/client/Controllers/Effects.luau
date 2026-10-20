--!strict
-- Game feel ("juice"): pooled projectiles, pop particles + squish sounds on every layer pop,
-- screen shake on boss pops, placement thump, upgrade sparkle and "+$" cash popups.
-- Everything is pooled and budgeted per frame so 300+ slimes stay at 60 FPS on phones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapData = require(Shared.Data.MapData)
local SlimeData = require(Shared.Data.SlimeData)

local CameraController = require(script.Parent.CameraController)
local Sound = require(script.Parent.Sound)
local Towers = require(script.Parent.Towers)

local Effects = {}

local GROUND = MapData.groundY
local MAX_POP_BURSTS_PER_FRAME = 40
local MAX_PROJECTILES = 160
local HIDDEN = CFrame.new(0, -1000, 0)

local folder: Folder
local anchor: Part
local popEmitters: { [string]: { attachment: Attachment, emitter: ParticleEmitter } } = {}
local sparkle: { attachment: Attachment, emitter: ParticleEmitter }
local dust: { attachment: Attachment, emitter: ParticleEmitter }
local fire: { attachment: Attachment, emitter: ParticleEmitter }
local popsThisFrame = 0

---------------------------------------------------------------------------
-- Particles
---------------------------------------------------------------------------

local function makeEmitter(
	name: string,
	color: Color3,
	props: { [string]: any }
): { attachment: Attachment, emitter: ParticleEmitter }
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.2
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Drag = 3
	for k, v in props do
		(emitter :: any)[k] = v
	end
	emitter.Parent = attachment
	return { attachment = attachment, emitter = emitter }
end

local function burst(e: { attachment: Attachment, emitter: ParticleEmitter }, position: Vector3, count: number)
	e.attachment.WorldPosition = position
	e.emitter:Emit(count)
end

---------------------------------------------------------------------------
-- Projectiles (pooled parts moved with BulkMoveTo)
---------------------------------------------------------------------------

type Projectile = {
	part: BasePart,
	from: Vector3,
	to: Vector3,
	t: number,
	duration: number,
	arc: number,
}

local projectilePool: { BasePart } = {}
local activeProjectiles: { Projectile } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

type Style = { color: Color3, size: Vector3, material: Enum.Material, duration: number, arc: number }
local STYLES: { [string]: Style } = {
	dart = {
		color = Color3.fromRGB(255, 230, 120),
		size = Vector3.new(0.25, 0.25, 1.2),
		material = Enum.Material.SmoothPlastic,
		duration = 0.12,
		arc = 0,
	},
	bomb = {
		color = Color3.fromRGB(40, 40, 50),
		size = Vector3.new(0.9, 0.9, 0.9),
		material = Enum.Material.SmoothPlastic,
		duration = 0.32,
		arc = 4,
	},
	orb = {
		color = Color3.fromRGB(190, 120, 255),
		size = Vector3.new(0.7, 0.7, 0.7),
		material = Enum.Material.Neon,
		duration = 0.18,
		arc = 0,
	},
	firebolt = {
		color = Color3.fromRGB(255, 140, 40),
		size = Vector3.new(0.6, 0.6, 1.3),
		material = Enum.Material.Neon,
		duration = 0.15,
		arc = 0,
	},
	phoenix = {
		color = Color3.fromRGB(255, 90, 30),
		size = Vector3.new(0.8, 0.8, 1.6),
		material = Enum.Material.Neon,
		duration = 0.2,
		arc = 2,
	},
	firewall = {
		color = Color3.fromRGB(255, 120, 30),
		size = Vector3.new(1.2, 1.2, 1.2),
		material = Enum.Material.Neon,
		duration = 0.25,
		arc = 3,
	},
	cluster = {
		color = Color3.fromRGB(60, 60, 70),
		size = Vector3.new(0.5, 0.5, 0.5),
		material = Enum.Material.SmoothPlastic,
		duration = 0.2,
		arc = 2,
	},
}

local function acquireProjectile(style: Style): BasePart?
	local part = table.remove(projectilePool)
	if not part then
		if #activeProjectiles >= MAX_PROJECTILES then
			return nil
		end
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = HIDDEN
		p.Parent = folder
		part = p
	end
	local p = part :: BasePart
	p.Color = style.color
	p.Size = style.size
	p.Material = style.material
	return p
end

local function launch(visual: string, from: Vector3, to: Vector3)
	local style = STYLES[visual] or STYLES.dart
	local part = acquireProjectile(style)
	if not part then
		return
	end
	table.insert(
		activeProjectiles,
		{ part = part, from = from, to = to, t = 0, duration = style.duration, arc = style.arc }
	)
end

---------------------------------------------------------------------------
-- Rings (nova attacks) and chain zaps
---------------------------------------------------------------------------

local ringPool: { BasePart } = {}

local function ring(position: Vector3, radius: number, color: Color3, material: Enum.Material)
	local part = table.remove(ringPool)
	if not part then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		part = p
	end
	local p = part :: BasePart
	p.Color = color
	p.Material = material
	p.Transparency = 0.3
	p.Size = Vector3.new(0.3, 1, 1)
	p.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local tween = TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		p.CFrame = HIDDEN
		table.insert(ringPool, p)
	end)
	tween:Play()
end

local function zap(a: Vector3, b: Vector3)
	local part = table.remove(ringPool)
	if not part then
		return
	end
	local p = part :: BasePart
	p.Color = Color3.fromRGB(170, 140, 255)
	p.Material = Enum.Material.Neon
	p.Transparency = 0.1
	local length = (b - a).Magnitude
	p.Size = Vector3.new(length, 0.25, 0.25)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	task.delay(0.08, function()
		p.CFrame = HIDDEN
		table.insert(ringPool, p)
	end)
end

---------------------------------------------------------------------------
-- Cash popups (local player's towers only)
---------------------------------------------------------------------------

local pendingCash: { [number]: number } = {}
local popupPool: { BillboardGui } = {}
local cashFlushTimer = 0

local function cashPopup(model: Model, amount: number)
	local gui = table.remove(popupPool)
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromScale(4, 1.6)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 225, 70)
		label.TextStrokeColor3 = Color3.fromRGB(60, 30, 0)
		label.TextStrokeTransparency = 0
		label.Parent = g
		g.Parent = folder
		gui = g
	end
	local g = gui :: BillboardGui
	local label = g:FindFirstChild("Label") :: TextLabel
	label.Text = `+${amount}`
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0;
	(g :: any).Adornee = model.PrimaryPart
	g.StudsOffset = Vector3.new(0, 5.5, 0)
	g.Enabled = true
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(g, info, { StudsOffset = Vector3.new(0, 8, 0) }):Play()
	local fade = TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Once(function()
		g.Enabled = false;
		(g :: any).Adornee = nil
		table.insert(popupPool, g)
	end)
	fade:Play()
end

---------------------------------------------------------------------------
-- Public API (called by EnemyRenderer / Towers)
---------------------------------------------------------------------------

local function towerPosition(model: Model): Vector3
	return model:GetPivot().Position + Vector3.new(0, 2.2, 0)
end

local function ownedByMe(model: Model): boolean
	return model:GetAttribute("Owner") == Players.LocalPlayer.UserId
end

function Effects.pop(kind: string, position: Vector3, towerUid: number)
	local def = SlimeData[kind]
	if kind == "Boss" then
		burst(popEmitters.Boss, position, 120)
		Sound.play("bossPop")
		CameraController.shake(1.6, 0.6)
	elseif popsThisFrame < MAX_POP_BURSTS_PER_FRAME then
		popsThisFrame += 1
		local e = popEmitters[kind]
		if e then
			burst(e, position + Vector3.new(0, (def and def.size or 1) * 0.5, 0), 6)
		end
		Sound.play("squish")
	end
	if towerUid ~= 0 then
		local model = Towers.byUid[towerUid]
		if model and ownedByMe(model) then
			pendingCash[towerUid] = (pendingCash[towerUid] or 0) + 1
		end
	end
end

function Effects.leak()
	Sound.play("leak")
	CameraController.shake(0.3, 0.15)
end

function Effects.attack(towerUid: number, visual: string, x: number, z: number)
	local model = Towers.byUid[towerUid]
	if not model then
		return
	end
	local target = Vector3.new(x, GROUND + 1, z)
	local origin = towerPosition(model)
	if visual == "frost" or visual == "blades" or visual == "hotblades" then
		local range = model:GetAttribute("Range")
		local r = if type(range) == "number" then range else 6
		if visual == "frost" then
			ring(origin - Vector3.new(0, 2, 0), r, Color3.fromRGB(170, 230, 255), Enum.Material.Ice)
		else
			ring(
				origin - Vector3.new(0, 2, 0),
				r,
				if visual == "hotblades" then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(230, 230, 230),
				Enum.Material.Neon
			)
		end
		return
	end
	-- Turn the tower to face its target (purely cosmetic, client-side).
	local pivot = model:GetPivot()
	local flatTarget = Vector3.new(x, pivot.Position.Y, z)
	if (flatTarget - pivot.Position).Magnitude > 0.5 then
		model:PivotTo(CFrame.lookAt(pivot.Position, flatTarget))
	end
	launch(visual, origin, target)
	if visual == "firewall" then
		burst(fire, target, 25)
	elseif visual == "bomb" then
		task.delay(0.3, function()
			burst(dust, target, 12)
		end)
	end
end

function Effects.chain(x1: number, z1: number, x2: number, z2: number)
	zap(Vector3.new(x1, GROUND + 1, z1), Vector3.new(x2, GROUND + 1, z2))
end

function Effects.towerPlaced(model: Model)
	Sound.play("thump")
	CameraController.shake(0.25, 0.12)
	burst(dust, model:GetPivot().Position + Vector3.new(0, 0.5, 0), 20)
	-- Squash-and-stretch pop-in.
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / 0.35
		if t >= 1 or not model.Parent then
			if model.Parent then
				model:ScaleTo(1)
			end
			connection:Disconnect()
			return
		end
		local s = if t < 0.4 then 0.5 + t / 0.4 * 0.7 else 1.2 - (t - 0.4) / 0.6 * 0.2
		model:ScaleTo(s)
	end)
end

function Effects.towerUpgraded(model: Model)
	Sound.play("sparkle")
	burst(sparkle, model:GetPivot().Position + Vector3.new(0, 3, 0), 40)
end

local function update(dt: number)
	popsThisFrame = 0

	-- Projectiles
	table.clear(moveParts)
	table.clear(moveCFrames)
	local i = 1
	while i <= #activeProjectiles do
		local p = activeProjectiles[i]
		p.t += dt
		local alpha = math.min(p.t / p.duration, 1)
		local pos = p.from:Lerp(p.to, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * p.arc, 0)
		local dir = p.to - p.from
		local cf = if dir.Magnitude > 0.01 then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
		if alpha >= 1 then
			table.insert(moveParts, p.part)
			table.insert(moveCFrames, HIDDEN)
			table.insert(projectilePool, p.part)
			activeProjectiles[i] = activeProjectiles[#activeProjectiles]
			activeProjectiles[#activeProjectiles] = nil
		else
			table.insert(moveParts, p.part)
			table.insert(moveCFrames, cf)
			i += 1
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- Cash popups, aggregated per tower
	cashFlushTimer += dt
	if cashFlushTimer >= 0.45 then
		cashFlushTimer = 0
		local any = false
		for uid, amount in pendingCash do
			local model = Towers.byUid[uid]
			if model and model.PrimaryPart then
				cashPopup(model, amount)
				any = true
			end
		end
		table.clear(pendingCash)
		if any then
			Sound.play("cash")
		end
	end
end

function Effects.start()
	local f = Instance.new("Folder")
	f.Name = "ClientEffects"
	f.Parent = Workspace
	folder = f
	local a = Instance.new("Part")
	a.Name = "EffectsAnchor"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.CFrame = CFrame.new()
	a.Parent = f
	anchor = a

	for kind, def in SlimeData do
		local color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
		if kind == "Boss" then
			popEmitters[kind] = makeEmitter("PopBoss", color, {
				Speed = NumberRange.new(20, 45),
				Lifetime = NumberRange.new(0.5, 0.9),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) }),
			})
		else
			popEmitters[kind] = makeEmitter(`Pop{kind}`, color, {})
		end
	end
	sparkle = makeEmitter("Sparkle", Color3.fromRGB(255, 240, 140), {
		LightEmission = 1,
		Speed = NumberRange.new(4, 10),
		Acceleration = Vector3.new(0, 6, 0),
		Lifetime = NumberRange.new(0.6, 1),
	})
	dust = makeEmitter("Dust", Color3.fromRGB(255, 235, 245), {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(10, 180),
		Acceleration = Vector3.new(0, 2, 0),
		Lifetime = NumberRange.new(0.4, 0.7),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.5) }),
	})
	fire = makeEmitter("Fire", Color3.fromRGB(255, 130, 40), {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		LightEmission = 1,
		Speed = NumberRange.new(2, 6),
		Acceleration = Vector3.new(0, 12, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) }),
	})
	for _ = 1, 24 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = HIDDEN
		p.Parent = f
		table.insert(ringPool, p)
	end

	Towers.added:Connect(function(model, initial)
		if not initial then
			Effects.towerPlaced(model)
		end
		local function onTier()
			if model.Parent then
				Effects.towerUpgraded(model)
			end
		end
		model:GetAttributeChangedSignal("TierA"):Connect(onTier)
		model:GetAttributeChangedSignal("TierB"):Connect(onTier)
	end)
	RunService.RenderStepped:Connect(update)
end

return Effects
