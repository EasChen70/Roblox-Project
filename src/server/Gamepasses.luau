local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local Gamepasses = {}

local initialized = false
local passIdToKey = {}
local ownershipRefreshCache = {}
local OWNERSHIP_CACHE_WINDOW = 5
local RESPAWN_RECOVERY_DELAYS = { 0, 0.15, 0.5 }
local respawnRecoveryTokens = {}
local zeroVector = Vector3.new(0, 0, 0)

local function getAttributeName(key)
	return "Has" .. key
end

local function setOwnershipAttribute(player, key, owned)
	player:SetAttribute(getAttributeName(key), owned == true)
end

local function cloneOwnershipResult(result)
	local cloned = {
		allSucceeded = result ~= nil and result.allSucceeded ~= false,
		ownership = {},
		resolved = {},
	}

	if result then
		for key, value in pairs(result.ownership or {}) do
			cloned.ownership[key] = value == true
		end

		for key, value in pairs(result.resolved or {}) do
			cloned.resolved[key] = value == true
		end
	end

	return cloned
end

function Gamepasses.refreshOwnershipNow(player)
	if not player then
		return {
			allSucceeded = false,
			ownership = {},
			resolved = {},
		}
	end

	local cached = ownershipRefreshCache[player]
	local now = tick()
	if cached and (now - cached.at) <= OWNERSHIP_CACHE_WINDOW then
		return cloneOwnershipResult(cached.result)
	end

	local result = {
		allSucceeded = true,
		ownership = {},
		resolved = {},
	}

	for key, passId in pairs(Config.Gamepasses) do
		local previousOwned = Gamepasses.has(player, key)
		local ok, ownedOrError = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)

		if ok then
			local owned = ownedOrError == true
			result.ownership[key] = owned
			result.resolved[key] = true
			setOwnershipAttribute(player, key, owned)
		else
			result.allSucceeded = false
			result.ownership[key] = previousOwned == true
			result.resolved[key] = false
			if previousOwned then
				setOwnershipAttribute(player, key, true)
			end
		end
	end

	local character = player.Character
	if character then
		Gamepasses.applyCharacterDefaults(player, character:FindFirstChildOfClass("Humanoid"))
	end

	ownershipRefreshCache[player] = {
		at = now,
		result = cloneOwnershipResult(result),
	}

	return cloneOwnershipResult(result)
end

local function scheduleRespawnRecovery(player, character)
	respawnRecoveryTokens[player] = (respawnRecoveryTokens[player] or 0) + 1
	local token = respawnRecoveryTokens[player]

	for passIndex, delaySeconds in ipairs(RESPAWN_RECOVERY_DELAYS) do
		local scheduledPassIndex = passIndex
		local scheduledDelaySeconds = delaySeconds
		task.delay(scheduledDelaySeconds, function()
			if respawnRecoveryTokens[player] ~= token or player.Character ~= character or not character.Parent then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				humanoid = character:WaitForChild("Humanoid", 1)
			end
			if not humanoid or not humanoid.Parent then
				return
			end

			local options = {
				zeroVelocity = scheduledPassIndex == 1,
			}
			if scheduledPassIndex == 1 then
				options.state = Enum.HumanoidStateType.GettingUp
			elseif scheduledPassIndex == #RESPAWN_RECOVERY_DELAYS then
				options.state = Enum.HumanoidStateType.Running
			end

			Gamepasses.applyCharacterDefaults(player, humanoid, options)
		end)
	end
end

local function bindPlayer(player)
	for key in pairs(Config.Gamepasses) do
		setOwnershipAttribute(player, key, false)
	end

	player.CharacterAdded:Connect(function(character)
		scheduleRespawnRecovery(player, character)
	end)

	player:GetAttributeChangedSignal(getAttributeName("SpeedBoost")):Connect(function()
		local character = player.Character
		if not character then
			return
		end

		Gamepasses.applyCharacterDefaults(player, character:FindFirstChildOfClass("Humanoid"))
	end)

	if player.Character then
		task.spawn(function()
			local character = player.Character
			if not character then
				return
			end

			scheduleRespawnRecovery(player, character)
		end)
	end

	task.spawn(function()
		Gamepasses.refreshOwnershipNow(player)
	end)
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

function Gamepasses.applyCharacterDefaults(player, humanoid, options)
	if not humanoid then
		return
	end

	local useLegacyDefaults = options == nil
	options = options or {}
	local shouldZeroVelocity = useLegacyDefaults or options.zeroVelocity == true
	local targetState = useLegacyDefaults and Enum.HumanoidStateType.GettingUp or options.state

	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid.Jump = false
	humanoid.Sit = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	Gamepasses.applyDefaultSpeed(player, humanoid)
	if targetState then
		humanoid:ChangeState(targetState)
	end

	local character = humanoid.Parent
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart and character then
		rootPart = character:WaitForChild("HumanoidRootPart", 1)
	end

	if rootPart then
		rootPart.Anchored = false
		if shouldZeroVelocity then
			rootPart.AssemblyLinearVelocity = zeroVector
			rootPart.AssemblyAngularVelocity = zeroVector
		end
	end
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
		ownershipRefreshCache[player] = nil
	end)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ownershipRefreshCache[player] = nil
		respawnRecoveryTokens[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return Gamepasses
