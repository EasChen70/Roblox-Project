local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local Spawner = require(game.ServerScriptService.Spawner)
local BrainrotUI = require(game.ReplicatedStorage.BrainrotUI)

local Pickup = {}

local carrying = {}          -- player → Model (world visual while grabbed)
local inventory = {}         -- player → Tool[]
local equipped = {}          -- player → Tool (currently equipped, tracked server-side)
local carryTracks = {}       -- player → AnimationTrack
local inventorySnapshot = {} -- respawn restore

local onStashCallback = nil
local onEquipCallback = nil

local modelFolders = {
	Common    = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare      = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic      = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic    = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret    = ServerStorage:WaitForChild("SecretBrainRotModels"),
	Divine    = ServerStorage:WaitForChild("DivineBrainRotModels"),
}

------------------------------------------------
-- Animation
------------------------------------------------

local function startCarryAnim(player)
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = Config.CarryAnimationId

	local track = animator:LoadAnimation(anim)
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

------------------------------------------------
-- API
------------------------------------------------

function Pickup.onStash(cb)
	onStashCallback = cb
end

function Pickup.onEquipChanged(cb)
	onEquipCallback = cb
end

function Pickup.isCarrying(player)
	return carrying[player] ~= nil
end

function Pickup.getInventory(player)
	return inventory[player] or {}
end

function Pickup.getInventoryTool(player)
	return equipped[player]
end

function Pickup.isItemEquipped(player)
	return equipped[player] ~= nil
end

function Pickup.removeFromInventory(player, tool)
	local items = inventory[player]
	if not items then return end

	for i, t in ipairs(items) do
		if t == tool then
			table.remove(items, i)
			return
		end
	end
end

------------------------------------------------
-- Tool creation
------------------------------------------------

