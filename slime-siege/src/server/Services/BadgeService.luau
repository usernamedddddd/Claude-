--!strict
-- Badges: checks every profile change against the badge rules (Shared/Sim/Badges), records
-- newly earned badges, pays their Goo on ClaimBadge, and lets players equip one. Equipped
-- badges show over the player's head in the lobby. Real Roblox badges (non-zero ids) are
-- awarded too, best-effort.

local BadgeServiceRoblox = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeData = require(Shared.Data.BadgeData)
local Theme = require(Shared.Data.Theme)
local Badges = require(Shared.Sim.Badges)
local Remotes = require(Shared.Net.Remotes)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.Guard)

local BadgeService = {}

local TAG_NAME = "BadgeTag"

local evaluating: { [Player]: boolean } = {}

local function notify(player: Player, message: string, kind: string)
	Remotes.get("Notify"):FireClient(player, message, kind)
end

local function awardRoblox(player: Player, def: BadgeData.BadgeDef)
	if def.robloxBadgeId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeServiceRoblox:AwardBadge(player.UserId, def.robloxBadgeId)
		end)
		if not ok then
			warn(`[Badges] AwardBadge {def.id} failed: {err}`)
		end
	end)
end

local function refreshTag(player: Player)
	if ReplicatedStorage:GetAttribute("Mode") ~= "lobby" then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild(TAG_NAME)
	if existing then
		existing:Destroy()
	end
	local profile = DataService.get(player)
	local def = profile and BadgeData.byId[profile.equippedBadge]
	if not def then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.fromOffset(200, 36)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundColor3 = Color3.fromHex("#0B0816")
	label.BackgroundTransparency = 0.25
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextColor3 = Theme.BadgeTint[def.tint]
	label.Text = string.upper(def.name)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = tag
	tag.Parent = head
end

-- Records any newly earned badges. Safe to call often; does nothing when nothing changed.
function BadgeService.evaluate(player: Player)
	if evaluating[player] then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local earned = Badges.newlyEarned(profile)
	if #earned == 0 then
		return
	end
	evaluating[player] = true
	DataService.update(player, function(p)
		for _, def in earned do
			p.badges[def.id] = false
		end
	end)
	evaluating[player] = nil
	for _, def in earned do
		notify(player, `Badge earned: {def.name}! Claim {def.reward} Goo in Badges.`, "success")
		Analytics.track("badge_earned", { userId = player.UserId, badge = def.id })
		awardRoblox(player, def)
	end
end

function BadgeService.claim(player: Player, rawId: unknown): boolean
	if not Guard.allow(player, "ClaimBadge", 4, 6) then
		return false
	end
	local id = Guard.key(rawId, BadgeData.byId)
	local profile = DataService.get(player)
	if not id or not profile or profile.badges[id] ~= false then
		return false
	end
	local def = BadgeData.byId[id]
	DataService.update(player, function(p)
		p.badges[id] = true
		p.goo += def.reward
	end)
	notify(player, `+{def.reward} Goo from {def.name}!`, "success")
	Analytics.track("badge_claimed", { userId = player.UserId, badge = id, goo = def.reward })
	return true
end

function BadgeService.equip(player: Player, rawId: unknown): boolean
	if not Guard.allow(player, "EquipBadge", 4, 6) or type(rawId) ~= "string" then
		return false
	end
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local id = rawId :: string
	if id ~= "" and (BadgeData.byId[id] == nil or profile.badges[id] == nil) then
		return false
	end
	if profile.equippedBadge == id then
		return true
	end
	DataService.update(player, function(p)
		p.equippedBadge = id
	end)
	refreshTag(player)
	return true
end

function BadgeService.start()
	Remotes.get("ClaimBadge").OnServerEvent:Connect(function(player, rawId)
		BadgeService.claim(player, rawId)
	end)
	Remotes.get("EquipBadge").OnServerEvent:Connect(function(player, rawId)
		BadgeService.equip(player, rawId)
	end)
	DataService.onLoaded(function(player)
		BadgeService.evaluate(player)
		refreshTag(player)
	end)
	DataService.onChanged(function(player)
		BadgeService.evaluate(player)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5) -- let the Head exist
			refreshTag(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		evaluating[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return BadgeService
