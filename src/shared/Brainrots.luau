local Brainrots = {
	-- Common
	{ name = "Tralalero Tralala", rarity = "Common", imageId = "116597140173840", incomePerSec = 25, spawnWeight = 60 },
	{ name = "Ta Ta Ta Ta Sahur", rarity = "Common", imageId = "135177356944663", incomePerSec = 28, spawnWeight = 60 },
	{ name = "Pipi Kiwi", rarity = "Common", imageId = "109595881341378", incomePerSec = 32, spawnWeight = 30 },
	{ name = "Lirili Larila", rarity = "Common", imageId = "82609156714796", incomePerSec = 35, spawnWeight = 30 },
	-- Rare
	{ name = "Boneca Ambalabu", rarity = "Rare", imageId = "122338324527276", incomePerSec = 95, spawnWeight = 60 },
	{ name = "Br Br Patapim", rarity = "Rare", imageId = "77589601141688", incomePerSec = 120, spawnWeight = 60 },
	{ name = "Burbaloni Loliloli", rarity = "Rare", imageId = "124726034048520", incomePerSec = 165, spawnWeight = 30 },
	{ name = "Svinina Bombardino", rarity = "Rare", imageId = "76078077826086", incomePerSec = 180, spawnWeight = 30 },
	-- Epic
	{ name = "Bananita Dolphinita", rarity = "Epic", imageId = "122671097291692", incomePerSec = 590, spawnWeight = 60 },
	{ name = "Cappucino Assasino", rarity = "Epic", imageId = "93894297615026", incomePerSec = 680, spawnWeight = 60 },
	{ name = "Frigo Camelo", rarity = "Epic", imageId = "119705041788614", incomePerSec = 875, spawnWeight = 30 },
	{ name = "Orangutini Ananassini", rarity = "Epic", imageId = "83625339319929", incomePerSec = 1000, spawnWeight = 30 },
	-- Legendary
	{ name = "Ballerina Cappuccina", rarity = "Legendary", imageId = "120231232977377", incomePerSec = 2500, spawnWeight = 60 },
	{ name = "La Vacca Saturno Saturnita", rarity = "Legendary", imageId = "115600384704376", incomePerSec = 3000, spawnWeight = 60 },
	{ name = "Odin Din Din Dun", rarity = "Legendary", imageId = "133565525389233", incomePerSec = 4200, spawnWeight = 30 },
	{ name = "Trulimero Trulicina", rarity = "Legendary", imageId = "104196176450796", incomePerSec = 5000, spawnWeight = 30 },
	-- Mythic
	{ name = "Bombombini Gusini", rarity = "Mythic", imageId = "80026740968675", incomePerSec = 11000, spawnWeight = 60 },
	{ name = "Garamararam", rarity = "Mythic", imageId = "87958705169061", incomePerSec = 13000, spawnWeight = 60 },
	{ name = "Giraffa Celestre", rarity = "Mythic", imageId = "125909385975837", incomePerSec = 14500, spawnWeight = 30 },
	{ name = "Job Job Job Sahur", rarity = "Mythic", imageId = "108613378713759",  incomePerSec = 18000, spawnWeight = 30 },
	-- Secret
	{ name = "67 Letter", rarity = "Secret", imageId = "92927080723209", incomePerSec = 55000, spawnWeight = 60 },
	{ name = "Esok Sekolah", rarity = "Secret", imageId = "99495931235802", incomePerSec = 70000, spawnWeight = 60 },
	{ name = "Karkerkar Kurkur", rarity = "Secret", imageId = "83711326101506", incomePerSec = 90000, spawnWeight = 30 },
	{ name = "Matteo", rarity = "Secret", imageId = "77477463021579", incomePerSec = 110000, spawnWeight = 30 },
	-- Divine
	{ name = "Ballerino Lololo", rarity = "Divine", imageId = "139589594957694", incomePerSec = 200000, spawnWeight = 60 },
	{ name = "Crab Chef", rarity = "Divine", imageId = "112382794552743", incomePerSec = 250000, spawnWeight = 60 },
	{ name = "Garama", rarity = "Divine", imageId = "97814624497045", incomePerSec = 300000, spawnWeight = 30 },
	{ name = "Strawberry Elephant", rarity = "Divine", imageId = "70996787496449", incomePerSec = 350000, spawnWeight = 30 },
	-- Ancient
	{ name = "Alessio", rarity = "Ancient", imageId = "112367179203055", incomePerSec = 900000, spawnWeight = 60 },
	{ name = "Spaghetti Tualetti", rarity = "Ancient", imageId = "102814813397762", incomePerSec = 1200000, spawnWeight = 60 },
	{ name = "Torrtuginni Dragonfrutini", rarity = "Ancient", imageId = "98338881191753", incomePerSec = 1800000, spawnWeight = 30 },
	{ name = "Dragon Cannelloni", rarity = "Ancient", imageId = "136755664449432", incomePerSec = 2300000, spawnWeight = 30 },
	-- Exclusive
	{ name = "Tung Tung Sahur", rarity = "Exclusive", imageId = "120839622539296", incomePerSec = 167, spawnWeight = 0 },
}

-- Level/Income scaling by rarity (v2 — Max Level 50)
Brainrots.RarityScaling = {
	Common = { incomeScale = 0.30, costMult = 10 },
	Rare = { incomeScale = 0.30, costMult = 10 },
	Epic = { incomeScale = 0.30, costMult = 10 },
	Legendary = { incomeScale = 0.30, costMult = 10 },
	Mythic = { incomeScale = 0.30, costMult = 10 },
	Secret = { incomeScale = 0.30, costMult = 10 },
	Divine = { incomeScale = 0.30, costMult = 10 },
	Ancient = { incomeScale = 0.30, costMult = 10 },
	Exclusive = { incomeScale = 0.30, costMult = 10 },
}

Brainrots.MaxLevel = 50
Brainrots.CostGrowth = 1.12

function Brainrots.getIncomeAtLevel(baseIncome, rarity, level)
	local scaling = Brainrots.RarityScaling[rarity]
	if not scaling then
		return baseIncome
	end
	return math.floor(baseIncome * (1 + scaling.incomeScale * (level - 1)))
end

function Brainrots.getUpgradeCost(baseIncome, rarity, currentLevel)
	if currentLevel >= Brainrots.MaxLevel then
		return nil
	end
	local scaling = Brainrots.RarityScaling[rarity]
	if not scaling then
		return nil
	end
	return math.floor(baseIncome * scaling.costMult * (Brainrots.CostGrowth ^ (currentLevel - 1)))
end

function Brainrots.getIncomeWithMutation(baseIncome, rarity, level, mutation)
	local base = Brainrots.getIncomeAtLevel(baseIncome, rarity, level)
	local Config = require(game.ReplicatedStorage.Config)
	local mult = Config.MutationMultipliers[mutation] or 1.0
	return math.floor(base * mult)
end

return Brainrots