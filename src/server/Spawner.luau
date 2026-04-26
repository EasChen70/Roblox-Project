local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local BrainrotUI = require(ReplicatedStorage.BrainrotUI)

local Spawner = {}

local ZONES = {
    { zone = "SpawnZones",           models = "CommonBrainRotModels",       rarity = "Common",       inner = "CommonSpawnZone" },
    { zone = "SpawnZonesRare",        models = "RareBrainRotModels",         rarity = "Rare",         inner = "RareSpawnZone" },
    { zone = "SpawnZonesEpic",        models = "EpicBrainRotModels",         rarity = "Epic",         inner = "EpicSpawnZone" },
    { zone = "SpawnZonesLegendary",   models = "LegendaryBrainRotModels",    rarity = "Legendary",    inner = "LegendarySpawnZone" },
    { zone = "SpawnZonesMythic",      models = "MythicBrainRotModels",       rarity = "Mythic",       inner = "MythicSpawnZone" },
    { zone = "SpawnZonesSecret",      models = "SecretBrainRotModels",       rarity = "Secret",       inner = "SecretSpawnZone" },
    { zone = "SpawnZonesDivine",      models = "DivineBrainRotModels",       rarity = "Divine",       inner = "DivineSpawnZone" },
}

local brainrotsByRarity = {}
for _, entry in ipairs(Brainrots) do
    if not brainrotsByRarity[entry.rarity] then
        brainrotsByRarity[entry.rarity] = {}
    end
    table.insert(brainrotsByRarity[entry.rarity], entry)
end

local zoneStates = {}
local onGrabCallback = nil

local function rollMutation()
    local roll = math.random()
    if roll < Config.MutationDiamondChance then
        return "Diamond"
    elseif roll < Config.MutationDiamondChance + Config.MutationGoldChance then
        return "Gold"
    end
    return "None"
end

local function getModelFolderName(rarity, mutation)
    if mutation and mutation ~= "None" then
        return mutation .. rarity .. "BrainRotModels"
    end
    return rarity .. "BrainRotModels"
end

function Spawner.onGrab(cb)
    onGrabCallback = cb
end

local function initZones()
    for i, zoneConfig in ZONES do
        local folder = game.Workspace:FindFirstChild(zoneConfig.zone)
        if not folder then continue end

        local spCount = 0
        for _, child in folder:GetChildren() do
            if child.Name:sub(1, 2) == "SP" then 
                spCount += 1 
            end
        end

        local models = ServerStorage:FindFirstChild(zoneConfig.models)
        if not models then continue end

        local pool = brainrotsByRarity[zoneConfig.rarity]
        if not pool or #pool == 0 then continue end

        local innerModel = folder:FindFirstChild(zoneConfig.inner)
        if not innerModel then continue end

        table.insert(zoneStates, {
            folder = folder,
            innerZone = innerModel,
            modelsFolder = models,
            brainrotPool = pool,
            occupiedPoints = {},
            rarity = zoneConfig.rarity,
        })
    end
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
                local finalRemaining = math.max(0, remaining - elapsed)
                clone:SetAttribute("DespawnRemaining", finalRemaining)
                return 
            end

            local elapsed = tick() - startTime
            if elapsed >= remaining then
                Spawner.clearPoint(clone)
                clone:Destroy()
                return
            end
        end
    end)
end

function Spawner.spawnOne(state)
    local count = countSpawned(state)
    if count >= Config.MaxSpawns then return end

    local point = getOpenPoint(state)
    if not point then return end

    local brainrotData = pickBrainrot(state.brainrotPool)
    local mutation = rollMutation()
    local folderName = getModelFolderName(state.rarity, mutation)
    local modelsFolder = ServerStorage:FindFirstChild(folderName) or state.modelsFolder
    local template = modelsFolder:FindFirstChild(brainrotData.name)
    if not template or not template.PrimaryPart then return end

    local clone = template:Clone()
    clone:PivotTo(CFrame.new(point.Position + Vector3.new(0, -2, 0)))
    clone:SetAttribute("Rarity", brainrotData.rarity)
    local mutMult = Config.MutationMultipliers[mutation] or 1.0
    clone:SetAttribute("IncomePerSec", math.floor(brainrotData.incomePerSec * mutMult))
    clone:SetAttribute("Name", brainrotData.name)
    clone:SetAttribute("Mutation", mutation)
    for _, p in clone:GetDescendants() do
        if p:IsA("BasePart") then p.CanQuery = false end
    end
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

    prompt.Triggered:Connect(function(player)
        if not onGrabCallback then return end
        onGrabCallback(player, clone)
    end)

    state.occupiedPoints[point] = clone
    Spawner.startDespawnTimer(clone)
    BrainrotUI.createWorldBillboard(clone, {
        name = brainrotData.name,
        rarity = brainrotData.rarity,
        incomePerSec = clone:GetAttribute("IncomePerSec"),
        mutation = mutation,
    })

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
    initZones()
    if #zoneStates == 0 then return end
    for _, state in zoneStates do
        task.spawn(function()
            while true do
                Spawner.spawnOne(state)
                task.wait(Config.SpawnInterval)
            end
        end)
    end
end

return Spawner