local Config = require(game.ReplicatedStorage.Config)
local Remotes = require(game.ReplicatedStorage.Remotes)
local Base = require(game.ServerScriptService.Base)
local Spawner = require(game.ServerScriptService.Spawner)
local Pickup = require(game.ServerScriptService.Pickup)
local Placement = require(game.ServerScriptService.Placement)

Spawner.start()
Placement.setup()

Pickup.onStash(function(player)
	Placement.refreshPrompts(player)
end)