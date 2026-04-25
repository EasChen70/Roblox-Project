-- server/Rebirth.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local PlayerData = require(ServerScriptService.PlayerData)

local Rebirth = {}

local rebirthDebounce = {}

local function getNextRebirth(currentRebirths)
	return Config.RebirthRequirements[currentRebirths + 1]
end

local function canRebirth(player)
	local currentRebirths = player:FindFirstChild("leaderstats") and
		player.leaderstats:FindFirstChild("Rebirths") and
		player.leaderstats.Rebirths.Value or 0

	if currentRebirths >= #Config.RebirthRequirements then
		return false, "max"
	end

	local next = getNextRebirth(currentRebirths)
	if not next then
		return false, "max"
	end

	local currentPower = player:GetAttribute("CannonPower") or 1
	if currentPower < next.power then
		return false, "power"
	end

	return true, next
end

local function doRebirth(player)
	local ok, result = canRebirth(player)
	if not ok then
		print("[Rebirth]", player.Name, "cannot rebirth —", result)
		return
	end

	local next = result

	-- Apply rebirth
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local rebirths = leaderstats:FindFirstChild("Rebirths")
	local money = leaderstats:FindFirstChild("Money")
	if not rebirths or not money then return end

	-- Increment rebirth count
	rebirths.Value += 1

	-- Reset money and cannon power
	money.Value = 0
	player:SetAttribute("CannonPower", 1)

	-- Apply new multiplier
	player:SetAttribute("RebirthMultiplier", next.multiplier)

	-- Save
	PlayerData.requestSave(player)

	print("[Rebirth]", player.Name, "rebirthed →", rebirths.Value,
		"| multiplier:", next.multiplier,
		"| power reset to 1")
end

function Rebirth.init()
	Remotes.Rebirth.OnServerEvent:Connect(function(player)
		if rebirthDebounce[player] then
			return
		end
		rebirthDebounce[player] = true

		local ok, err = pcall(doRebirth, player)
		if not ok then
			warn("[Rebirth] Error for", player.Name, err)
		end

		task.delay(1, function()
			rebirthDebounce[player] = nil
		end)
	end)
end

-- Clean up on disconnect
Players.PlayerRemoving:Connect(function(player)
	rebirthDebounce[player] = nil
end)

return Rebirth