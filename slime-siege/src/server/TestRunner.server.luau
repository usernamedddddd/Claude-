--!strict
-- Studio-only: runs the TestEZ specs in ServerStorage.Tests when the Workspace attribute
-- "RunTests" is true. Requires `wally install` (TestEZ lands in ServerStorage.DevPackages).
-- Headless CI runs the same specs with `lune run tools/test`.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() or Workspace:GetAttribute("RunTests") ~= true then
	return
end

local packages = ServerStorage:FindFirstChild("DevPackages")
local testEZModule = packages and packages:FindFirstChild("TestEZ")
if not testEZModule or not testEZModule:IsA("ModuleScript") then
	warn("[Tests] TestEZ not found. Run `wally install` and rebuild with Rojo.")
	return
end

local TestEZ = (require :: any)(testEZModule)
TestEZ.TestBootstrap:run({ ServerStorage:WaitForChild("Tests") })
