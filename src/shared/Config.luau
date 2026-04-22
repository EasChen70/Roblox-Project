-- shared/Config.luau

local Config = {
	-- Base
	MaxSlots = 12,
	MaxPlayers = 5,
	IncomeTickRate = 1,
	PlacementYOffset = -0.5,
	UpgradeSoundId = "rbxassetid://76834925120308",
	
	-- Spawner
	SpawnInterval = 3,
	MaxSpawns = 10,
	DespawnTimeMin = 30,
	DespawnTimeMax = 60,

	-- Pickup
	MaxInventory = 10,
	PickupHoldDuration = 0.6,
	PickupRange = 8,
	CarryOffset = Vector3.new(0, 3, 0),
	CarryRotation = CFrame.Angles(0, math.rad(180), 0),
	CarryAnimationId = "rbxassetid://76257603071803",

	--CannonShop
	CannonCostScale = 1.1,  -- cost multiplier per power level owned
	CannonUpgradeCosts = {
		{amount = 1,  cost = 500},
		{amount = 5,  cost = 2500},
		{amount = 10, cost = 5000},
	},

	MutationGoldChance = 0.10,
	MutationDiamondChance = 0.05,
	MutationMultipliers = {
		None = 1.0,
		Gold = 1.5,
		Diamond = 2.0,
	}
}

return Config