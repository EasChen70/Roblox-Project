local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local BrainrotUI = require(ReplicatedStorage.BrainrotUI)

local Spawner = {}

local ZONES = {
	{ zone = "SpawnZones",            models = "CommonBrainRotModels",       rarity = "Common",       inner = "CommonSpawnZone" },
	{ zone = "SpawnZonesRare",        models = "RareBrainRotModels",         rarity = "Rare",         inner = "RareSpawnZone" },
	{ zone = "SpawnZonesEpic",        models = "EpicBrainRotModels",         rarity = "Epic",         inner = "EpicSpawnZone" },
	{ zone = "SpawnZonesLegendary",   models = "LegendaryBrainRotModels",    rarity = "Legendary",    inner = "LegendarySpawnZone" },
	{ zone = "SpawnZonesMythic",      models = "MythicBrainRotModels",       rarity = "Mythic",       inner = "MythicSpawnZone" },
	{ zone = "SpawnZonesSecret",      models = "SecretBrainRotModels",       rarity = "Secret",       inner = "SecretSpawnZone" },
	-- { zone = "SpawnZonesDivine",   models = "DivineBrainRotModels",       rarity = "Divine",       inner = "DivineSpawnZone" },
}

print("[Spawner] Module loaded, ZONES count:", #ZONES)

local brainrotsByRarity = {}
for _, entry in ipairs(Brainrots) do
	if not brainrotsByRarity[entry.rarity] then
		brainrotsByRarity[entry.rarity] = {}
	end
	table.insert(brainrotsByRarity[entry.rarity], entry)
end

print("[Spawner] Rarity pools built:")
for rarity, pool in brainrotsByRarity do
	print("  ", rarity, "->", #pool, "entries")
end

local zoneStates = {}

-- Grab callback — registered by Pickup via Spawner.onGrab()
-- Eliminates DescendantAdded connection leak (no longer watching Workspace)
local onGrabCallback = nil

function Spawner.onGrab(cb)
	onGrabCallback = cb
end

local function initZones()
	print("[Spawner] initZones() called")

	for i, zoneConfig in ZONES do
		print("[Spawner] Processing zone", i, ":", zoneConfig.zone)

		local folder = game.Workspace:FindFirstChild(zoneConfig.zone)
		if not folder then
			warn("[Spawner] FAIL: zone not found in Workspace:", zoneConfig.zone)
			continue
		end
		print("[Spawner]   Found folder:", folder:GetFullName())

		local spCount = 0
		for _, child in folder:GetChildren() do
			if child.Name:sub(1, 2) == "SP" then spCount += 1 end
		end
		print("[Spawner]   SP points found:", spCount)
		if spCount == 0 then
			print("[Spawner]   Children of", folder.Name, ":")
			for _, child in folder:GetChildren() do
				print("    ", child.Name, "(" .. child.ClassName .. ")")
			end
		end

		local models = ServerStorage:FindFirstChild(zoneConfig.models)
		if not models then
			warn("[Spawner] FAIL: model folder not found in ServerStorage:", zoneConfig.models)
			continue
		end
		print("[Spawner]   Found models folder:", models:GetFullName(), "with", #models:GetChildren(), "models")
		for _, model in models:GetChildren() do
			print("    ", model.Name)
		end

		local pool = brainrotsByRarity[zoneConfig.rarity]
		if not pool or #pool == 0 then
			warn("[Spawner] FAIL: no Brainrots.luau entries for rarity:", zoneConfig.rarity)
			continue
		end
		print("[Spawner]   Pool has", #pool, "entries for rarity:", zoneConfig.rarity)

		local innerModel = folder:FindFirstChild(zoneConfig.inner)
		if not innerModel then
			warn("[Spawner] FAIL: inner zone not found:", zoneConfig.inner, "in", folder.Name)
			continue
		end

		table.insert(zoneStates, {
			folder = folder,
			innerZone = innerModel,
			modelsFolder = models,
			brainrotPool = pool,
			occupiedPoints = {},
			rarity = zoneConfig.rarity,
		})
		print("[Spawner]   Zone registered OK")
	end

	print("[Spawner] initZones() done. Total active zones:", #zoneStates)
end

local function pickBrainrot(pool)
	local totalWeight = 0
	for _, brainrot in pool do
		totalWeight += brainrot.spawnWeight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, brainrot in pool do
		cumulative += brainrot.spawnWeight
		if roll <= cumulative then
			return brainrot
		end
	end

	return pool[1]
end

local function getOpenPoint(state)
	local points = {}
	for _, child in state.innerZone:GetChildren() do
		if child.Name:sub(1, 2) == "SP" and not state.occupiedPoints[child] then
			table.insert(points, child)
		end
	end

	if #points == 0 then return nil end
	return points[math.random(#points)]
end

local function countSpawned(state)
	local count = 0
	for _ in state.occupiedPoints do
		count += 1
	end
	return count
end

function Spawner.startDespawnTimer(clone)
	local remaining = clone:GetAttribute("DespawnRemaining")
	if not remaining then return end

	clone:SetAttribute("DespawnPaused", false)
	local startTime = tick()

	task.spawn(function()
		while true do
			task.wait(1)
			if not clone.Parent then return end
			if clone:GetAttribute("DespawnPaused") then
				local elapsed = tick() - startTime
				clone:SetAttribute("DespawnRemaining", math.max(0, remaining - elapsed))
				return
			end

			local elapsed = tick() - startTime
			clone:SetAttribute("DespawnRemaining", math.max(0, remaining - elapsed))

			if elapsed >= remaining then
				Spawner.clearPoint(clone)
				clone:Destroy()
				print("[Spawner]", clone:GetAttribute("Name"), "despawned")
				return
			end
		end
	end)
end

function Spawner.spawnOne(state)
	local count = countSpawned(state)
	if count >= Config.MaxSpawns then
		print("[Spawner] " .. state.rarity .. " at max spawns (" .. count .. "/" .. Config.MaxSpawns .. "), skipping")
		return
	end

	local point = getOpenPoint(state)
	if not point then
		print("[Spawner] " .. state.rarity .. " no open SP points, skipping")
		return
	end

	local brainrotData = pickBrainrot(state.brainrotPool)
	print("[Spawner] " .. state.rarity .. " picked:", brainrotData.name)

	local template = state.modelsFolder:FindFirstChild(brainrotData.name)
	if not template then
		warn("[Spawner] FAIL: no model for '" .. brainrotData.name .. "' in " .. state.modelsFolder.Name)
		return
	end

	if not template.PrimaryPart then
		warn("[Spawner] FAIL: model '" .. brainrotData.name .. "' has no PrimaryPart set")
		return
	end

	local clone = template:Clone()
	clone:PivotTo(CFrame.new(point.Position + Vector3.new(0, -2, 0)))
	clone:SetAttribute("Rarity", brainrotData.rarity)
	clone:SetAttribute("IncomePerSec", brainrotData.incomePerSec)
	clone:SetAttribute("Name", brainrotData.name)

	local despawnTime = math.random(Config.DespawnTimeMin, Config.DespawnTimeMax)
	clone:SetAttribute("DespawnRemaining", despawnTime)
	clone:SetAttribute("DespawnPaused", false)
	clone.Parent = game.Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = brainrotData.name
	prompt.HoldDuration = Config.PickupHoldDuration
	prompt.MaxActivationDistance = Config.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = clone.PrimaryPart

	-- Connect grab directly here — no DescendantAdded needed
	prompt.Triggered:Connect(function(player)
		if not onGrabCallback then
			warn("[Spawner] Grab triggered but no onGrab callback registered")
			return
		end
		onGrabCallback(player, clone)
	end)

	state.occupiedPoints[point] = clone
	print("[Spawner] Spawned", brainrotData.name, "at", point.Name, "(" .. state.rarity .. ")")

	Spawner.startDespawnTimer(clone)
	BrainrotUI.createWorldBillboard(clone, brainrotData)

	return clone
end

function Spawner.clearPoint(brainrotModel)
	for _, state in zoneStates do
		for point, model in state.occupiedPoints do
			if model == brainrotModel then
				state.occupiedPoints[point] = nil
				return
			end
		end
	end
end

function Spawner.start()
	print("[Spawner] start() called")
	initZones()
	if #zoneStates == 0 then
		warn("[Spawner] No zones initialized! Nothing will spawn.")
		return
	end
	for _, state in zoneStates do
		print("[Spawner] Starting spawn loop for:", state.rarity)
		task.spawn(function()
			while true do
				Spawner.spawnOne(state)
				task.wait(Config.SpawnInterval)
			end
		end)
	end
end

return Spawner