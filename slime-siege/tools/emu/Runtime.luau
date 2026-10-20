--!nocheck
-- A small Roblox runtime emulator for Lune. It loads the place built by Rojo, runs the real
-- server Script and client LocalScript against mocked engine services, and lets a scenario
-- drive time, players, remotes and input. It is NOT Roblox: it catches script errors, wiring
-- mistakes and logic bugs, not rendering, physics or performance problems.
--
-- Contexts: "server" plus one per client. Every coroutine carries its context so that
-- Players.LocalPlayer, RunService:IsClient(), RemoteEvent:FireServer and module caches behave
-- per machine, as they would in Roblox.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Runtime = {}

---------------------------------------------------------------------------
-- Contexts, scheduler and errors
---------------------------------------------------------------------------

export type Context = {
	name: string,
	isServer: boolean,
	player: any?,
	modules: { [any]: any },
	renderSteps: { [string]: { priority: number, fn: (number) -> () } },
}

local now = 0
local current: Context? = nil
local sleeping: { { co: thread, at: number, ctx: Context?, args: { any }?, seq: number } } = {}
local seq = 0
local errors: { string } = {}
local logs: { string } = {}
local printLogs = false

Runtime.errors = errors
Runtime.logs = logs

function Runtime.now(): number
	return now
end

function Runtime.current(): Context?
	return current
end

function Runtime.setPrintLogs(on: boolean)
	printLogs = on
end

local function log(ctx: Context?, kind: string, ...: any)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local line = string.format("[%7.2f][%s]%s %s", now, if ctx then ctx.name else "?", kind, table.concat(parts, " "))
	table.insert(logs, line)
	if printLogs then
		print(line)
	end
end

local seenErrors: { [string]: number } = {}
local function recordError(ctx: Context?, message: string)
	local line = `[{string.format("%.2f", now)}][{if ctx then ctx.name else "?"}] {message}`
	table.insert(errors, line)
	local key = (if ctx then ctx.name else "?") .. message
	seenErrors[key] = (seenErrors[key] or 0) + 1
	if seenErrors[key] == 1 then
		print("ERROR " .. line)
	end
end

local function resume(co: thread, ctx: Context?, ...: any)
	if coroutine.status(co) == "dead" then
		return
	end
	local prev = current
	current = ctx
	local ok, err = coroutine.resume(co, ...)
	current = prev
	if not ok then
		recordError(ctx, debug.traceback(co, tostring(err)))
	end
end

function Runtime.spawnIn(ctx: Context?, fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ctx, ...)
	return co
end

local function schedule(co: thread, at: number, ctx: Context?, args: { any }?)
	seq += 1
	table.insert(sleeping, { co = co, at = at, ctx = ctx, args = args, seq = seq })
end

-- Runs every thread due at the current time (including ones scheduled while running).
local function runDue()
	while true do
		local bestIndex = nil
		for i, s in sleeping do
			if
				s.at <= now
				and (
					bestIndex == nil
					or s.at < sleeping[bestIndex].at
					or (s.at == sleeping[bestIndex].at and s.seq < sleeping[bestIndex].seq)
				)
			then
				bestIndex = i
			end
		end
		if not bestIndex then
			return
		end
		local s = table.remove(sleeping, bestIndex)
		if s.args then
			resume(s.co, s.ctx, table.unpack(s.args))
		else
			resume(s.co, s.ctx, now)
		end
	end
end

local task = {}
function task.wait(t: number?): number
	local co = coroutine.running()
	local start = now
	schedule(co, now + math.max(t or 0, 1 / 60), current, nil)
	coroutine.yield()
	return now - start
end
function task.spawn(fn: any, ...: any): thread
	return Runtime.spawnIn(current, fn, ...)
