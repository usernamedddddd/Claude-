--!strict
-- Server half of Monetization. Clients call Monetization.promptPurchase(productKey, onGranted)
-- (src/client/Controllers/Monetization), which sends PurchaseRequest here.
--
-- MVP behaviour: products have id 0. In Studio the purchase is printed and granted
-- immediately; in live servers it is refused with "coming soon". Once real ids are filled
-- in Data/Products, the real MarketplaceService prompts and ProcessReceipt take over.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Data.Products)
local Remotes = require(Shared.Net.Remotes)
local Guard = require(script.Parent.Guard)
local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local grantedCallbacks: { (Player, string) -> () } = {}

local function productByKey(key: string): Products.Product?
	return Products[key]
end

local function productById(kind: string, id: number): Products.Product?
	if id == 0 then
		return nil
	end
	for _, p in Products do
		if p.kind == kind and p.id == id then
			return p
		end
	end
	return nil
end

local function applyGrant(player: Player, product: Products.Product): boolean
	local ok = DataService.update(player, function(profile)
		if product.kind == "gamepass" then
			profile.passes[product.key] = true
		elseif product.goo then
			profile.goo += product.goo
		end
	end)
	if ok then
		Remotes.get("PurchaseResult"):FireClient(player, product.key, true)
		for _, callback in grantedCallbacks do
			task.spawn(callback, player, product.key)
		end
	end
	return ok
end

function MonetizationService.onGranted(callback: (Player, string) -> ())
	table.insert(grantedCallbacks, callback)
end

local function onPurchaseRequest(player: Player, rawKey: unknown)
	if not Guard.allow(player, "Purchase", 0.5, 3) then
		return
	end
	local key = Guard.key(rawKey, Products)
	if not key then
		return
	end
	local product = productByKey(key) :: Products.Product
	Analytics.track("purchase_prompted", { userId = player.UserId, product = key })

	if product.kind == "gamepass" and DataService.hasPass(player, key) then
		Remotes.get("Notify"):FireClient(player, "You already own this!", "info")
		return
	end

	if product.id == 0 then
		if RunService:IsStudio() then
			print(`[Monetization] Studio stub: granting {key} to {player.Name}`)
			applyGrant(player, product)
		else
			Remotes.get("Notify"):FireClient(player, "Coming soon!", "info")
			Remotes.get("PurchaseResult"):FireClient(player, key, false)
		end
		return
	end

	if product.kind == "gamepass" then
		MarketplaceService:PromptGamePassPurchase(player, product.id)
	else
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productById("devproduct", receipt.ProductId)
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not DataService.recordReceipt(profile, tostring(receipt.PurchaseId)) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	if not applyGrant(player, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Persist promptly so a crash can't lose a paid grant.
	if not DataService.saveNow(player, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function syncOwnedPasses(player: Player)
	for key, product in Products do
		if product.kind == "gamepass" and product.id ~= 0 and not DataService.hasPass(player, key) then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, product.id)
			end)
			if ok and owns then
				applyGrant(player, product)
			end
		end
	end
end

function MonetizationService.start()
	Remotes.get("PurchaseRequest").OnServerEvent:Connect(onPurchaseRequest)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local product = productById("gamepass", passId)
			if product then
				applyGrant(player, product)
			end
		end
	end)
	DataService.onLoaded(function(player)
		syncOwnedPasses(player)
	end)
end

return MonetizationService
