--Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--Shared Modules
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local BrainrotUI = require(ReplicatedStorage.BrainrotUI)
local Util = require(ReplicatedStorage.Util)

--Server Systems
local Base = require(ServerScriptService.Base)
local Pickup = require(ServerScriptService.Pickup)
local Placement = require(ServerScriptService.Placement)

local PlayerData = {}

-----CONFIG/CONSTANTS-----
local DATA_STORE_NAME = "BrainrotCannonV1"

local CURRENT_VERSION = 1

local LOCK_EXPIRY = 60
local LOCK_REFRESH = 30

local AUTOSAVE_INTERVAL = 60
local SAVE_THROTTLE = 6

local MAX_RETRIES = 3
local RETRY_DELAYS = {1, 2, 4}

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-----RUNTIME STATE-----
local sessionData = {}
local sessionBase = {}
local lastSave = {}
local lockThreads = {}

local modelFolders = {
	Common    = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare      = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic      = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic    = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret    = ServerStorage:WaitForChild("SecretBrainRotModels"),
}

local migrations = {}

-----HELPERS-----

local function createDefault()
	return {
		version = CURRENT_VERSION,
		money = 0,
		rebirths = 0,
		cannonPower = 0,
		slots = {},
		inventory = {},
	}
end

local function getKey(player)
	return "player_" .. player.UserId
end

local function runMigrations(data)
	if not data.version then data.version = 1 end

	if data.version > CURRENT_VERSION then return nil end

	for v = data.version + 1, CURRENT_VERSION do
		if migrations[v] then
			local ok, result = pcall(migrations[v], data)
			if not ok then
				warn("[PlayerData] Migration failed:", result)
				return nil
			end
			data = result
		end
	end

	data.version = CURRENT_VERSION
	return data
end

local function retryAsync(func)
	for i = 1, MAX_RETRIES do
		local ok, result = pcall(func)
		if ok then
			return true, result
		end
		warn("[PlayerData] Attempt", i, "failed:", result)
		if i < MAX_RETRIES then
			task.wait(RETRY_DELAYS[i])
		end
	end
	return false, nil
end

local function getIncomeFromRegistry(name)
	for _, entry in Brainrots do
		if entry.name == name then
			return entry.incomePerSec
		end
	end
	return 0
end

function PlayerData.countSlots(slots)
	local count = 0
	for _ in slots do count += 1 end
	return count
end

-----READ CURRENT GAME STATE-----

local function readSlots(player)
	local slots = {}

	local base = sessionBase[player] or Base.getPlayerBase(player)
	if not base then return slots end
	local slotsFolder = base:FindFirstChild("Slots")
	if not slotsFolder then return slots end

	for i = 1, Config.MaxSlots do
		local slot = slotsFolder:FindFirstChild("Slot" .. i)
		if not slot then continue end

		for _, child in slot:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("Placed") then
				slots[i] = {
					name = child:GetAttribute("Name"),
					rarity = child:GetAttribute("Rarity"),
					accumulatedCash = slot:GetAttribute("AccumulatedCash") or 0,
				}
				break
			end
		end
	end
	return slots
end

