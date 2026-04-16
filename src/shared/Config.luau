-- shared/Config.luau

local Config = {
	-- Base
	MaxSlots = 12,
	MaxPlayers = 5,
	IncomeTickRate = 1,

	-- Spawner
	SpawnInterval = 3,
	MaxSpawns = 10,
	DespawnTimeMin = 30,
	DespawnTimeMax = 60,

	-- Pickup
	MaxInventory = 10,
	PickupHoldDuration = 0.6,  -- seconds to hold E
	PickupRange = 8,            -- studs away to see prompt
	CarryOffset = Vector3.new(0, 3, 0),  -- height above player head
}

return Config