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
	CannonCostScale = 1.10, -- cost multiplier per power level owned
	MaxCannonPower = 130, -- set to whatever cannon launch physics top-end is
	CannonUpgradeCosts = {
		{amount = 1,  cost = 1500},
		{amount = 5,  cost = 6000},
		{amount = 10, cost = 11000},
	},

	MutationGoldChance = 0.08,
	MutationDiamondChance = 0.04,
	MutationMultipliers = {
		None = 1.0,
		Gold = 1.5,
		Diamond = 2.0,
	},

	-- Rebirth
	RebirthBaseMultiplier = 1.0,
	RebirthRequirements = {
		{ rebirth = 1, power = 20, multiplier = 1.5 },
		{ rebirth = 2, power = 40, multiplier = 2.0 },
		{ rebirth = 3, power = 60, multiplier = 2.5 },
		{ rebirth = 4, power = 80, multiplier = 3.0 },
		{ rebirth = 5, power = 90, multiplier = 3.5 },
		{ rebirth = 6, power = 100, multiplier = 4.0 },
		{ rebirth = 7, power = 110, multiplier = 4.5 },
		{ rebirth = 8, power = 120, multiplier = 5.0 },
	},
}

return Config
