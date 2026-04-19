local Brainrots = {
	-- Common
	{ name = "Tralalero Tralala",     rarity = "Common",    incomePerSec = 5,    spawnWeight = 50 },
	{ name = "Ta Ta Ta Ta Sahur",     rarity = "Common",    incomePerSec = 7,    spawnWeight = 50 },
	{ name = "Pipi Kiwi",             rarity = "Common",    incomePerSec = 10,   spawnWeight = 30 },
	{ name = "Lirili Larila",         rarity = "Common",    incomePerSec = 12,   spawnWeight = 30 },
	-- Rare
	{ name = "Boneca Ambalabu",       rarity = "Rare",      incomePerSec = 25,   spawnWeight = 40 },
	{ name = "Br Br Patapim",         rarity = "Rare",      incomePerSec = 30,   spawnWeight = 40 },
	{ name = "Burbaloni Loliloli",    rarity = "Rare",      incomePerSec = 35,   spawnWeight = 30 },
	{ name = "Svinina Bombardino",    rarity = "Rare",      incomePerSec = 40,   spawnWeight = 30 },
	-- Epic
	{ name = "Bananita Dolphinita",   rarity = "Epic",      incomePerSec = 75,   spawnWeight = 35 },
	{ name = "Cappucino Assasino",    rarity = "Epic",      incomePerSec = 85,   spawnWeight = 35 },
	{ name = "Frigo Camelo",          rarity = "Epic",      incomePerSec = 95,   spawnWeight = 25 },
	{ name = "Orangutini Ananassini", rarity = "Epic",      incomePerSec = 100,  spawnWeight = 25 },
	-- Legendary
	{ name = "Ballerina Cappuccina",       rarity = "Legendary", incomePerSec = 200,  spawnWeight = 30 },
	{ name = "La Vacca Saturno Saturnita", rarity = "Legendary", incomePerSec = 225,  spawnWeight = 30 },
	{ name = "Odin Din Din Dun",           rarity = "Legendary", incomePerSec = 250,  spawnWeight = 25 },
	{ name = "Trulimero Trulicina",        rarity = "Legendary", incomePerSec = 275,  spawnWeight = 25 },
	-- Mythic
	{ name = "Bombombini Gusini",     rarity = "Mythic",    incomePerSec = 500,  spawnWeight = 30 },
	{ name = "Garamararam",           rarity = "Mythic",    incomePerSec = 550,  spawnWeight = 30 },
	{ name = "Giraffa Celestre",      rarity = "Mythic",    incomePerSec = 600,  spawnWeight = 25 },
	{ name = "Job Job Job Sahur",     rarity = "Mythic",    incomePerSec = 650,  spawnWeight = 25 },
	-- Secret
	{ name = "67 Letter",             rarity = "Secret",    incomePerSec = 1000, spawnWeight = 25 },
	{ name = "Esok Sekolah",          rarity = "Secret",    incomePerSec = 1100, spawnWeight = 25 },
	{ name = "Karkerkar Kurkur",      rarity = "Secret",    incomePerSec = 1200, spawnWeight = 25 },
	{ name = "Matteo",                rarity = "Secret",    incomePerSec = 1300, spawnWeight = 25 },
}

-- Level/Income scaling by rarity (v2 — Max Level 50)
Brainrots.RarityScaling = {
	Common    = { incomeScale = 0.05, costMult = 8  },
	Rare      = { incomeScale = 0.07, costMult = 10 },
	Epic      = { incomeScale = 0.09, costMult = 13 },
	Legendary = { incomeScale = 0.12, costMult = 18 },
	Mythic    = { incomeScale = 0.18, costMult = 26 },
	Secret    = { incomeScale = 0.25, costMult = 35 },
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

return Brainrots