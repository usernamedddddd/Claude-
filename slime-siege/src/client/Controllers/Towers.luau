--!strict
-- Client index of replicated tower models (Workspace.Towers), keyed by tower uid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local Towers = {}

Towers.byUid = {} :: { [number]: Model }
Towers.added = Signal.new() :: Signal.Signal<Model, boolean>
Towers.removed = Signal.new() :: Signal.Signal<number>
Towers.folder = nil :: Folder?

local function track(model: Instance, initial: boolean)
	if not model:IsA("Model") then
		return
	end
	local uid = model:GetAttribute("Uid")
	if type(uid) ~= "number" then
		return
	end
	Towers.byUid[uid] = model
	Towers.added:Fire(model, initial)
end

function Towers.footprints(): { { x: number, z: number, footprint: number } }
	local list = {}
	for _, model in Towers.byUid do
		local pivot = model:GetPivot().Position
		local footprint = model:GetAttribute("Footprint")
		table.insert(list, {
			x = pivot.X,
			z = pivot.Z,
			footprint = if type(footprint) == "number" then footprint else 1.5,
		})
	end
	return list
end

function Towers.modelFromPart(part: Instance?): Model?
	local node = part
	while node and node ~= Towers.folder do
		if node:IsA("Model") and node:GetAttribute("Uid") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Towers.start()
	local folder = Workspace:WaitForChild("Towers") :: Folder
	Towers.folder = folder
	for _, child in folder:GetChildren() do
		track(child, true)
	end
	folder.ChildAdded:Connect(function(child)
		-- Attributes replicate with the instance, but wait a frame for safety.
		task.defer(track, child, false)
	end)
	folder.ChildRemoved:Connect(function(child)
		local uid = child:GetAttribute("Uid")
		if type(uid) == "number" and Towers.byUid[uid] == child then
			Towers.byUid[uid] = nil
			Towers.removed:Fire(uid)
		end
	end)
end

return Towers
