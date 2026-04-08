-- shared/Config.luau

local Config = {
	-- Base
	MaxSlots = 12,
	MaxPlayers = 5,
	IncomeTickRate = 1,

	-- Spawner
	SpawnInterval = 5,
	MaxSpawns = 8,

	-- Despawn times per rarity (seconds, nil = never despawns)
	DespawnTimes = {
		Common = 30,
		Rare = 45,
		Epic = 60,
		Legendary = 90,
		Mythic = nil,
	},

	-- Pickup
	PickupHoldDuration = 0.5,  -- seconds to hold E
	PickupRange = 8,            -- studs away to see prompt
	CarryOffset = Vector3.new(0, 3, 0),  -- height above player head
}

return Config