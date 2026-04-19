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

local CURRENT_VERSION = 2  -- bumped from 1 for level field

local LOCK_EXPIRY = 60
local LOCK_REFRESH = 30

local AUTOSAVE_INTERVAL = 10
local SAVE_THROTTLE = 6           -- only used by PlayerData.save (autosave safety net)
local REQUEST_COALESCE_WINDOW = 1.5  -- event-driven saves coalesce within this window

local MAX_RETRIES = 3
local RETRY_DELAYS = {1, 2, 4}

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-----RUNTIME STATE-----
local sessionData = {}
local sessionBase = {}
local lastSave = {}           -- tick time of last completed save (for throttle + coalesce decisions)
local lockThreads = {}
local pendingSave = {}        -- player → true when a coalesced save is scheduled

local modelFolders = {
	Common    = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare      = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic      = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic    = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret    = ServerStorage:WaitForChild("SecretBrainRotModels"),
}

local migrations = {}

-- Migration v1 -> v2: default level = 1 on all existing slots + inventory items
migrations[2] = function(data)
	if data.slots then
		for _, slot in data.slots do
			slot.level = slot.level or 1
		end
	end
	if data.inventory then
		for _, item in data.inventory do
			item.level = item.level or 1
		end
	end
	return data
end

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
	for _, entry in ipairs(Brainrots) do
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
					level = child:GetAttribute("Level") or 1,
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

	-- Slot logging (parity with inventory logging)
	local slotCount = PlayerData.countSlots(data.slots)
	print("[PlayerData] Reading slots for save, count:", slotCount)
	for slotIndex, slotData in data.slots do
		print("[PlayerData]   - Slot" .. slotIndex .. ":", slotData.name, slotData.rarity, "L" .. slotData.level, "$" .. slotData.accumulatedCash)
	end

	local items = Pickup.getInventory(player)

	print("[PlayerData] Reading inventory for save, count:", #items)

	for _, tool in items do
		if tool then
			local toolLevel = tool:GetAttribute("Level") or 1
			table.insert(data.inventory, {
				name = tool.Name,
				rarity = tool:GetAttribute("Rarity"),
				level = toolLevel,
			})
			print("[PlayerData]   - Inv:", tool.Name, tool:GetAttribute("Rarity"), "L" .. toolLevel)
		end
	end

	print("[PlayerData] Final inventory save count:", #data.inventory)
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
			Pickup.giveItem(player, itemData.name, itemData.rarity, income, itemData.level or 1)
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

		local level = slotData.level or 1
		local baseIncome = getIncomeFromRegistry(slotData.name)
		local incomePerSec = Brainrots.getIncomeAtLevel(baseIncome, slotData.rarity, level)

		local ok, clone = pcall(function()
			local c = template:Clone()
			c:SetAttribute("Name", slotData.name)
			c:SetAttribute("Rarity", slotData.rarity)
			c:SetAttribute("Level", level)
			c:SetAttribute("BaseIncome", baseIncome)
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
			level = level,
			maxLevel = Brainrots.MaxLevel,
		})

		-- Prompts + upgrade billboard handled by shared helper
		Placement.createSlotPrompts(clone, slot, base, {
			name = slotData.name,
			rarity = slotData.rarity,
			baseIncome = baseIncome,
			level = level,
		})

		print("[PlayerData] Hydrated Slot" .. slotIndex .. ":", slotData.name, "L" .. level)
	end
end

-----SAVE SYSTEM-----

-- Internal: do the save. Bypasses throttle. Used by requestSave + autosave path.
local function doSave(player, reason)
	if not sessionData[player] then return end

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

	lastSave[player] = tick()

	if success then
		print("[PlayerData] Saved", player.Name, "(" .. reason .. ")")
	else
		warn("[PlayerData] FAILED to save", player.Name, "(" .. reason .. ")")
	end
end

-- Event-driven save. Coalesces rapid calls within REQUEST_COALESCE_WINDOW.
-- Use this from destructive event hooks (place, pickup, stash, upgrade, sell, collect).
function PlayerData.requestSave(player)
	if not sessionData[player] then return end

	if pendingSave[player] then
		-- Already scheduled — the pending handler will capture final state when it fires
		print("[PlayerData] requestSave coalesced for", player.Name)
		return
	end

	pendingSave[player] = true

	task.delay(REQUEST_COALESCE_WINDOW, function()
		pendingSave[player] = nil

		-- Player may have left during the coalesce window
		if not sessionData[player] then return end

		local ok, err = pcall(doSave, player, "requested")
		if not ok then
			warn("[PlayerData] requestSave handler crashed for", player.Name, err)
		end
	end)
end

-- Throttled save. Used by autosave loop as a safety-net.
-- Manual callers should prefer requestSave for destructive events.
function PlayerData.save(player)
	if not sessionData[player] then return end

	local now = tick()
	if lastSave[player] and (now - lastSave[player]) < SAVE_THROTTLE then
		print("[PlayerData] save throttled for", player.Name, "(" .. string.format("%.1f", now - lastSave[player]) .. "s since last)")
		return
	end

	doSave(player, "autosave")
end

-----CLEAN UP-----
-- Atomic clearSession: captures data FIRST, clears sessionData FIRST (before yielding SetAsync),
-- so concurrent callers (PlayerRemoving + BindToClose) can't both proceed past the guard.
local function clearSession(player)
	-- Atomic claim: if sessionData[player] is nil, another caller already handled this.
	-- This check-and-clear MUST happen before any yield (task.wait, UpdateAsync, SetAsync).
	local data = sessionData[player]
	if not data then return end
	sessionData[player] = nil

	-- Cancel lock refresh thread (doesn't yield)
	if lockThreads[player] then
		task.cancel(lockThreads[player])
		lockThreads[player] = nil
	end

	-- Clear pending coalesce flag so any still-queued task.delay handler no-ops
	pendingSave[player] = nil

	-- Final save: read live state + SetAsync (this yields, but we've already claimed the slot)
	readLiveState(player, data)
	data.lockJobId = nil
	data.lockTimestamp = nil
	data.version = CURRENT_VERSION

	local key = getKey(player)
	local ok, err = pcall(function()
		dataStore:SetAsync(key, data)
	end)
	if not ok then
		warn("[PlayerData] Final save FAILED for", player.Name, err)
	else
		print("[PlayerData] Final save", player.Name)
	end

	-- Final cleanup
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