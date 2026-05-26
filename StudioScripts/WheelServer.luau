local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Shared Modules
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Brainrots = require(ReplicatedStorage:WaitForChild("Brainrots"))
local Util = require(ReplicatedStorage:WaitForChild("Util"))

-- Server Modules
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

-- CONFIGURATION
local SPIN_COOLDOWN = 600 
local SOUND_DURATION = 4.5 -- Matches the length of rbxassetid://9120150534

local REWARDS = {
	{Name = "Epic Brainrot",      Weight = 30, Deg = 0,   Type = "Brainrot", Rarity = "Epic"},
	{Name = "10M Cash",           Weight = 30, Deg = 60,  Type = "Cash",     Amount = 10000000},
	{Name = "Legendary Brainrot",      Weight = 20, Deg = 120, Type = "Brainrot", Rarity = "Legendary"},
	{Name = "100M Cash",          Weight = 10, Deg = 180, Type = "Cash",     Amount = 100000000},
	{Name = "Mythic Brainrot", Weight = 5,  Deg = 240, Type = "Brainrot", Rarity = "Mythic"},
	{Name = "1B Cash",     Weight = 5,  Deg = 300, Type = "Cash",     Amount = 1000000000},
}

local function getRandomReward()
	local totalWeight = 0
	for _, reward in ipairs(REWARDS) do totalWeight += reward.Weight end
	local roll = math.random(1, totalWeight)
	local counter = 0
	for _, reward in ipairs(REWARDS) do
		counter += reward.Weight
		if roll <= counter then return reward end
	end
end

local function getRandomItemByRarity(rarity)
	local eligible = {}
	for _, data in ipairs(Brainrots) do
		if data.rarity == rarity or data.Rarity == rarity then 
			table.insert(eligible, data) 
		end
	end
	return #eligible > 0 and eligible[math.random(1, #eligible)] or nil
end

Remotes.SpinWheel.OnServerEvent:Connect(function(player)
	local lastSpinTime = player:GetAttribute("LastSpinTime") or 0
	local now = os.time()

	if (now - lastSpinTime) < SPIN_COOLDOWN then return end

	local reward = getRandomReward()
	player:SetAttribute("LastSpinTime", now)

	-- Inside Remotes.SpinWheel.OnServerEvent
	Remotes.SpinWheel:FireClient(player, reward)

	-- CHANGE: Wait for the sound and animation to finish before giving the prize
	task.wait(3.5) 

	-- Security Check: Make sure they didn't leave during the spin
	if not player.Parent then return end

	-- Give rewards logic follows here...
	if reward.Type == "Cash" then
		-- ... (reward code)
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats and leaderstats:FindFirstChild("Money") then
			leaderstats.Money.Value += reward.Amount
		end
	elseif reward.Type == "Brainrot" then
		local itemData = getRandomItemByRarity(reward.Rarity)
		if itemData then
			Pickup.giveItem(player, itemData.name or itemData.Name, reward.Rarity, itemData.incomePerSec or 0, 1, "None")
		end
	end

	PlayerData.requestSave(player)
end)