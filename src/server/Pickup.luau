local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Spawner = require(game.ServerScriptService.Spawner)
local BrainrotUI = require(game.ReplicatedStorage.BrainrotUI)

local Pickup = {}

local carrying = {}
local inventory = {} -- player → array of Tools
local carryTracks = {} -- player → AnimationTrack (state 1: grabbed from world)
local onStashCallback = nil
local onEquipCallback = nil

local ServerStorage = game:GetService("ServerStorage")

local modelFolders = {
	Common    = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare      = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic      = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic    = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret    = ServerStorage:WaitForChild("SecretBrainRotModels"),
}

local function startCarryAnim(player)
	local character = player.Character
	if not character then return nil end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local carryAnim = Instance.new("Animation")
	carryAnim.AnimationId = Config.CarryAnimationId
	local track = animator:LoadAnimation(carryAnim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play()
	return track
end

local function stopCarryAnim(track)
	if track then
		pcall(function()
			track:Stop()
		end)
	end
end

function Pickup.onStash(callback)
	onStashCallback = callback
end

function Pickup.onEquipChanged(callback)
	onEquipCallback = callback
end

function Pickup.isCarrying(player)
	return carrying[player] ~= nil
end

function Pickup.getInventory(player)
	return inventory[player] or {}
end

function Pickup.getInventoryTool(player)
	local items = inventory[player]
	if not items then return nil end
	local character = player.Character
	for _, tool in items do
		if character and tool.Parent == character then
			return tool
		end
	end
	return nil
end

function Pickup.isItemEquipped(player)
	return Pickup.getInventoryTool(player) ~= nil
end

function Pickup.removeFromInventory(player, tool)
	local items = inventory[player]
	if not items then return end
	for i, t in items do
		if t == tool then
			table.remove(items, i)
			return
		end
	end
end

local function createBrainrotTool(player, data)
	local tool = Instance.new("Tool")
	tool.Name = data.name
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool:SetAttribute("Rarity", data.rarity)
	tool:SetAttribute("IncomePerSec", data.incomePerSec)
	tool:SetAttribute("BrainrotTool", true)

	local folder = modelFolders[data.rarity]
	local template = folder and folder:FindFirstChild(data.name)
	local visual = nil
	local carryTrack = nil -- state 2: Tool equipped from backpack

	tool.Equipped:Connect(function()
		local character = player.Character
		if not character or not template then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		visual = template:Clone()
		visual:SetAttribute("Name", data.name)
		visual:SetAttribute("Rarity", data.rarity)
		visual:SetAttribute("IncomePerSec", data.incomePerSec)

		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = false
				part.Massless = true
			end
		end

		-- 1. Parent first
		visual.Parent = character

		-- 2. Position with PivotTo
		visual:PivotTo(rootPart.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation)

		-- 3. Weld all parts to PrimaryPart
		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") and part ~= visual.PrimaryPart then
				local w = Instance.new("WeldConstraint")
				w.Part0 = visual.PrimaryPart
				w.Part1 = part
				w.Parent = part
			end
		end

		-- 4. Weld to HumanoidRootPart AFTER positioning
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = visual.PrimaryPart
		weld.Parent = visual.PrimaryPart

		BrainrotUI.createBillboard(visual, {
			name = data.name,
			rarity = data.rarity,
			incomePerSec = data.incomePerSec,
		})

		-- Start carry animation for state 2
		carryTrack = startCarryAnim(player)

		if onEquipCallback then
			onEquipCallback(player)
		end
	end)

	tool.Unequipped:Connect(function()
		if visual and visual.Parent then
			visual:Destroy()
			visual = nil
		end

		-- Stop carry animation for state 2
		stopCarryAnim(carryTrack)
		carryTrack = nil

		if onEquipCallback then
			onEquipCallback(player)
		end
	end)

	tool.Parent = player.Backpack

	if not inventory[player] then
		inventory[player] = {}
	end
	table.insert(inventory[player], tool)
end

function Pickup.giveItem(player, name, rarity, incomePerSec)
	if carrying[player] then return false end
	local items = inventory[player]
	if items and #items >= Config.MaxInventory then return false end

	-- Validate template exists before creating the tool
	local folder = modelFolders[rarity]
	if not folder or not folder:FindFirstChild(name) then
		warn("No brainrot model found for:", name, "rarity:", rarity)
		return false
	end

	createBrainrotTool(player, {
		name = name,
		rarity = rarity,
		incomePerSec = incomePerSec,
	})
	return true
end

function Pickup.grab(player, brainrotModel)
	if carrying[player] then
		warn(player.Name, "already carrying a brainrot")
		return
	end

	local items = inventory[player]
	if items and #items >= Config.MaxInventory then
		warn(player.Name, "inventory full")
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

	-- 1. Parent first
	brainrotModel.Parent = character

	-- 2. Position with PivotTo
	brainrotModel:PivotTo(rootPart.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation)

	-- 3. Weld all parts to PrimaryPart
	for _, part in brainrotModel:GetDescendants() do
		if part:IsA("BasePart") and part ~= brainrotModel.PrimaryPart then
			local w = Instance.new("WeldConstraint")
			w.Part0 = brainrotModel.PrimaryPart
			w.Part1 = part
			w.Parent = part
		end
	end

	-- 4. Weld to HumanoidRootPart AFTER positioning
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = brainrotModel.PrimaryPart
	weld.Parent = brainrotModel.PrimaryPart

	carrying[player] = brainrotModel
	print(player.Name, "grabbed", brainrotModel:GetAttribute("Name"))

	-- Start carry animation for state 1
	carryTracks[player] = startCarryAnim(player)

	local oldBillboard = brainrotModel.PrimaryPart:FindFirstChild("BrainrotBillboard")
	if oldBillboard then
		oldBillboard:Destroy()
	end

	BrainrotUI.createBillboard(brainrotModel, {
		name = brainrotModel:GetAttribute("Name"),
		rarity = brainrotModel:GetAttribute("Rarity"),
		incomePerSec = brainrotModel:GetAttribute("IncomePerSec"),
	})
end

function Pickup.stash(player)
	local brainrotModel = carrying[player]
	if not brainrotModel then return end

	-- Stop carry animation for state 1
	stopCarryAnim(carryTracks[player])
	carryTracks[player] = nil

	local data = {
		name = brainrotModel:GetAttribute("Name"),
		rarity = brainrotModel:GetAttribute("Rarity"),
		incomePerSec = brainrotModel:GetAttribute("IncomePerSec"),
	}

	brainrotModel:Destroy()
	carrying[player] = nil

	createBrainrotTool(player, data)

	if onStashCallback then
		onStashCallback(player)
	end

	print(player.Name, "stashed", data.name, "to backpack")
end

function Pickup.drop(player)
	local brainrotModel = carrying[player]
	if not brainrotModel then return end

	-- Stop carry animation for state 1
	stopCarryAnim(carryTracks[player])
	carryTracks[player] = nil

	carrying[player] = nil

	-- Destroy only welds connecting to the character
	local character = player.Character
	for _, descendant in brainrotModel:GetDescendants() do
		if descendant:IsA("WeldConstraint") then
			if character and descendant.Part0 and descendant.Part0:IsDescendantOf(character) then
				descendant:Destroy()
			elseif character and descendant.Part1 and descendant.Part1:IsDescendantOf(character) then
				descendant:Destroy()
			end
		end
	end

	-- Reparent to Workspace immediately
	brainrotModel.Parent = game.Workspace

	-- Anchor all parts
	for _, part in brainrotModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	-- Raycast to find ground
	local dropPosition

	if character and character:FindFirstChild("HumanoidRootPart") then
		local origin = character.HumanoidRootPart.Position
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {character, brainrotModel}
		params.FilterType = Enum.RaycastFilterType.Exclude
		local rayResult = game.Workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
		if rayResult then
			dropPosition = rayResult.Position + Vector3.new(0, 1, 0)
		else
			dropPosition = Vector3.new(origin.X, 0, origin.Z)
		end
	else
		dropPosition = Vector3.new(0, 10, 0)
	end

	brainrotModel:PivotTo(CFrame.new(dropPosition))

	-- Billboard
	local oldBillboard = brainrotModel.PrimaryPart:FindFirstChild("BrainrotBillboard")
	if oldBillboard then
		oldBillboard:Destroy()
	end

	BrainrotUI.createWorldBillboard(brainrotModel, {
		name = brainrotModel:GetAttribute("Name"),
		rarity = brainrotModel:GetAttribute("Rarity"),
		incomePerSec = brainrotModel:GetAttribute("IncomePerSec"),
	})

	Spawner.startDespawnTimer(brainrotModel)

	-- Delay prompt so other player can't grab during physics settle
	task.delay(0.5, function()
		if not brainrotModel.Parent then return end
		-- Only re-enable prompt if still in Workspace (not re-grabbed by someone else)
		if brainrotModel.Parent ~= game.Workspace then return end

		local prompt = brainrotModel.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Grab"
			prompt.ObjectText = brainrotModel:GetAttribute("Name")
			prompt.HoldDuration = Config.PickupHoldDuration
			prompt.MaxActivationDistance = Config.PickupRange
			prompt.RequiresLineOfSight = false
			prompt.Parent = brainrotModel.PrimaryPart
		else
			prompt.Enabled = true
		end
	end)

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

		-- Only grab wild spawned brainrots: has a Name, not Placed, and is parented directly in Workspace (not in a slot or character)
		if not model then return end
		if not model:GetAttribute("Name") then return end
		if model:GetAttribute("Placed") then return end
		if model.Parent ~= game.Workspace then return end

		Pickup.grab(player, model)
	end)
end

for _, descendant in game.Workspace:GetDescendants() do
	onDescendantAdded(descendant)
end
game.Workspace.DescendantAdded:Connect(onDescendantAdded)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		humanoid.Died:Connect(function()
			Pickup.drop(player)
		end)

		humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
			if humanoid.PlatformStand then
				Pickup.drop(player)
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local brainrotModel = carrying[player]
	if brainrotModel then
		brainrotModel:Destroy()
		carrying[player] = nil
	end

	-- Clean up carry animation track
	stopCarryAnim(carryTracks[player])
	carryTracks[player] = nil

	local items = inventory[player]
	if items then
		for _, tool in items do
			tool:Destroy()
		end
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