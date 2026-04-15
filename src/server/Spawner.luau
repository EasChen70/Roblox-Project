local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local BrainrotUI = require(ReplicatedStorage.BrainrotUI)
local Spawner = {}

local modelsFolder = game:GetService("ServerStorage"):WaitForChild("CommonBrainRotModels")
local spawnZone = game.Workspace.SpawnZones.CommonSpawnZone
local occupiedPoints = {}

local function pickBrainrot()
	local totalWeight = 0
	for _, brainrot in Brainrots do
		totalWeight += brainrot.spawnWeight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, brainrot in Brainrots do
		cumulative += brainrot.spawnWeight
		if roll <= cumulative then
			return brainrot
		end
	end

	return Brainrots[1]
end

local function getOpenPoint()
	local points = {}
	for _, child in spawnZone:GetChildren() do
		if child.Name:sub(1, 2) == "SP" and not occupiedPoints[child] then
			table.insert(points, child)
		end
	end

	if #points == 0 then return nil end
	return points[math.random(#points)]
end

local function countSpawned()
	local count = 0
	for _ in occupiedPoints do
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
				print(clone:GetAttribute("Name"), "despawned")
				return
			end
		end
	end)
end

function Spawner.spawnOne()
	if countSpawned() >= Config.MaxSpawns then return end

	local point = getOpenPoint()
	if not point then return end

	local brainrotData = pickBrainrot()
	local template = modelsFolder:FindFirstChild(brainrotData.name)
	if not template then
		warn("No model found for:", brainrotData.name)
		return
	end

	local clone = template:Clone()
	clone:PivotTo(CFrame.new(point.Position + Vector3.new(0, -2, 0)))
	clone:SetAttribute("Rarity", brainrotData.rarity)
	clone:SetAttribute("IncomePerSec", brainrotData.incomePerSec)
	clone:SetAttribute("Name", brainrotData.name)

	local despawnTime = math.random(30,60) --Config.DespawnTimes[brainrotData.rarity]
	if despawnTime then
		clone:SetAttribute("DespawnRemaining", despawnTime)
	end

	clone:SetAttribute("DespawnPaused", false)
	clone.Parent = game.Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = brainrotData.name
	prompt.HoldDuration = Config.PickupHoldDuration
	prompt.MaxActivationDistance = Config.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = clone.PrimaryPart

	occupiedPoints[point] = clone
	print("Spawned", brainrotData.name, "at", point.Name)

	Spawner.startDespawnTimer(clone)
	BrainrotUI.createWorldBillboard(clone, brainrotData)

	return clone
end

function Spawner.clearPoint(brainrotModel)
	for point, model in occupiedPoints do
		if model == brainrotModel then
			occupiedPoints[point] = nil
			return
		end
	end
end

function Spawner.start()
	task.spawn(function()
		while true do
			Spawner.spawnOne()
			task.wait(Config.SpawnInterval)
		end
	end)
end

return Spawner