local Brainrots = {
	-- Common
	{ name = "Tralalero Tralala",     rarity = "Common",    incomePerSec = 5,       spawnWeight = 60 },
	{ name = "Ta Ta Ta Ta Sahur",     rarity = "Common",    incomePerSec = 8,       spawnWeight = 60 },
	{ name = "Pipi Kiwi",             rarity = "Common",    incomePerSec = 12,      spawnWeight = 30 },
	{ name = "Lirili Larila",         rarity = "Common",    incomePerSec = 15,      spawnWeight = 30 },
	-- Rare
	{ name = "Boneca Ambalabu",       rarity = "Rare",      incomePerSec = 75,      spawnWeight = 60 },
	{ name = "Br Br Patapim",         rarity = "Rare",      incomePerSec = 100,     spawnWeight = 60 },
	{ name = "Burbaloni Loliloli",    rarity = "Rare",      incomePerSec = 125,     spawnWeight = 30 },
	{ name = "Svinina Bombardino",    rarity = "Rare",      incomePerSec = 150,     spawnWeight = 30 },
	-- Epic
	{ name = "Bananita Dolphinita",   rarity = "Epic",      incomePerSec = 500,     spawnWeight = 60 },
	{ name = "Cappucino Assasino",    rarity = "Epic",      incomePerSec = 650,     spawnWeight = 60 },
	{ name = "Frigo Camelo",          rarity = "Epic",      incomePerSec = 750,     spawnWeight = 30 },
	{ name = "Orangutini Ananassini", rarity = "Epic",      incomePerSec = 800,     spawnWeight = 30 },
	-- Legendary
	{ name = "Ballerina Cappuccina",       rarity = "Legendary", incomePerSec = 2000,   spawnWeight = 60 },
	{ name = "La Vacca Saturno Saturnita", rarity = "Legendary", incomePerSec = 2500,   spawnWeight = 60 },
	{ name = "Odin Din Din Dun",           rarity = "Legendary", incomePerSec = 3000,   spawnWeight = 30 },
	{ name = "Trulimero Trulicina",        rarity = "Legendary", incomePerSec = 3500,   spawnWeight = 30 },
	-- Mythic
	{ name = "Bombombini Gusini",     rarity = "Mythic",    incomePerSec = 10000,   spawnWeight = 60 },
	{ name = "Garamararam",           rarity = "Mythic",    incomePerSec = 12000,   spawnWeight = 60 },
	{ name = "Giraffa Celestre",      rarity = "Mythic",    incomePerSec = 13500,   spawnWeight = 30 },
	{ name = "Job Job Job Sahur",     rarity = "Mythic",    incomePerSec = 15000,   spawnWeight = 30 },
	-- Secret
	{ name = "67 Letter",             rarity = "Secret",    incomePerSec = 55000,   spawnWeight = 60 },
	{ name = "Esok Sekolah",          rarity = "Secret",    incomePerSec = 70000,   spawnWeight = 60 },
	{ name = "Karkerkar Kurkur",      rarity = "Secret",    incomePerSec = 90000,   spawnWeight = 30 },
	{ name = "Matteo",                rarity = "Secret",    incomePerSec = 110000,  spawnWeight = 30 },
	-- Divine
	{ name = "Ballerino Lololo",      rarity = "Divine",    incomePerSec = 200000,  spawnWeight = 60 },
	{ name = "Crab Chef",             rarity = "Divine",    incomePerSec = 250000,  spawnWeight = 60 },
	{ name = "Garama",                rarity = "Divine",    incomePerSec = 300000,  spawnWeight = 30 },
	{ name = "Strawberry Elephant",   rarity = "Divine",    incomePerSec = 350000,  spawnWeight = 30 },
}

-- Level/Income scaling by rarity (v2 — Max Level 50)
Brainrots.RarityScaling = {
	Common    = { incomeScale = 0.30, costMult = 10  },
	Rare      = { incomeScale = 0.30, costMult = 10 },
	Epic      = { incomeScale = 0.30, costMult = 10 },
	Legendary = { incomeScale = 0.30, costMult = 10 },
	Mythic    = { incomeScale = 0.30, costMult = 10 },
	Secret    = { incomeScale = 0.30, costMult = 10 },
	Divine 	  = { incomeScale = 0.35, costMult = 10 },
}

Brainrots.MaxLevel = 50
Brainrots.CostGrowth = 1.08

function Brainrots.getIncomeAtLevel(baseIncome, rarity, level)
	local scaling = Brainrots.RarityScaling[rarity]
	if not scaling then return baseIncome end
	return math.floor(baseIncome * (1 + scaling.incomeScale * (level - 1)))
end

function Brainrots.getUpgradeCost(baseIncome, rarity, currentLevel)
	if currentLevel >= Brainrots.MaxLevel then return nil end
	local scaling = Brainrots.RarityScaling[rarity]
	if not scaling then return nil end
	return math.floor(baseIncome * scaling.costMult * (Brainrots.CostGrowth ^ (currentLevel - 1)))
end

function Brainrots.getIncomeWithMutation(baseIncome, rarity, level, mutation)
	local base = Brainrots.getIncomeAtLevel(baseIncome, rarity, level)
	local Config = require(game.ReplicatedStorage.Config)
	local mult = Config.MutationMultipliers[mutation] or 1.0
	return math.floor(base * mult)
end

return Brainrots