local Config = require(game.ReplicatedStorage.Config)
local Remotes = require(game.ReplicatedStorage.Remotes)

local Base = require(game.ServerScriptService.Base)
local Spawner = require(game.ServerScriptService.Spawner)
local Pickup = require(game.ServerScriptService.Pickup)
local Placement = require(game.ServerScriptService.Placement)
local Income = require(game.ServerScriptService.Income)
local PlayerData = require(game.ServerScriptService.PlayerData)

Spawner.start()

Placement.setup()
Income.setup()

PlayerData.setup()
PlayerData.start()

Income.start()

-- Wire world grab: Spawner fires callback → Pickup.grab handles it
-- Eliminates DescendantAdded leak (no longer watching Workspace for prompts)
Spawner.onGrab(function(player, model)
	Pickup.grab(player, model)
end)

Placement.onDataChanged(function(player)
	PlayerData.save(player)
end)

Income.onDataChanged(function(player)
	PlayerData.save(player)
end)

Pickup.onStash(function(player)
	Placement.refreshPrompts(player)
	PlayerData.save(player)
end)

Pickup.onEquipChanged(function(player)
	Placement.refreshPrompts(player)
end)