local function createBrainrotTool(player, data)
	local level = data.level or 1
	local baseIncome = data.incomePerSec  -- Stored as "base" because tools are level-aware now

	local tool = Instance.new("Tool")
	tool.Name = data.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	tool:SetAttribute("Rarity", data.rarity)
	tool:SetAttribute("IncomePerSec", baseIncome)  -- Base income; actual display uses level
	tool:SetAttribute("Level", level)
	tool:SetAttribute("BrainrotTool", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Anchored = false
	handle.Parent = tool

	print("[Pickup] Created tool:", data.name, "L" .. level, "RequiresHandle:", tool.RequiresHandle, "Handle exists:", tool:FindFirstChild("Handle") ~= nil)

	local folder = modelFolders[data.rarity]
	local template = folder and folder:FindFirstChild(data.name)

	if not template then
		warn("Missing model:", data.name, data.rarity)
		return
	end

	tool.Equipped:Connect(function()
		equipped[player] = tool

		local character = player.Character
		if not character then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local visual = template:Clone()

		visual:SetAttribute("Name", data.name)
		visual:SetAttribute("Rarity", data.rarity)
		visual:SetAttribute("Level", level)
		visual:SetAttribute("BaseIncome", baseIncome)

		if not visual.PrimaryPart then
			visual.PrimaryPart = visual:FindFirstChildWhichIsA("BasePart")
		end
		if not visual.PrimaryPart then
			warn("No PrimaryPart:", data.name)
			return
		end

		-- Anchor + flatten physics BEFORE positioning/parenting
		for _, p in ipairs(visual:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.Massless = true
			end
		end

		visual:PivotTo(
			rootPart.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation
		)

		visual.Parent = character

		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") and part ~= visual.PrimaryPart then
				local w = Instance.new("WeldConstraint")
				w.Part0 = visual.PrimaryPart
				w.Part1 = part
				w.Parent = part
			end
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = visual.PrimaryPart
		weld.Parent = visual.PrimaryPart

		for _, p in visual:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
			end
		end

		print("[Pickup] equip weld set for", data.name)

		-- Billboard for carried visual: show level if > 1, otherwise plain
		local currentIncome = Brainrots.getIncomeAtLevel(baseIncome, data.rarity, level)
		BrainrotUI.createBillboard(visual, {
			name = data.name,
			rarity = data.rarity,
			incomePerSec = currentIncome,
			level = level > 1 and level or nil,  -- only show level if non-default
			maxLevel = Brainrots.MaxLevel,
		})

		carrying[player] = visual
		carryTracks[player] = startCarryAnim(player)

		if onEquipCallback then
			onEquipCallback(player, true)
		end

		print("[Pickup] equipped", data.name, "L" .. level, "for", player.Name)
	end)

	tool.Unequipped:Connect(function()
		equipped[player] = nil

		local model = carrying[player]
		if model then model:Destroy() end

		carrying[player] = nil

		stopCarryAnim(carryTracks[player])
		carryTracks[player] = nil

		if onEquipCallback then
			onEquipCallback(player, false)
		end

		print("[Pickup] unequipped for", player.Name)
	end)

	tool.Parent = player.Backpack

	inventory[player] = inventory[player] or {}
	table.insert(inventory[player], tool)
end

------------------------------------------------
-- Give item
------------------------------------------------

function Pickup.giveItem(player, name, rarity, incomePerSec, level)
	local items = inventory[player]
	if items and #items >= Config.MaxInventory then
		return false
	end

	local folder = modelFolders[rarity]
	if not folder or not folder:FindFirstChild(name) then
		warn("Missing brainrot:", name, rarity)
		return false
	end

	createBrainrotTool(player, {
		name = name,
		rarity = rarity,
		incomePerSec = incomePerSec,
		level = level or 1,
	})

	return true
end

------------------------------------------------
-- World grab (state 1: model welded directly to HRP)
------------------------------------------------

function Pickup.grab(player, model)
	if carrying[player] then
		print("[Pickup] grab blocked —", player.Name, "already carrying something")
		return
	end
	Remotes.GrabStateChanged:FireClient(player, true)
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local prompt = model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end

	local name = model:GetAttribute("Name")
	local rarity = model:GetAttribute("Rarity")
	local incomePerSec = model:GetAttribute("IncomePerSec")

	local partCount = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.Massless = true
			partCount += 1
		end
	end

	print("[Pickup] Model part count:", partCount)

	model:PivotTo(root.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation)
	model.Parent = character

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local w = Instance.new("WeldConstraint")
			w.Part0 = model.PrimaryPart
			w.Part1 = part
			w.Parent = part
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end

	print("[Pickup] grab weld set, all parts unanchored —", model:GetAttribute("Name"), "parts:", partCount)

	model:SetAttribute("DespawnPaused", true)
	Spawner.clearPoint(model)

	carrying[player] = model
	carryTracks[player] = startCarryAnim(player)

	print("[Pickup]", player.Name, "grabbed", name, "(", rarity, ")")
end

------------------------------------------------
-- Drop / stash
------------------------------------------------

function Pickup.stash(player)
	local model = carrying[player]
	if not model then return end

	stopCarryAnim(carryTracks[player])
	carryTracks[player] = nil
	Remotes.GrabStateChanged:FireClient(player, false)
	-- World grabs always stash at level 1
	local data = {
		name = model:GetAttribute("Name"),
		rarity = model:GetAttribute("Rarity"),
		incomePerSec = model:GetAttribute("IncomePerSec"),
		level = 1,
	}

	model:Destroy()
	carrying[player] = nil

	createBrainrotTool(player, data)

	local items = inventory[player]
	print("[Pickup] Inventory after stash for", player.Name, ":", items and #items or "NIL")
	if items then
		for i, tool in items do
			print("[Pickup]   Tool", i, ":", tool.Name, "L" .. (tool:GetAttribute("Level") or 1))
		end
	end

	print("[Pickup]", player.Name, "stashed", data.name, "to backpack")

	if onStashCallback then
		onStashCallback(player)
	end
end

function Pickup.drop(player)
	local model = carrying[player]
	if not model then return end

	stopCarryAnim(carryTracks[player])
	carryTracks[player] = nil
	carrying[player] = nil
	Remotes.GrabStateChanged:FireClient(player, false)

	-- Destroy all welds on the model
	for _, p in model:GetDescendants() do
		if p:IsA("WeldConstraint") then
			p:Destroy()
		end
	end

	-- Clean up HRP welds
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		for _, w in root:GetChildren() do
			if w:IsA("WeldConstraint") then
				w:Destroy()
			end
		end
	end

	if root then
		local dropPos = root.Position + Vector3.new(0, 0, 3)

		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {model, player.Character}
		params.FilterType = Enum.RaycastFilterType.Exclude

		local hit = workspace:Raycast(
			Vector3.new(dropPos.X, root.Position.Y + 50, dropPos.Z),
			Vector3.new(0, -100, 0),
			params
		)

		local rawHitY = hit and hit.Position.Y
		local groundY

		if rawHitY and rawHitY < root.Position.Y then
			groundY = rawHitY
		else
			groundY = root.Position.Y - 3
		end

		print("[Pickup] DROP DEBUG",
			"| rootY:", root.Position.Y,
			"| hitY:", rawHitY or "MISS",
			"| hitInstance:", hit and hit.Instance.Name or "nil",
			"| groundY (final):", groundY
		)

		model.Parent = workspace
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
			end
		end
		model:PivotTo(CFrame.new(dropPos.X, groundY, dropPos.Z))
	else
		model.Parent = workspace
		model:PivotTo(CFrame.new(Vector3.new(0, 10, 0)))
	end

	-- Recreate grab prompt regardless of which path was taken
	if model.PrimaryPart then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.ActionText = "Grab"
		newPrompt.ObjectText = model:GetAttribute("Name") or ""
		newPrompt.HoldDuration = Config.PickupHoldDuration
		newPrompt.MaxActivationDistance = Config.PickupRange
		newPrompt.RequiresLineOfSight = false
		newPrompt.Parent = model.PrimaryPart

		newPrompt.Triggered:Connect(function(triggerPlayer)
			if carrying[triggerPlayer] then return end
			Pickup.grab(triggerPlayer, model)
		end)
	end

	Spawner.startDespawnTimer(model)
	print("[Pickup]", player.Name, "dropped", model:GetAttribute("Name"))
end

------------------------------------------------
-- Respawn handling
------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		local saved = inventorySnapshot[player]
		if saved then
			inventory[player] = {}

			for _, data in ipairs(saved) do
				createBrainrotTool(player, data)
			end

			inventorySnapshot[player] = nil
		end

		humanoid.Died:Connect(function()
			Pickup.drop(player)

			local items = inventory[player]
			if items then
				inventorySnapshot[player] = {}

				for _, tool in ipairs(items) do
					table.insert(inventorySnapshot[player], {
						name = tool.Name,
						rarity = tool:GetAttribute("Rarity"),
						incomePerSec = tool:GetAttribute("IncomePerSec"),
						level = tool:GetAttribute("Level") or 1,
					})
				end
			end
		end)
	end)
end)

------------------------------------------------
-- Boundary stash trigger
------------------------------------------------

local stashDebounce = {}

local spawnZoneFolders = {
    game.Workspace:WaitForChild("SpawnZones"),
    game.Workspace:WaitForChild("SpawnZonesRare"),
    game.Workspace:WaitForChild("SpawnZonesEpic"),
    game.Workspace:WaitForChild("SpawnZonesLegendary"),
    game.Workspace:WaitForChild("SpawnZonesMythic"),
    game.Workspace:WaitForChild("SpawnZonesSecret"),
    game.Workspace:WaitForChild("SpawnZonesDivine"),
}

for _, folder in spawnZoneFolders do
    local boundary = folder:WaitForChild("Boundary", 10)
    if not boundary then
        warn("[Pickup] No Boundary found in", folder.Name)
        continue
    end

    boundary.TouchEnded:Connect(function(hit)
        local character = hit.Parent
        if not character then return end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if not carrying[player] then return end
        if equipped[player] then return end

        if stashDebounce[player] then return end
        stashDebounce[player] = true

        Pickup.stash(player)

        task.delay(1, function()
            stashDebounce[player] = nil
        end)
    end)
end

Remotes.DropBrainrot.OnServerEvent:Connect(function(player)
	if not carrying[player] then return end
	Pickup.drop(player)
end)

return Pickup