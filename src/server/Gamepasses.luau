local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local Gamepasses = {}

local initialized = false
local passIdToKey = {}

local function getAttributeName(key)
	return "Has" .. key
end

local function setOwnershipAttribute(player, key, owned)
	player:SetAttribute(getAttributeName(key), owned == true)
end

local function refreshOwnership(player)
	for key, passId in pairs(Config.Gamepasses) do
		local ok, ownedOrError = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)

		if ok then
			setOwnershipAttribute(player, key, ownedOrError)
		else
			setOwnershipAttribute(player, key, false)
			warn(string.format("[Gamepasses] Failed ownership check for %s (%s): %s", player.Name, key, tostring(ownedOrError)))
		end
	end

	local character = player.Character
	if character then
		Gamepasses.applyDefaultSpeed(player, character:FindFirstChildOfClass("Humanoid"))
	end
end

local function bindPlayer(player)
	for key in pairs(Config.Gamepasses) do
		setOwnershipAttribute(player, key, false)
	end

	player.CharacterAdded:Connect(function(character)
		Gamepasses.applyDefaultSpeed(player, character:WaitForChild("Humanoid"))
	end)

	player:GetAttributeChangedSignal(getAttributeName("SpeedBoost")):Connect(function()
		local character = player.Character
		if not character then
			return
		end

		Gamepasses.applyDefaultSpeed(player, character:FindFirstChildOfClass("Humanoid"))
	end)

	if player.Character then
		task.spawn(function()
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				Gamepasses.applyDefaultSpeed(player, humanoid)
			end
		end)
	end

	task.spawn(refreshOwnership, player)
end

function Gamepasses.has(player, key)
	if not player then
		return false
	end

	return player:GetAttribute(getAttributeName(key)) == true
end

function Gamepasses.getDefaultWalkSpeed(player)
	if Gamepasses.has(player, "SpeedBoost") then
		return Config.DefaultWalkSpeed * Config.GamepassValues.SpeedBoostMultiplier
	end

	return Config.DefaultWalkSpeed
end

function Gamepasses.applyDefaultSpeed(player, humanoid)
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = Gamepasses.getDefaultWalkSpeed(player)
end

function Gamepasses.init()
	if initialized then
		return
	end

	initialized = true

	for key, passId in pairs(Config.Gamepasses) do
		passIdToKey[passId] = key
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		local key = passIdToKey[gamePassId]
		if not key or not wasPurchased or not player then
			return
		end

		setOwnershipAttribute(player, key, true)
	end)

	Players.PlayerAdded:Connect(bindPlayer)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return Gamepasses
