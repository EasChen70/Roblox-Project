-- server/Pickup.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Spawner = require(game.ServerScriptService.Spawner)

local Pickup = {}

local carrying = {}
local inventory = {}
local onStashCallback = nil

function Pickup.onStash(callback)
	onStashCallback = callback
end

function Pickup.isCarrying(player)
	return carrying[player] ~= nil
end

function Pickup.getInventory(player)
	return inventory[player] or {}
end

function Pickup.getInventoryTool(player)
	return inventory[player]
end

function Pickup.clearInventory(player)
	inventory[player] = nil
end

function Pickup.grab(player, brainrotModel)
	if carrying[player] then
		warn(player.Name, "already carrying a brainrot")
		return
	end

	if inventory[player] then
		warn(player.Name, "already has a brainrot in inventory")
		return
	end

	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local prompt = brainrotModel.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	brainrotModel:SetAttribute("DespawnPaused", true)

	Spawner.clearPoint(brainrotModel)

	for _, part in brainrotModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = brainrotModel.PrimaryPart
	weld.Parent = brainrotModel.PrimaryPart

	brainrotModel.PrimaryPart.CFrame = rootPart.CFrame * CFrame.new(Config.CarryOffset)
	brainrotModel.Parent = character

	carrying[player] = brainrotModel
	print(player.Name, "grabbed", brainrotModel:GetAttribute("Name"))
end

function Pickup.stash(player)
	local brainrotModel = carrying[player]
	if not brainrotModel then return end

	local data = {
		name = brainrotModel:GetAttribute("Name"),
		rarity = brainrotModel:GetAttribute("Rarity"),
		incomePerSec = brainrotModel:GetAttribute("IncomePerSec"),
	}

	brainrotModel:Destroy()
	carrying[player] = nil

	local tool = Instance.new("Tool")
	tool.Name = data.name
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool:SetAttribute("Rarity", data.rarity)
	tool:SetAttribute("IncomePerSec", data.incomePerSec)
	tool:SetAttribute("BrainrotTool", true)

	local modelsFolder = game:GetService("ServerStorage"):WaitForChild("BrainRotModels")
	local template = modelsFolder:FindFirstChild(data.name)

	local visual = nil

	tool.Equipped:Connect(function()
		local character = player.Character
		if not character or not template then return end

		local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if not rightHand then return end

		visual = template:Clone()
		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = false
			end
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rightHand
		weld.Part1 = visual.PrimaryPart
		weld.Parent = visual.PrimaryPart

		visual.PrimaryPart.CFrame = rightHand.CFrame * CFrame.new(0, 0, -1)
		visual.Parent = character
	end)

	tool.Unequipped:Connect(function()
		if visual and visual.Parent then
			visual:Destroy()
			visual = nil
		end
	end)

	tool.Parent = player.Backpack
	inventory[player] = tool

	if onStashCallback then
		onStashCallback(player)
	end

	print(player.Name, "stashed", data.name, "to backpack")
end

function Pickup.drop(player)
	local brainrotModel = carrying[player]
	if not brainrotModel then return end

	local character = player.Character
	local dropPosition

	if character and character:FindFirstChild("HumanoidRootPart") then
		dropPosition = character.HumanoidRootPart.Position + Vector3.new(0, 2, 0)
	else
		dropPosition = Vector3.new(0, 10, 0)
	end

	local weld = brainrotModel.PrimaryPart:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end

	for _, part in brainrotModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	brainrotModel:SetPrimaryPartCFrame(CFrame.new(dropPosition))
	brainrotModel.Parent = game.Workspace

	local prompt = brainrotModel.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end

	Spawner.startDespawnTimer(brainrotModel)

	carrying[player] = nil
	print(player.Name, "dropped", brainrotModel:GetAttribute("Name"))
end

function Pickup.getCarried(player)
	return carrying[player]
end

local function onDescendantAdded(descendant)
	if not descendant:IsA("ProximityPrompt") then return end

	descendant.Triggered:Connect(function(player)
		local model = descendant.Parent
		while model and not model:IsA("Model") do
			model = model.Parent
		end

		if model and model:GetAttribute("Name") then
			Pickup.grab(player, model)
		end
	end)
end

for _, descendant in game.Workspace:GetDescendants() do
	onDescendantAdded(descendant)
end
game.Workspace.DescendantAdded:Connect(onDescendantAdded)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid").Died:Connect(function()
			Pickup.drop(player)
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local brainrotModel = carrying[player]
	if brainrotModel then
		brainrotModel:Destroy()
		carrying[player] = nil
	end
	inventory[player] = nil
end)

local boundary = game.Workspace.SpawnZones:WaitForChild("Boundary")

boundary.TouchEnded:Connect(function(hit)
	local character = hit.Parent
	if not character then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if not carrying[player] then return end

	Pickup.stash(player)
end)

return Pickup