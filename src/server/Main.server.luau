local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local CannonShop = require(ServerScriptService.CannonShop)
local Base = require(ServerScriptService.Base)
local Spawner = require(ServerScriptService.Spawner)
local Pickup = require(ServerScriptService.Pickup)
local Placement = require(ServerScriptService.Placement)
local Income = require(ServerScriptService.Income)
local PlayerData = require(ServerScriptService.PlayerData)

Spawner.start()

Placement.setup()
Income.setup()

PlayerData.setup()
PlayerData.start()

Income.start()

-- Ordered PlayerRemoving: save player state BEFORE destroying placed brainrots
Players.PlayerRemoving:Connect(function(player)
	-- 1. Save slot state first (reads live models from base while they still exist)
	PlayerData.clearSession(player)
	-- 2. Then release base + destroy placed brainrots + reset slot visuals
	Base.releaseBase(player)
end)

-- Wire world grab: Spawner fires callback → Pickup.grab handles it
-- Eliminates DescendantAdded leak (no longer watching Workspace for prompts)
Spawner.onGrab(function(player, model)
	Pickup.grab(player, model)
end)

Placement.onDataChanged(function(player)
	PlayerData.requestSave(player)
end)

Income.onDataChanged(function(player)
	PlayerData.requestSave(player)
end)

Pickup.onStash(function(player)
	Placement.refreshPrompts(player)
	PlayerData.requestSave(player)
end)

Pickup.onEquipChanged(function(player)
	Placement.refreshPrompts(player)
end)

CannonShop.init()