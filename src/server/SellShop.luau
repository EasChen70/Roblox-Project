-- server/SellShop.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Remotes)
local ShopZones = require(ReplicatedStorage.ShopZones)
local Pickup = require(ServerScriptService.Pickup)
local PlayerData = require(ServerScriptService.PlayerData)

local SellShop = {}

function SellShop.init()
	-- NEW Sell shop
	Remotes.SellInventoryItem.OnServerEvent:Connect(function(player, tool)
		if not ShopZones.isPlayerWithinRange(player, "SellShop") then
			return
		end

		local soldValue = Pickup.sellInventoryTool(player, tool)
		if soldValue > 0 then
			PlayerData.requestSave(player)
		end
	end)

	-- NEW Sell shop
	Remotes.SellAllInventoryItems.OnServerEvent:Connect(function(player)
		if not ShopZones.isPlayerWithinRange(player, "SellShop") then
			return
		end

		local soldCount = Pickup.sellAllInventoryTools(player)
		if soldCount > 0 then
			PlayerData.requestSave(player)
		end
	end)
end

return SellShop
