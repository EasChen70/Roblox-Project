local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
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
	local tool = Instance.new("Tool")
	tool.Name = data.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	tool:SetAttribute("Rarity", data.rarity)
	tool:SetAttribute("IncomePerSec", data.incomePerSec)
	tool:SetAttribute("BrainrotTool", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Anchored = false
	handle.Parent = tool

	-- ADD THIS DEBUG
	print("[Pickup] Created tool:", data.name, "RequiresHandle:", tool.RequiresHandle, "Handle exists:", tool:FindFirstChild("Handle") ~= nil)

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
		visual:SetAttribute("IncomePerSec", data.incomePerSec)

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

		-- Position BEFORE parenting (reduces replication spike)
		visual:PivotTo(
			rootPart.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation
		)

		visual.Parent = character

		-- Build internal welds between all non-PrimaryPart parts and PrimaryPart
		for _, part in visual:GetDescendants() do
			if part:IsA("BasePart") and part ~= visual.PrimaryPart then
				local w = Instance.new("WeldConstraint")
				w.Part0 = visual.PrimaryPart
				w.Part1 = part
				w.Parent = part
			end
		end

		-- Weld PrimaryPart to HRP
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = visual.PrimaryPart
		weld.Parent = visual.PrimaryPart

		-- Unanchor all parts — internal welds + HRP weld keep everything together
		for _, p in visual:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
			end
		end

		print("[Pickup] equip weld set for", data.name)

		BrainrotUI.createBillboard(visual, {
			name = data.name,
			rarity = data.rarity,
			incomePerSec = data.incomePerSec,
		})

		carrying[player] = visual
		carryTracks[player] = startCarryAnim(player)

		if onEquipCallback then
			onEquipCallback(player, true)
		end

		print("[Pickup] equipped", data.name, "for", player.Name)
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

function Pickup.giveItem(player, name, rarity, incomePerSec)
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
	})

	return true
end

------------------------------------------------
-- World grab (state 1: model welded directly to HRP)
-- Called via Spawner.onGrab callback — no DescendantAdded needed
--
-- Ground teleport fix: anchor + Massless all parts FIRST, then
-- PivotTo carry position, then reparent, then build internal welds,
-- then weld to HRP, then unanchor all parts. Order matters.
------------------------------------------------

function Pickup.grab(player, model)
	if carrying[player] then
		print("[Pickup] grab blocked —", player.Name, "already carrying something")
		return
	end

	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Disable prompt immediately after grab check passes
	local prompt = model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	local name = model:GetAttribute("Name")
	local rarity = model:GetAttribute("Rarity")
	local incomePerSec = model:GetAttribute("IncomePerSec")

	-- Step 1: kill physics on all parts before anything else
	-- This is what prevents the ground teleport jolt
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

	-- Step 2: move to carry position while still in Workspace (clean, no physics)
	model:PivotTo(root.CFrame * CFrame.new(Config.CarryOffset) * Config.CarryRotation)

	-- Step 3: reparent to character
	model.Parent = character

	-- Step 4: build internal welds between all non-PrimaryPart parts and PrimaryPart
	-- (spawned models from Toolbox often lack these — without them, unanchored parts fall)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local w = Instance.new("WeldConstraint")
			w.Part0 = model.PrimaryPart
			w.Part1 = part
			w.Parent = part
		end
	end

	-- Step 5: weld PrimaryPart to HRP
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart

	-- Step 6: unanchor all parts
	-- Internal welds hold assembly together; HRP weld drives it
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end

	print("[Pickup] grab weld set, all parts unanchored —", model:GetAttribute("Name"), "parts:", partCount)

	-- Pause despawn timer + free the spawn point
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

	local data = {
		name = model:GetAttribute("Name"),
		rarity = model:GetAttribute("Rarity"),
		incomePerSec = model:GetAttribute("IncomePerSec"),
	}

	model:Destroy()
	carrying[player] = nil

	createBrainrotTool(player, data)

	-- ADD THIS DEBUG BLOCK
	local items = inventory[player]
	print("[Pickup] Inventory after stash for", player.Name, ":", items and #items or "NIL")
	if items then
		for i, tool in items do
			print("[Pickup]   Tool", i, ":", tool.Name)
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

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")

	model.Parent = workspace

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end

	model:PivotTo(CFrame.new(root and root.Position or Vector3.new(0, 10, 0)))

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
					})
				end
			end
		end)
	end)
end)


------------------------------------------------
-- Boundary stash trigger
------------------------------------------------

local boundary = game.Workspace.SpawnZones:WaitForChild("Boundary")
local stashDebounce = {}

boundary.TouchEnded:Connect(function(hit)
	local character = hit.Parent
	if not character then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if not carrying[player] then return end
	if equipped[player] then return end  -- ← ADD THIS LINE
	
	if stashDebounce[player] then return end
	stashDebounce[player] = true

	Pickup.stash(player)
	
	task.delay(1, function()
		stashDebounce[player] = nil
	end)
end)

return Pickup