end
function task.defer(fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(co, now, current, table.pack(...))
	return co
end
function task.delay(t: number, fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(co, now + t, current, table.pack(...))
	return co
end
function task.cancel(co: thread)
	for i, s in sleeping do
		if s.co == co then
			table.remove(sleeping, i)
			return
		end
	end
end
Runtime.task = task

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(name: string?)
	return setmetatable({ handlers = {}, name = name or "Signal" }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn, ctx = current, connected = true }
	table.insert(self.handlers, entry)
	local signal = self
	local connection = { Connected = true }
	function connection.Disconnect(c)
		entry.connected = false
		c.Connected = false
		local i = table.find(signal.handlers, entry)
		if i then
			table.remove(signal.handlers, i)
		end
	end
	connection.disconnect = connection.Disconnect
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	local co = coroutine.running()
	local ctx = current
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		schedule(co, now, ctx, table.pack(...))
	end)
	return coroutine.yield()
end

-- Fires to every handler, each in its own coroutine in the context it connected from.
-- `onlyCtx` restricts delivery to handlers connected from that context.
function Signal:Fire(...)
	for _, entry in table.clone(self.handlers) do
		if entry.connected then
			Runtime.spawnIn(entry.ctx, entry.fn, ...)
		end
	end
end

function Signal:FireIn(ctx: Context, ...)
	for _, entry in table.clone(self.handlers) do
		if entry.connected and entry.ctx == ctx then
			Runtime.spawnIn(entry.ctx, entry.fn, ...)
		end
	end
end

function Signal:HandlerCount(): number
	return #self.handlers
end

Runtime.Signal = Signal

-- Per-instance lazily created signals (events Lune doesn't implement).
-- Lune hands out fresh userdata for the same Instance, so key by a stable id attribute.
local instanceSignals: { [any]: { [string]: any } } = {}
local nextEmuId = 0
local function keyOf(inst: any): any
	if typeof(inst) ~= "Instance" then
		return inst
	end
	local id = inst:GetAttribute("__emuId")
	if id == nil then
		nextEmuId += 1
		id = nextEmuId
		inst:SetAttribute("__emuId", id)
	end
	return id
end
Runtime.keyOf = keyOf
local function signalFor(inst: any, name: string)
	inst = keyOf(inst)
	local map = instanceSignals[inst]
	if not map then
		map = {}
		instanceSignals[inst] = map
	end
	local s = map[name]
	if not s then
		s = Signal.new(name)
		map[name] = s
	end
	return s
end
Runtime.signalFor = signalFor

---------------------------------------------------------------------------
-- Value copying across the "network" (remotes serialize their arguments)
---------------------------------------------------------------------------

local function netCopy(v: any, depth: number?): any
	local d = depth or 0
	if d > 30 then
		error("remote argument nested too deeply")
	end
	local t = type(v)
	if t == "table" then
		if getmetatable(v) ~= nil and rawget(v, "__player") == nil then
			-- tables with metatables lose them across the network
		end
		if rawget(v, "__player") then
			return v -- player mocks travel by reference, like Instances
		end
		local out = {}
		for k, value in v do
			if type(k) ~= "function" and type(value) ~= "function" and type(value) ~= "thread" then
				out[netCopy(k, d + 1)] = netCopy(value, d + 1)
			end
		end
		return out
	elseif t == "buffer" then
		local copy = buffer.create(buffer.len(v))
		buffer.copy(copy, 0, v)
		return copy
	elseif t == "function" or t == "thread" then
		return nil
	end
	return v
end

local function packNet(...: any): { any }
	local out = table.pack(...)
	for i = 1, out.n do
		out[i] = netCopy(out[i])
	end
	return out
end

---------------------------------------------------------------------------
-- The place, players and contexts
---------------------------------------------------------------------------

local game: any = nil
local serverCtx: Context = { name = "server", isServer = true, player = nil, modules = {}, renderSteps = {} }
local clients: { Context } = {}
local playersList: { any } = {}
local options =
	{ studio = true, jobId = "job-server-1", privateServerId = "", privateServerOwnerId = 0, placeId = 1234 }

Runtime.serverCtx = serverCtx
Runtime.clients = clients

local services: { [string]: any } = {}
Runtime.services = services

function Runtime.game(): any
	return Runtime.gameProxy
end

---------------------------------------------------------------------------
-- Instance API gaps (implemented on Lune's Instances)
---------------------------------------------------------------------------

local function findPath(inst: any, path: string): any
	local node = inst
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
Runtime.findPath = findPath

local implemented = false
local function implementInstanceApi()
	if implemented then
		return
	end
	implemented = true
	local implementMethod, implementProperty = roblox.implementMethod, roblox.implementProperty

	implementMethod("Instance", "WaitForChild", function(inst, name, timeout)
		local child = inst:FindFirstChild(name)
		local deadline = now + (timeout or 5)
		while not child do
			if now >= deadline then
				if timeout then
					return nil
				end
				error(`Infinite yield: WaitForChild("{name}") on {inst:GetFullName()}`)
			end
			task.wait(0.1)
			child = inst:FindFirstChild(name)
		end
		return child
	end)
	for _, eventName in { "ChildAdded", "ChildRemoved", "AttributeChanged", "Destroying", "DescendantAdded" } do
		implementProperty("Instance", eventName, function(inst)
			return signalFor(inst, eventName)
		end)
	end
	implementMethod("Instance", "GetAttributeChangedSignal", function(inst, name)
		return signalFor(inst, "AttributeChanged:" .. name)
	end)
	implementMethod("Instance", "GetPropertyChangedSignal", function(inst, name)
		return signalFor(inst, "PropertyChanged:" .. name)
	end)

	-- Pivot API
	implementMethod("PVInstance", "GetPivot", function(inst)
		if inst:IsA("BasePart") then
			return inst.CFrame
		end
		local primary = inst.PrimaryPart
		if primary then
			return primary.CFrame
		end
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				return d.CFrame
			end
		end
		return CFrame.new()
	end)
	implementMethod("PVInstance", "PivotTo", function(inst, target)
		if inst:IsA("BasePart") then
			inst.CFrame = target
			return
		end
		local delta = target * inst:GetPivot():Inverse()
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			end
		end
	end)
	implementMethod("Model", "ScaleTo", function(inst, scale)
		inst:SetAttribute("__scale", scale)
	end)
	implementMethod("Model", "GetScale", function(inst)
		return inst:GetAttribute("__scale") or 1
	end)

	-- Remotes
	implementProperty("RemoteEvent", "OnServerEvent", function(inst)
		return signalFor(inst, "OnServerEvent")
	end)
	implementProperty("RemoteEvent", "OnClientEvent", function(inst)
		return signalFor(inst, "OnClientEvent")
	end)
	implementMethod("RemoteEvent", "FireServer", function(inst, ...)
		local ctx = current
		if not ctx or ctx.isServer then
			error("FireServer can only be called from the client")
		end
		local args = packNet(...)
		log(ctx, " -> " .. inst.Name, table.unpack(args, 1, args.n))
		local player = ctx.player
		task.defer(function()
			signalFor(inst, "OnServerEvent"):FireIn(serverCtx, player, table.unpack(args, 1, args.n))
		end)
	end)
	local function deliver(inst, player, args)
		for _, ctx in clients do
			if ctx.player == player and player.Parent ~= nil then
				signalFor(inst, "OnClientEvent"):FireIn(ctx, table.unpack(args, 1, args.n))
			end
		end
	end
	implementMethod("RemoteEvent", "FireClient", function(inst, player, ...)
		if current and not current.isServer then
			error("FireClient can only be called from the server")
		end
		if type(player) ~= "table" or not rawget(player, "__player") then
			error("FireClient: argument 1 must be a Player")
		end
		local args = packNet(...)
		Runtime.recordRemote(inst.Name, player, args)
		task.defer(deliver, inst, player, args)
	end)
	implementMethod("RemoteEvent", "FireAllClients", function(inst, ...)
		if current and not current.isServer then
			error("FireAllClients can only be called from the server")
		end
		local args = packNet(...)
		for _, player in playersList do
			Runtime.recordRemote(inst.Name, player, args)
			task.defer(deliver, inst, player, args)
		end
	end)

	-- Gui events
	for _, eventName in
		{ "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "MouseEnter", "MouseLeave" }
	do
		implementProperty("GuiButton", eventName, function(inst)
			return signalFor(inst, eventName)
		end)
	end

	-- Sounds / particles / tweens are visual-only no-ops
	implementMethod("Sound", "Play", function(inst)
		inst:SetAttribute("__plays", (inst:GetAttribute("__plays") or 0) + 1)
	end)
	implementMethod("Sound", "Stop", function() end)
	implementMethod("ParticleEmitter", "Emit", function(inst, count)
		inst:SetAttribute("__emitted", (inst:GetAttribute("__emitted") or 0) + (count or 1))
	end)

	-- Teleport options
	implementMethod("TeleportOptions", "SetTeleportData", function(inst, data)
		rawset(signalFor(inst, "__data"), "data", data)
	end)
	implementMethod("TeleportOptions", "GetTeleportData", function(inst)
		return rawget(signalFor(inst, "__data"), "data")
	end)

	-- Workspace helpers
	implementMethod("Workspace", "BulkMoveTo", function(_, parts, cframes)
		assert(#parts == #cframes, "BulkMoveTo: parts and cframes must have the same length")
		for i, part in parts do
			part.CFrame = cframes[i]
		end
	end)
	implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
		return Runtime.raycast(origin, direction, params)
	end)
	implementProperty("Workspace", "CurrentCamera", function(ws)
		local cam = ws:FindFirstChild("Camera")
		if not cam then
			cam = Instance.new("Camera")
			cam.Name = "Camera"
			-- Lune has no default for this read-only property; give the emulated screen a size.
			pcall(function()
				cam.ViewportSize = roblox.Vector2.new(1000, 1000)
			end)
			cam.Parent = ws
		end
		return cam
	end)
	implementProperty("Camera", "ViewportSize", function()
		return roblox.Vector2.new(1000, 1000)
	end)
	-- Emulated screen mapping: viewport (x, y) looks straight down at world (x - 500, y - 500).
	implementMethod("Camera", "ViewportPointToRay", function(_, x, y)
		return { Origin = Vector3.new(x - 500, 200, y - 500), Direction = Vector3.new(0, -1, 0), Unit = nil }
	end)
	implementMethod("Camera", "ScreenPointToRay", function(_, x, y)
		return { Origin = Vector3.new(x - 500, 200, y - 500), Direction = Vector3.new(0, -1, 0) }
	end)

	implementMethod("DataModel", "GetService", function(dm, name)
		local mock = services[name]
		if mock then
			return mock
		end
		local existing = dm:FindFirstChild(name)
		if existing then
			return existing
		end
		local ok, inst = pcall(Instance.new, name)
		if not ok then
			inst = Instance.new("Folder")
		end
		inst.Name = name
		inst.Parent = dm
		return inst
	end)
	implementMethod("DataModel", "BindToClose", function(_, fn)
		table.insert(Runtime.closeHandlers, { fn = fn, ctx = current })
	end)
	implementProperty("DataModel", "JobId", function()
		return options.jobId
	end)
	implementProperty("DataModel", "PlaceId", function()
		return options.placeId
	end)
	implementProperty("DataModel", "PrivateServerId", function()
		return options.privateServerId
	end)
	implementProperty("DataModel", "PrivateServerOwnerId", function()
		return options.privateServerOwnerId
	end)
	implementProperty("ScreenGui", "ScreenInsets", function(inst)
		return inst:GetAttribute("__ScreenInsets")
	end, function(inst, value)
		inst:SetAttribute("__ScreenInsets", tostring(value))
	end)
end

Runtime.closeHandlers = {}

---------------------------------------------------------------------------
-- Raycasts (enough for placement and tower selection)
---------------------------------------------------------------------------

function Runtime.raycast(origin, direction, params)
	local filter = if params then params.FilterDescendantsInstances else {}
	local include = params == nil or params.FilterType == roblox.Enum.RaycastFilterType.Include
	if direction.Y >= 0 then
		return nil
	end
	local t = -origin.Y / direction.Y
	if t > direction.Magnitude then
		return nil
	end
	local hit = origin + direction.Unit * (-origin.Y / direction.Unit.Y)
	for _, root in filter do
		if root.Name == "Towers" then
			local best, bestDist = nil, math.huge
			for _, model in root:GetChildren() do
				local p = model:GetPivot().Position
				local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(hit.X, 0, hit.Z)).Magnitude
				if d < (model:GetAttribute("Footprint") or 2) + 0.5 and d < bestDist then
					best, bestDist = model, d
				end
			end
			if best then
				local part = best:FindFirstChildWhichIsA("BasePart", true)
				return { Position = hit, Instance = part, Normal = Vector3.new(0, 1, 0), Distance = t }
			end
		elseif root.Name == "Map" and include then
			local ground = root:FindFirstChild("Ground")
			if ground then
				local size, pos = ground.Size, ground.CFrame.Position
				if math.abs(hit.X - pos.X) <= size.X / 2 and math.abs(hit.Z - pos.Z) <= size.Z / 2 then
					return { Position = hit, Instance = ground, Normal = Vector3.new(0, 1, 0), Distance = t }
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Remote traffic log (for assertions)
---------------------------------------------------------------------------

Runtime.remoteLog = {} :: { { name: string, player: any, args: { any }, time: number } }
function Runtime.recordRemote(name: string, player: any, args: { any })
	table.insert(Runtime.remoteLog, { name = name, player = player, args = args, time = now })
	if #Runtime.remoteLog > 20000 then
		table.remove(Runtime.remoteLog, 1)
	end
end

function Runtime.lastRemote(name: string, player: any?): { any }?
	for i = #Runtime.remoteLog, 1, -1 do
		local r = Runtime.remoteLog[i]
		if r.name == name and (player == nil or r.player == player) then
			return r.args
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Mock services
---------------------------------------------------------------------------

local function newPlayersService()
	local Players = {
		Name = "Players",
		ClassName = "Players",
		PlayerAdded = Signal.new("PlayerAdded"),
		PlayerRemoving = Signal.new("PlayerRemoving"),
		CharacterAutoLoads = true,
	}
	function Players.GetPlayers(_)
		return table.clone(playersList)
	end
	function Players.GetPlayerByUserId(_, id)
		for _, p in playersList do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end
	return setmetatable(Players, {
		__index = function(_, key)
			if key == "LocalPlayer" then
				return if current and not current.isServer then current.player else nil
			end
			return nil
		end,
	})
end

local function newRunService()
	local rs = {
		Name = "RunService",
		Heartbeat = Signal.new("Heartbeat"),
		RenderStepped = Signal.new("RenderStepped"),
		Stepped = Signal.new("Stepped"),
	}
	function rs.IsStudio()
		return options.studio
	end
	function rs.IsServer()
		return current == nil or current.isServer
	end
	function rs.IsClient()
		return current ~= nil and not current.isServer
	end
	function rs.BindToRenderStep(_, name, priority, fn)
		assert(current and not current.isServer, "BindToRenderStep is client-only")
		current.renderSteps[name] = { priority = priority, fn = fn }
	end
	function rs.UnbindFromRenderStep(_, name)
		if current then
			current.renderSteps[name] = nil
		end
	end
	return rs
end

Runtime.dataStores = {} :: { [string]: { [string]: string } }
Runtime.dataStoreFailures = 0 -- next N calls throw

local function newDataStoreService()
	local dss = { Name = "DataStoreService" }
	function dss.GetDataStore(_, name)
		local backing = Runtime.dataStores[name]
		if not backing then
			backing = {}
			Runtime.dataStores[name] = backing
		end
		local store = {}
		function store.UpdateAsync(_, key, transform)
			task.wait(0.05) -- network latency
			if Runtime.dataStoreFailures > 0 then
				Runtime.dataStoreFailures -= 1
				error("502: emulated DataStore failure")
			end
			local old = if backing[key] then serde.decode("json", backing[key]) else nil
			local co = coroutine.running()
			local result = transform(old)
			assert(coroutine.running() == co, "UpdateAsync transform must not yield")
			if result ~= nil then
				backing[key] = serde.encode("json", result)
			end
			return result
		end
		function store.GetAsync(_, key)
			return if backing[key] then serde.decode("json", backing[key]) else nil
		end
		function store.SetAsync()
			error("SetAsync is banned in this project; use UpdateAsync")
		end
		return store
	end
	function dss.GetRequestBudgetForRequestType()
		return 100
	end
	return dss
end

Runtime.teleports = {} :: { any }
local function newTeleportService()
	local ts = { Name = "TeleportService" }
	function ts.ReserveServer(_, placeId)
		assert(type(placeId) == "number", "ReserveServer needs a place id")
		return `reserved-{#Runtime.teleports + 1}`
	end
	function ts.TeleportAsync(_, placeId, players, teleportOptions)
		assert(current and current.isServer, "TeleportAsync is server-only")
		assert(type(players) == "table" and #players > 0, "TeleportAsync needs players")
		local data = nil
		local code = nil
		if teleportOptions then
			data = teleportOptions:GetTeleportData()
			code = teleportOptions.ReservedServerAccessCode
		end
		table.insert(Runtime.teleports, { placeId = placeId, players = players, data = data, code = code, time = now })
	end
	return ts
end

local function newMarketplaceService()
	local ms = {
		Name = "MarketplaceService",
		PromptGamePassPurchaseFinished = Signal.new("PromptGamePassPurchaseFinished"),
		ProcessReceipt = nil,
		prompts = {},
	}
	function ms.PromptGamePassPurchase(self, player, id)
		table.insert(self.prompts, { player = player, id = id, kind = "gamepass" })
	end
	function ms.PromptProductPurchase(self, player, id)
		table.insert(self.prompts, { player = player, id = id, kind = "product" })
	end
	function ms.UserOwnsGamePassAsync()
		return false
	end
	return ms
end

local function newTweenService()
	local ts = { Name = "TweenService" }
	function ts.Create(_, inst, info, props)
		assert(typeof(inst) == "Instance", "TweenService:Create needs an Instance")
		local tween = { Completed = Signal.new("Completed") }
		for key, value in props do
			local _ = inst[key] -- property must exist
			assert(typeof(value) == typeof(inst[key]), `tween type mismatch for {key}`)
		end
		function tween.Play()
			local duration = if type(info) == "table" then info.Time or 0.25 else 0.25
			task.delay(duration, function()
				for key, value in props do
					inst[key] = value
				end
				tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
			end)
		end
		function tween.Cancel() end
		return tween
	end
	return ts
end

local function newUserInputService()
	local uis = {
		Name = "UserInputService",
		InputBegan = Signal.new("InputBegan"),
		InputEnded = Signal.new("InputEnded"),
		InputChanged = Signal.new("InputChanged"),
		TouchTapInWorld = Signal.new("TouchTapInWorld"),
		TouchPinch = Signal.new("TouchPinch"),
		TouchRotate = Signal.new("TouchRotate"),
		TouchPan = Signal.new("TouchPan"),
		LastInputTypeChanged = Signal.new("LastInputTypeChanged"),
		TouchEnabled = false,
		KeyboardEnabled = true,
		GamepadEnabled = false,
	}
	function uis.GetMouseLocation()
		local ctx = current
		return if ctx and ctx.mouse then ctx.mouse else roblox.Vector2.new(500, 500)
	end
	function uis.GetLastInputType()
		return roblox.Enum.UserInputType.MouseMovement
	end
	function uis.IsKeyDown(_, key)
		local ctx = current
		return ctx ~= nil and ctx.keysDown ~= nil and ctx.keysDown[key] == true
	end
	function uis.GetFocusedTextBox()
		return nil
	end
	return uis
end

local function newContextActionService()
	local cas = { Name = "ContextActionService" }
	function cas.BindAction(_, name, fn, _createTouchButton, ...)
		assert(current and not current.isServer, "BindAction is client-only")
		current.actions = current.actions or {}
		current.actions[name] = { fn = fn, keys = { ... }, priority = 2000 }
	end
	function cas.BindActionAtPriority(_, name, fn, _createTouchButton, priority, ...)
		assert(current and not current.isServer, "BindActionAtPriority is client-only")
		assert(type(priority) == "number", "BindActionAtPriority: priority must be a number")
		current.actions = current.actions or {}
		current.actions[name] = { fn = fn, keys = { ... }, priority = priority }
	end
	function cas.UnbindAction(_, name)
		if current and current.actions then
			current.actions[name] = nil
		end
	end
	return cas
end

local function newGuiService()
	return {
		Name = "GuiService",
		SelectedObject = nil,
		GetGuiInset = function()
			return roblox.Vector2.new(0, 36), roblox.Vector2.new(0, 0)
		end,
	}
end

---------------------------------------------------------------------------
-- Globals for loaded scripts
---------------------------------------------------------------------------

local RandomMock = {}
function RandomMock.new(seed: number?)
	local state = seed or 1
	local r = {}
	local function nextFloat()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function r.NextNumber(_, min, max)
		local lo, hi = min or 0, max or 1
		return lo + (hi - lo) * nextFloat()
	end
	function r.NextInteger(_, min, max)
		return min + math.floor((max - min + 1) * nextFloat())
	end
	return r
end

local TweenInfoMock = {}
function TweenInfoMock.new(time, style, direction, repeatCount, reverses, delayTime)
	return {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local RaycastParamsMock = {}
function RaycastParamsMock.new()
	return { FilterType = roblox.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {} }
end

-- Scripts see `game` through a proxy so engine services resolve to the mocks
-- (Lune's native DataModel:GetService can't be overridden).
local gameProxy = nil
local function getService(name: string): any
	local mock = services[name]
	if mock then
		return mock
	end
	local existing = game:FindFirstChild(name)
	if existing then
		return existing
	end
	local ok, inst = pcall(Instance.new, name)
	if not ok then
		inst = Instance.new("Folder")
	end
	inst.Name = name
	inst.Parent = game
	return inst
end
local function makeGameProxy(): any
	local overrides = {
		GetService = function(_, name)
			return getService(name)
		end,
		FindService = function(_, name)
			return getService(name)
		end,
		BindToClose = function(_, fn)
			table.insert(Runtime.closeHandlers, { fn = fn, ctx = current })
		end,
	}
	return setmetatable({}, {
		__index = function(_, key)
			if overrides[key] then
				return overrides[key]
			elseif key == "JobId" then
				return options.jobId
			elseif key == "PlaceId" then
				return options.placeId
			elseif key == "PrivateServerId" then
				return options.privateServerId
			elseif key == "PrivateServerOwnerId" then
				return options.privateServerOwnerId
			end
			local value = game[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(game, ...)
				end
			end
			return value
		end,
		__tostring = function()
			return "game"
		end,
	})
end

local function makeGlobals(ctx: Context, script: any): { [string]: any }
	local g = {}
	g.script = script
	g.game = gameProxy
	g.workspace = getService("Workspace")
	g.Workspace = g.workspace
	g.Instance = {
		new = function(className, parent)
			local inst = Instance.new(className)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	}
	for _, name in
		{
			"Vector3",
			"Vector2",
			"CFrame",
			"Color3",
			"Enum",
			"UDim",
			"UDim2",
			"NumberRange",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"Rect",
			"Ray",
			"BrickColor",
			"Font",
		}
	do
		g[name] = roblox[name]
	end
	g.Random = RandomMock
	g.TweenInfo = TweenInfoMock
	g.RaycastParams = RaycastParamsMock
	g.task = task
	g.wait = task.wait
	g.os = setmetatable({
		clock = function()
			return now
		end,
		time = function()
			return 1700000000 + math.floor(now)
		end,
	}, { __index = os })
	g.tick = function()
		return now
	end
	g.time = function()
		return now
	end
	g.print = function(...)
		log(ctx, "", ...)
	end
	g.warn = function(...)
		log(ctx, " WARN", ...)
		table.insert(Runtime.warnings, `[{ctx.name}] ` .. table.concat({ ... } :: any, " "))
	end
	g.typeof = function(v)
		if type(v) == "table" and rawget(v, "__player") then
			return "Instance"
		end
		return typeof(v)
	end
	g.require = function(target)
		return Runtime.require(ctx, target)
	end
	return g
end

Runtime.warnings = {} :: { string }

function Runtime.require(ctx: Context, target: any): any
	assert(
		typeof(target) == "Instance" and target:IsA("ModuleScript"),
		`require expects a ModuleScript, got {tostring(target)}`
	)
	local cached = ctx.modules[keyOf(target)]
	if cached ~= nil then
		if cached == Runtime then
			error(`cyclic require of {target:GetFullName()}`)
		end
		return cached
	end
	ctx.modules[keyOf(target)] = Runtime -- loading marker
	local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = makeGlobals(ctx, target) })
	local result = chunk()
	ctx.modules[keyOf(target)] = if result == nil then true else result
	return result
end

local function runScript(ctx: Context, script: any)
	local chunk = luau.load(script.Source, { debugName = script:GetFullName(), environment = makeGlobals(ctx, script) })
	Runtime.spawnIn(ctx, chunk)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

export type Options = { place: string, studio: boolean?, studioMode: string?, privateServerId: string?, jobId: string? }

function Runtime.boot(opts: Options)
	implementInstanceApi()
	options.studio = if opts.studio == nil then true else opts.studio
	options.privateServerId = opts.privateServerId or ""
	options.jobId = opts.jobId or "job-server-1"
	game = roblox.deserializePlace(fs.readFile(opts.place))
	gameProxy = makeGameProxy()
	Runtime.gameProxy = gameProxy
	-- Cameras saved in the place have no ViewportSize in Lune; give them the emulated screen.
	local cameras = game:GetDescendants()
	local ok, current = pcall(function()
		return game:GetService("Workspace").CurrentCamera
	end)
	if ok and current then
		table.insert(cameras, current)
	end
	for _, d in cameras do
		if d.ClassName == "Camera" then
			pcall(function()
				d.ViewportSize = roblox.Vector2.new(1000, 1000)
			end)
		end
	end
	services.Players = newPlayersService()
	services.RunService = newRunService()
	services.DataStoreService = newDataStoreService()
	services.TeleportService = newTeleportService()
	services.MarketplaceService = newMarketplaceService()
	services.TweenService = newTweenService()
	services.UserInputService = newUserInputService()
	services.ContextActionService = newContextActionService()
	services.GuiService = newGuiService()
	if opts.studioMode then
		game:GetService("Workspace"):SetAttribute("StudioMode", opts.studioMode)
	end
	-- Run every server Script under ServerScriptService.
	for _, d in game:GetService("ServerScriptService"):GetDescendants() do
		if d.ClassName == "Script" then
			runScript(serverCtx, d)
		end
	end
	runDue()
end

local nextUserId = 1001

-- A player joins: server sees PlayerAdded; a client context runs StarterPlayerScripts.
function Runtime.addPlayer(name: string, opts: { teleportData: any?, userId: number? }?): (any, Context)
	local userId = (opts and opts.userId) or nextUserId
	nextUserId += 1
	local player
	player = {
		__player = true,
		Name = name,
		DisplayName = name,
		UserId = userId,
		ClassName = "Player",
		Parent = services.Players,
		Character = nil,
		kicked = nil,
	}
	local playerGui = Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	player.PlayerGui = playerGui
	function player.Kick(self, message)
		self.kicked = message or ""
		log(serverCtx, " KICK", self.Name, message)
		Runtime.removePlayer(self)
	end
	function player.GetJoinData()
		return { TeleportData = opts and opts.teleportData }
	end
	function player.WaitForChild(_, childName)
		if childName == "PlayerGui" then
			return playerGui
		end
		error("Player mock has no child " .. childName)
	end
	function player.FindFirstChild(_, childName)
		return if childName == "PlayerGui" then playerGui else nil
	end
	function player.IsA(_, className)
		return className == "Player" or className == "Instance"
	end
	setmetatable(player, {
		__tostring = function()
			return name
		end,
	})
	table.insert(playersList, player)
	local ctx: Context = { name = `client:{name}`, isServer = false, player = player, modules = {}, renderSteps = {} }
	table.insert(clients, ctx)
	services.Players.PlayerAdded:FireIn(serverCtx, player)
	-- Client scripts
	local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if starter then
		for _, d in starter:GetDescendants() do
			if d.ClassName == "LocalScript" then
				runScript(ctx, d)
			end
		end
	end
	runDue()
	return player, ctx
end

function Runtime.removePlayer(player: any)
	if player.Parent == nil then
		return
	end
	services.Players.PlayerRemoving:FireIn(serverCtx, player)
	player.Parent = nil
	local i = table.find(playersList, player)
	if i then
		table.remove(playersList, i)
	end
	for ci, ctx in clients do
		if ctx.player == player then
			table.remove(clients, ci)
			break
		end
	end
end

-- Advances emulated time in 1/60 s frames: Heartbeat on the server, RenderStepped and
-- bound render steps on every client.
function Runtime.advance(seconds: number)
	local frame = 1 / 60
	local target = now + seconds
	while now < target - 1e-9 do
		now += frame
		runDue()
		services.RunService.Heartbeat:Fire(frame)
		for _, ctx in table.clone(clients) do
			local steps = {}
			for _, s in ctx.renderSteps do
				table.insert(steps, s)
			end
			table.sort(steps, function(a, b)
				return a.priority < b.priority
			end)
			for _, s in steps do
				Runtime.spawnIn(ctx, s.fn, frame)
			end
		end
		services.RunService.RenderStepped:Fire(frame)
		runDue()
	end
end

-- Runs a function inside a context (e.g. to call a client module the way its UI would).
function Runtime.within(ctx: Context, fn: (...any) -> ...any, ...: any)
	Runtime.spawnIn(ctx, fn, ...)
	runDue()
end

function Runtime.shutdown()
	for _, h in Runtime.closeHandlers do
		Runtime.spawnIn(h.ctx, h.fn)
	end
	Runtime.advance(1)
end

-- Fires a client-side input action bound through ContextActionService.
function Runtime.pressAction(ctx: Context, keyCode: any)
	local best = nil
	for name, action in ctx.actions or {} do
		for _, key in action.keys do
			if key == keyCode and (best == nil or action.priority > best.priority) then
				best = action
				best.name = name
			end
		end
	end
	if best then
		Runtime.spawnIn(ctx, best.fn, best.name, roblox.Enum.UserInputState.Begin, { KeyCode = keyCode })
	end
	runDue()
	return best ~= nil
end

-- Simulates a GUI button press (mouse click / tap / gamepad A all end in Activated).
function Runtime.click(ctx: Context, button: any)
	assert(button and button:IsA("GuiButton"), "click needs a GuiButton")
	signalFor(button, "MouseButton1Down"):FireIn(ctx)
	signalFor(button, "MouseButton1Up"):FireIn(ctx)
	signalFor(button, "Activated"):FireIn(ctx)
	runDue()
end

-- Simulates a world click at map coordinates (x, z) with the mouse.
function Runtime.clickWorld(ctx: Context, x: number, z: number)
	ctx.mouse = roblox.Vector2.new(x + 500, z + 500)
	Runtime.advance(1 / 30) -- let RenderStepped update ghosts
	services.UserInputService.InputBegan:FireIn(ctx, {
		UserInputType = roblox.Enum.UserInputType.MouseButton1,
		KeyCode = roblox.Enum.KeyCode.Unknown,
		Position = Vector3.new(x + 500, z + 500, 0),
	}, false)
	runDue()
end

function Runtime.findGui(ctx: Context, path: string): any
	return findPath(ctx.player.PlayerGui, path)
end

return Runtime
