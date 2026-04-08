-- server/Spawner.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)

local Spawner = {}

local modelsFolder = game:GetService("ServerStorage"):WaitForChild("BrainRotModels")
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
	clone:SetPrimaryPartCFrame(CFrame.new(point.Position + Vector3.new(0, 2, 0)))
	clone:SetAttribute("Rarity", brainrotData.rarity)
	clone:SetAttribute("IncomePerSec", brainrotData.incomePerSec)
	clone:SetAttribute("Name", brainrotData.name)
	clone.Parent = game.Workspace

	-- ProximityPrompt for pickup
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = brainrotData.name
	prompt.HoldDuration = Config.PickupHoldDuration
	prompt.MaxActivationDistance = Config.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = clone.PrimaryPart

	occupiedPoints[point] = clone
	print("Spawned", brainrotData.name, "at", point.Name)

	local despawnTime = Config.DespawnTimes[brainrotData.rarity]
	if despawnTime then
		task.delay(despawnTime, function()
			if clone.Parent then
				clone:Destroy()
				Spawner.clearPoint(clone)
				print(brainrotData.name, "despawned from", point.Name)
			end
		end)
	end

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