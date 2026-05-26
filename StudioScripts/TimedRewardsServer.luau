local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local RemotesModule = require(ReplicatedStorage:WaitForChild("Remotes"))
local Brainrots = require(ReplicatedStorage:WaitForChild("Brainrots"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

local REWARDS_CONFIG = {
	[1] = {Type = "Cash", Amount = 10000000,    Mins = 10},
	[2] = {Type = "Item", Rarity = "Legendary",   Mins = 20},
	[3] = {Type = "Cash", Amount = 100000000,  Mins = 30},
	[4] = {Type = "Item", Rarity = "Secret", Mins = 40},
	[5] = {Type = "Cash", Amount = 1000000000, Mins = 50},
	[6] = {Type = "Item", Rarity = "Ancient",  Mins = 60},
}

-- Pre-process Brainrots into a lookup table for O(1) access
local BrainrotsByRarity = {}
for _, data in ipairs(Brainrots) do
	local rarity = data.Rarity or data.rarity or data.RARITY or data.Tier or data.tier
	if rarity then
		local key = string.lower(tostring(rarity))
		BrainrotsByRarity[key] = BrainrotsByRarity[key] or {}
		table.insert(BrainrotsByRarity[key], data)
	end
end

local sessionClaims = {}

local function getRandomBrainrot(rarity)
	local eligible = BrainrotsByRarity[string.lower(rarity)]
	if not eligible or #eligible == 0 then return nil end
	return eligible[math.random(1, #eligible)]
end

RemotesModule.ClaimTimedReward.OnServerEvent:Connect(function(player, rewardIndex)
	local config = REWARDS_CONFIG[rewardIndex]
	if not config then return end

	-- Validate Time
	local joinTime = player:GetAttribute("JoinTime") or os.time()
	if (os.time() - joinTime) / 60 < config.Mins then return end

	-- Validate and Track Claims
	local userId = player.UserId
	sessionClaims[userId] = sessionClaims[userId] or {}
	if sessionClaims[userId][rewardIndex] then return end

	-- Grant Rewards
	if config.Type == "Cash" then
		local money = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Money")
		if money then
			money.Value += config.Amount
			sessionClaims[userId][rewardIndex] = true -- Only mark claimed if logic succeeds
		end
	elseif config.Type == "Item" then
		local itemData = getRandomBrainrot(config.Rarity)
		local itemName = itemData and (itemData.Name or itemData.name or itemData.Id or itemData.id)

		if itemName then
			local success = Pickup.giveItem(player, itemName, config.Rarity, nil, 1, "None")
			if success then
				sessionClaims[userId][rewardIndex] = true
			end
		end
	end
end)

local function onPlayerAdded(player)
	player:SetAttribute("JoinTime", os.time())
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do onPlayerAdded(p) end

Players.PlayerRemoving:Connect(function(player)
	sessionClaims[player.UserId] = nil
end)