local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CannonShop = require(ServerScriptService.CannonShop)
local SellShop = require(ServerScriptService.SellShop)
local Rebirth = require(ServerScriptService.Rebirth)
local Base = require(ServerScriptService.Base)
local Gamepasses = require(ServerScriptService.Gamepasses)
local Spawner = require(ServerScriptService.Spawner)
local Pickup = require(ServerScriptService.Pickup)
local Placement = require(ServerScriptService.Placement)
local Income = require(ServerScriptService.Income)
local PlayerData = require(ServerScriptService.PlayerData)
local Tutorial = require(ServerScriptService.Tutorial)
local CommunityRewards = require(ServerScriptService.CommunityRewards)
local Gifting = require(ServerScriptService.Gifting)

Spawner.start()

Placement.setup()
Income.setup()

PlayerData.setup()
Tutorial.init()
CommunityRewards.init()
Gifting.init()
Gamepasses.init()
PlayerData.start()

Income.start()

-- Ordered PlayerRemoving: save player state BEFORE destroying placed brainrots
Players.PlayerRemoving:Connect(function(player)
	Gifting.cleanupPlayer(player)
	-- 1. Save slot state first (reads live models from base while they still exist)
	PlayerData.clearSession(player)
	-- 2. Then release base + destroy placed brainrots + reset slot visuals
	Base.releaseBase(player)
	Pickup.cleanup(player)
end)

-- Wire world grab: Spawner fires callback → Pickup.grab handles it
-- Eliminates DescendantAdded leak (no longer watching Workspace for prompts)
Spawner.onGrab(function(player, model)
	Pickup.grab(player, model)
	Tutorial.handleGrab(player, model)
end)

Placement.onDataChanged(function(player)
	PlayerData.requestSave(player)
	Tutorial.handlePlacementDataChanged(player)
end)

Income.onDataChanged(function(player)
	PlayerData.requestSave(player)
	Tutorial.handleIncomeDataChanged(player)
end)

Pickup.onStash(function(player)
	Placement.refreshPrompts(player)
	PlayerData.requestSave(player)
	Tutorial.handleStash(player)
end)

Pickup.onEquipChanged(function(player)
	Placement.refreshPrompts(player)
end)

CannonShop.init()
SellShop.init()
Rebirth.init()
Tutorial.start()
