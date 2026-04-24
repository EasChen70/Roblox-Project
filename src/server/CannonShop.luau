-- server/CannonShop.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local PlayerData = require(ServerScriptService.PlayerData)

local CannonShop = {}

local function findUpgrade(amount)
	for _, entry in Config.CannonUpgradeCosts do
		if entry.amount == amount then
			return entry
		end
	end
	return nil
end

-- Actual cost = baseCost * scale^currentPower
local function computeCost(baseCost, currentPower, amount)
	if currentPower == 1 and amount == 1 then
		return 0
	end -- ADD THIS
	return math.floor(baseCost * (Config.CannonCostScale ^ currentPower))
end

function CannonShop.init()
	Remotes.UpgradeCannon.OnServerEvent:Connect(function(player, amount)
		local upgrade = findUpgrade(amount)
		if not upgrade then
			warn("[CannonShop] Invalid amount from", player.Name, amount)
			return
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then
			return
		end
		local money = leaderstats:FindFirstChild("Money")
		if not money then
			return
		end

		local currentPower = player:GetAttribute("CannonPower") or 1
		local actualCost = computeCost(upgrade.cost, currentPower, upgrade.amount)
		print(
			"[CannonShop] Purchase attempt:",
			player.Name,
			"| amount:",
			amount,
			"| currentPower:",
			currentPower,
			"| actualCost:",
			actualCost,
			"| money:",
			money.Value,
			"| canAfford:",
			money.Value >= actualCost
		)
		if money.Value < actualCost then
			return
		end

		money.Value -= actualCost
		local newPower = currentPower + upgrade.amount
		player:SetAttribute("CannonPower", newPower)

		PlayerData.requestSave(player)
		print(
			"[CannonShop]",
			player.Name,
			"upgraded cannon +",
			upgrade.amount,
			"→ Power:",
			newPower,
			"Cost was:",
			actualCost
		)
	end)
end

return CannonShop