local function readLiveState(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats then
		local money = leaderstats:FindFirstChild("Money")
		local rebirths = leaderstats:FindFirstChild("Rebirths")

		if money then data.money = money.Value end
		if rebirths then data.rebirths = rebirths.Value end
	end

	data.slots = readSlots(player)
	data.inventory = {}
	local items = Pickup.getInventory(player)
	
	print("[PlayerData] Reading inventory for save, count:", #items)  -- ADD THIS
	
	for _, tool in items do
		if tool then
			table.insert(data.inventory, {
				name = tool.Name,
				rarity = tool:GetAttribute("Rarity"),
			})
			print("[PlayerData]   - Saving:", tool.Name, tool:GetAttribute("Rarity"))  -- ADD THIS
		end
	end
	
	print("[PlayerData] Final inventory save count:", #data.inventory)  -- ADD THIS
end

-----LOAD SYSTEM-----
function PlayerData.load(player)
	local key = getKey(player)

	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		player:Kick("Data failed to load — rejoin")
		return
	end

	local base = nil
	local waitStart = tick()

	while not base and tick() - waitStart < 10 do
		base = Base.getPlayerBase(player)
		if not base then task.wait(0.1) end
	end

	if not player.Parent then return end

	local wasLocked = false
	local loadedData = nil

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function(current)
			if current and current.lockJobId and current.lockJobId ~= game.JobId then
				if os.time() - (current.lockTimestamp or 0) < LOCK_EXPIRY then
					wasLocked = true
					return nil
				end
			end

			local data = current or createDefault()

			data.lockJobId = game.JobId
			data.lockTimestamp = os.time()

			loadedData = data
			return data
		end)

		if wasLocked then error("Session locked") end
	end)

	if not success or not loadedData then
		player:Kick("Data locked — rejoin")
		return
	end

	loadedData = runMigrations(loadedData)
	if not loadedData then
		player:Kick("Version mismatch")
		return
	end

	sessionData[player] = loadedData
	sessionBase[player] = base
	lastSave[player] = tick()

	leaderstats.Money.Value = loadedData.money or 0
	leaderstats.Rebirths.Value = loadedData.rebirths or 0

	print("[PlayerData] Loaded", player.Name, "— Money:", loadedData.money, "Slots:", PlayerData.countSlots(loadedData.slots or {}), "Inventory:", #(loadedData.inventory or {}))

	if base and loadedData.slots then
		PlayerData.hydrateSlots(player, base, loadedData.slots)
	end

	if loadedData.inventory then
		-- Wait for character to be ready so hotbar UI can receive Tools
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(0.5)  -- Give client hotbar a moment to initialize
		
		for _, itemData in loadedData.inventory do
			local income = getIncomeFromRegistry(itemData.name)
			Pickup.giveItem(player, itemData.name, itemData.rarity, income)
			task.wait(0.05)  -- Small stagger between Tool creation to let client catch up
		end
		if #loadedData.inventory > 0 then
			print("[PlayerData] Restored", #loadedData.inventory, "inventory items for", player.Name)
		end
	end

	lockThreads[player] = task.spawn(function()
		while player.Parent do
			task.wait(LOCK_REFRESH)

			pcall(function()
				dataStore:UpdateAsync(key, function(current)
					if current and current.lockJobId == game.JobId then
						current.lockTimestamp = os.time()
						return current
					end
					return nil
				end)
			end)
		end
	end)
end

-----HYDRATE (rebuild)-----
function PlayerData.hydrateSlots(player, base, slots)
	local slotsFolder = base:FindFirstChild("Slots")
	if not slotsFolder then return end

	for slotIndex, slotData in slots do
		local slot = slotsFolder:FindFirstChild("Slot" .. slotIndex)
		if not slot then continue end

		local point = slot:FindFirstChild("PlacementPoint")
		if not point then continue end

		local folder = modelFolders[slotData.rarity]
		if not folder then
			warn("[PlayerData] No folder for rarity:", slotData.rarity)
			continue
		end

		local template = folder:FindFirstChild(slotData.name)
		if not template then
			warn("[PlayerData] Missing model:", slotData.name, "— skipping slot", slotIndex)
			continue
		end

		local incomePerSec = getIncomeFromRegistry(slotData.name)

		local ok, clone = pcall(function()
			local c = template:Clone()
			c:SetAttribute("Name", slotData.name)
			c:SetAttribute("Rarity", slotData.rarity)
			c:SetAttribute("IncomePerSec", incomePerSec)
			c:SetAttribute("Placed", true)

			for _, part in c:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
				end
			end
			return c
		end)

		if not ok or not clone then
			warn("[PlayerData] Failed to clone", slotData.name)
			continue
		end

		local collectButton = slot:FindFirstChild("CollectButton")
		local spawnPos = point.Position + Vector3.new(0, Config.PlacementYOffset, 0)

		if collectButton then
			local targetFlat = Vector3.new(collectButton.Position.X, spawnPos.Y, collectButton.Position.Z)
			clone:PivotTo(CFrame.lookAt(spawnPos, targetFlat) * CFrame.Angles(0, math.rad(180), 0))
		else
			clone:PivotTo(CFrame.new(spawnPos))
		end

		clone.Parent = slot

		slot:SetAttribute("AccumulatedCash", slotData.accumulatedCash or 0)

		if collectButton then
			local billboard = collectButton:FindFirstChild("CashDisplay")
			if billboard then
				local label = billboard:FindFirstChild("Amount")
				if label then
					label.Text = Util.formatMoney(slotData.accumulatedCash or 0)
				end
			end
		end

		BrainrotUI.createBillboard(clone, {
			name = slotData.name,
			rarity = slotData.rarity,
			incomePerSec = incomePerSec,
		})

		-- Prompts handled by shared helper — no duplication
		Placement.createSlotPrompts(clone, slot, base, {
			name = slotData.name,
			rarity = slotData.rarity,
			incomePerSec = incomePerSec,
		})

		print("[PlayerData] Hydrated Slot" .. slotIndex .. ":", slotData.name)
	end
end

-----SAVE SYSTEM-----
function PlayerData.save(player)
	if not sessionData[player] then return end

	local now = tick()
	if lastSave[player] and (now - lastSave[player]) < SAVE_THROTTLE then return end
	lastSave[player] = now

	local data = sessionData[player]

	readLiveState(player, data)

	local key = getKey(player)

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function()
			data.lockJobId = game.JobId
			data.lockTimestamp = os.time()
			data.version = CURRENT_VERSION
			return data
		end)
	end)

	if success then
		print("[PlayerData] Saved", player.Name)
	else
		warn("[PlayerData] FAILED to save", player.Name)
	end
end

-----FINAL SAVE-----
local function forceSave(player)
	if not sessionData[player] then return end

	local data = sessionData[player]

	readLiveState(player, data)

	data.lockJobId = nil
	data.lockTimestamp = nil
	data.version = CURRENT_VERSION

	local key = getKey(player)

	pcall(function()
		dataStore:SetAsync(key, data)
	end)

	print("[PlayerData] Final save", player.Name)
end

-----CLEAN UP-----
local function clearSession(player)
	if lockThreads[player] then
		task.cancel(lockThreads[player])
		lockThreads[player] = nil
	end

	forceSave(player)

	sessionData[player] = nil
	sessionBase[player] = nil
	lastSave[player] = nil

	print("[PlayerData] Session cleared", player.Name)
end

-----LIFECYCLE-----

function PlayerData.setup()
	Players.PlayerRemoving:Connect(clearSession)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			pcall(clearSession, player)
		end
	end)
end

function PlayerData.start()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)

			for _, player in Players:GetPlayers() do
				pcall(PlayerData.save, player)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		PlayerData.load(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			PlayerData.load(player)
		end)
	end
end

return PlayerData