--!strict
-- The one entry point for purchases on the client:
--   Monetization.promptPurchase(productKey, onGranted)
-- The server (MonetizationService) decides; in the MVP it prints and grants in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Products = require(Shared.Data.Products)

local Monetization = {}

local pending: { [string]: { () -> () } } = {}
local started = false

local function start()
	if started then
		return
	end
	started = true
	Remotes.get("PurchaseResult").OnClientEvent:Connect(function(productKey: string, granted: boolean)
		local callbacks = pending[productKey]
		pending[productKey] = nil
		if granted and callbacks then
			for _, callback in callbacks do
				task.spawn(callback)
			end
		end
	end)
end

function Monetization.promptPurchase(productKey: string, onGranted: (() -> ())?)
	start()
	if not Products[productKey] then
		warn(`[Monetization] unknown product {productKey}`)
		return
	end
	print(`[Monetization] prompting {productKey}`)
	if onGranted then
		local list = pending[productKey] or {}
		table.insert(list, onGranted)
		pending[productKey] = list
	end
	Remotes.get("PurchaseRequest"):FireServer(productKey)
end

return Monetization
