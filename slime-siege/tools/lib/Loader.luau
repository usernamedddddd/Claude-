--!strict
-- A tiny "Rojo in Lune": builds a virtual instance tree from default.project.json so that
-- Roblox-style `require(script.Parent.X)` and `game:GetService("ReplicatedStorage")` work for
-- the pure-logic modules when run headless (content tools, CI tests).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

export type VInstance = any

local Loader = {}

local SCRIPT_SUFFIXES = { ".server.luau", ".client.luau", ".server.lua", ".client.lua" }
local MODULE_SUFFIXES = { ".luau", ".lua" }

local function endsWith(s: string, suffix: string): boolean
	return #s >= #suffix and string.sub(s, -#suffix) == suffix
end

local instanceMethods = {}
local VInstanceMeta = {}

local function newInstance(name: string, className: string, parent: VInstance?, filePath: string?): VInstance
	local inst = setmetatable({
		__name = name,
		__className = className,
		__parent = parent,
		__children = {},
		__file = filePath,
	}, VInstanceMeta)
	if parent then
		parent.__children[name] = inst
	end
	return inst
end

function instanceMethods.FindFirstChild(self: VInstance, name: string): VInstance?
	return self.__children[name]
end

function instanceMethods.WaitForChild(self: VInstance, name: string): VInstance
	local child = self.__children[name]
	if not child then
		error(`WaitForChild: {name} is not a child of {self:GetFullName()}`, 2)
	end
	return child
end

function instanceMethods.GetChildren(self: VInstance): { VInstance }
	local out = {}
	for _, c in self.__children do
		table.insert(out, c)
	end
	table.sort(out, function(a, b)
		return a.__name < b.__name
	end)
	return out
end

function instanceMethods.GetDescendants(self: VInstance): { VInstance }
	local out = {}
	local function walk(node: VInstance)
		for _, c in instanceMethods.GetChildren(node) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function instanceMethods.IsA(self: VInstance, className: string): boolean
	return self.__className == className or className == "Instance"
end

function instanceMethods.GetFullName(self: VInstance): string
	local parts = {}
	local node = self
	while node and node.__parent do
		table.insert(parts, 1, node.__name)
		node = node.__parent
	end
	return table.concat(parts, ".")
end

function instanceMethods.GetService(self: VInstance, name: string): VInstance
	return self.__children[name] or newInstance(name, name, self, nil)
end

VInstanceMeta.__index = function(self: VInstance, key: string): any
	if key == "Name" then
		return rawget(self, "__name")
	elseif key == "Parent" then
		return rawget(self, "__parent")
	elseif key == "ClassName" then
		return rawget(self, "__className")
	end
	local method = (instanceMethods :: any)[key]
	if method then
		return method
	end
	local child = rawget(self, "__children")[key]
	if child then
		return child
	end
	error(`{key} is not a valid member of {instanceMethods.GetFullName(self)}`, 2)
end
VInstanceMeta.__tostring = function(self: VInstance): string
	return rawget(self, "__name")
end

local function mountDirectory(dirPath: string, inst: VInstance)
	for _, entry in fs.readDir(dirPath) do
		local full = `{dirPath}/{entry}`
		if fs.isDir(full) then
			local initFile: string? = nil
			for _, suffix in MODULE_SUFFIXES do
				if fs.isFile(`{full}/init{suffix}`) then
					initFile = `{full}/init{suffix}`
				end
			end
			local child = newInstance(entry, if initFile then "ModuleScript" else "Folder", inst, initFile)
			mountDirectory(full, child)
		elseif not string.match(entry, "^init%.") then
			local handled = false
			for _, suffix in SCRIPT_SUFFIXES do
				if endsWith(entry, suffix) then
					newInstance(string.sub(entry, 1, -#suffix - 1), "Script", inst, full)
					handled = true
					break
				end
			end
			if not handled then
				for _, suffix in MODULE_SUFFIXES do
					if endsWith(entry, suffix) then
						newInstance(string.sub(entry, 1, -#suffix - 1), "ModuleScript", inst, full)
						break
					end
				end
			end
		end
	end
end

local function mountNode(root: string, node: { [string]: any }, inst: VInstance)
	local path = node["$path"]
	if type(path) == "string" and fs.isDir(`{root}/{path}`) then
		mountDirectory(`{root}/{path}`, inst)
	end
	for key, value in node do
		if string.sub(key, 1, 1) ~= "$" and type(value) == "table" then
			local child = inst.__children[key] or newInstance(key, value["$className"] or key, inst, nil)
			mountNode(root, value, child)
		end
	end
end

export type Env = {
	game: VInstance,
	require: (any) -> any,
	extraGlobals: { [string]: any },
}

-- Builds the virtual DataModel for the project at `root`.
function Loader.load(root: string, extraGlobals: { [string]: any }?): Env
	local project = serde.decode("json", fs.readFile(`{root}/default.project.json`))
	local game = newInstance("game", "DataModel", nil, nil)
	mountNode(root, project.tree, game)

	local cache: { [VInstance]: any } = {}
	local loading: { [VInstance]: boolean } = {}
	local env: Env = { game = game, require = nil :: any, extraGlobals = extraGlobals or {} }

	local function vrequire(target: any): any
		if type(target) == "string" then
			return require(target)
		end
		if getmetatable(target) ~= VInstanceMeta then
			error("require expects a ModuleScript", 2)
		end
		local cached = cache[target]
		if cached ~= nil then
			return cached
		end
		local file = rawget(target, "__file")
		if not file then
			error(`{instanceMethods.GetFullName(target)} is not a ModuleScript`, 2)
		end
		if loading[target] then
			error(`cyclic require of {instanceMethods.GetFullName(target)}`, 2)
		end
		loading[target] = true
		local globals: { [string]: any } = { script = target, require = vrequire, game = game }
		for k, v in env.extraGlobals do
			globals[k] = v
		end
		local chunk = luau.load(fs.readFile(file), { debugName = file, environment = globals })
		local result = chunk()
		loading[target] = nil
		cache[target] = if result == nil then true else result
		return result
	end
	env.require = vrequire
	return env
end

-- Resolves "ReplicatedStorage.Shared.Sim.Engine" style paths.
function Loader.find(env: Env, dotted: string): VInstance
	local node = env.game
	for part in string.gmatch(dotted, "[^%.]+") do
		node = node:WaitForChild(part)
	end
	return node
end

return Loader
