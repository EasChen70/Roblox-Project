--Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
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

local CURRENT_VERSION = 7 -- bumped from 6 to 7 for wheel spin time persistence

local LOCK_EXPIRY = 60
local LOCK_REFRESH = 20

local AUTOSAVE_INTERVAL = 10
local SAVE_THROTTLE = 6 -- only used by PlayerData.save (autosave safety net)
local REQUEST_COALESCE_WINDOW = 1.5 -- event-driven saves coalesce within this window

local MAX_RETRIES = 3
local RETRY_DELAYS = { 1, 2, 4 }

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
local RAW_JOB_ID = game.JobId or ""
local SESSION_OWNER_ID = RAW_JOB_ID ~= "" and RAW_JOB_ID or ("studio-" .. HttpService:GenerateGUID(false))

-----RUNTIME STATE-----
local sessionData = {}
local sessionBase = {}
local lastSave = {} -- tick time of last completed save (for throttle + coalesce decisions)
local lockThreads = {}
local saveState = {} -- player -> { active, rerunRequested, nextReason, idleEvent }
local pendingSave = {} -- player → true when a coalesced save is scheduled

local finalizingSessions = {} -- player -> { snapshot, running, completed, success, reason, event }
local saveBlocked = {} -- player -> true after a lock-lost conflict

local debugFailpoints = {
	requestedSaveFailures = 0,
	finalSaveFailures = 0,
	lockMismatchResults = 0,
}

local migrations = {}
local loadedCallbacks = {}

print(
	string.format(
		"[PlayerData] Session owner initialized ownerId=%s rawJobId=%s",
		SESSION_OWNER_ID,
		RAW_JOB_ID ~= "" and RAW_JOB_ID or "<empty>"
	)
)

local function countPresentEntries(values)
	local count = 0
	for _ in pairs(values or {}) do
		count += 1
	end
	return count
end

local function cloneCompletedFlags(flags)
	local cloned = {}
	for stepId, completed in pairs(flags or {}) do
		if completed then
			cloned[stepId] = true
		end
	end
	return cloned
end

local function cloneSlotData(slots)
	local cloned = {}
	for slotIndex, slotData in pairs(slots or {}) do
		cloned[tostring(slotIndex)] = {
			name = slotData.name,
			rarity = slotData.rarity,
			level = slotData.level or 1,
			mutation = slotData.mutation or "None",
			accumulatedCash = slotData.accumulatedCash or 0,
		}
	end
	return cloned
end

local function cloneInventoryData(items)
	local cloned = {}
	for _, itemData in ipairs(items or {}) do
		table.insert(cloned, {
			name = itemData.name,
			rarity = itemData.rarity,
			level = itemData.level or 1,
			mutation = itemData.mutation or "None",
		})
	end
	return cloned
end

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

-- Migration v2 -> v3: default rebirthMultiplier on existing saves
migrations[3] = function(data)
	data.rebirthMultiplier = data.rebirthMultiplier or Config.RebirthBaseMultiplier
	return data
end

-- Migration v3 -> v4: tutorial progress defaults + veteran guard
migrations[4] = function(data)
	data.tutorialComplete = data.tutorialComplete == true
	data.tutorialStepFlags = cloneCompletedFlags(data.tutorialStepFlags)

	if (data.rebirths or 0) > 0 or (data.cannonPower or 1) > 1 or countPresentEntries(data.slots) > 0 then
		data.tutorialComplete = true
	end

	return data
end

-- Migration v4 -> v5: normalize slot keys to strings so sparse layouts persist safely
migrations[5] = function(data)
	data.slots = cloneSlotData(data.slots)
	return data
end

-- Migration v5 -> v6: persist the one-time community reward claim
migrations[6] = function(data)
	data.communityRewardClaimed = data.communityRewardClaimed == true
	return data
end

-- Migration v6 -> v7: Add lastSpinTime
migrations[7] = function(data)
	data.lastSpinTime = data.lastSpinTime or 0
	return data
end
-----HELPERS-----

local function createDefault()
	return {
		version = CURRENT_VERSION,
		money = 0,
		rebirths = 0,
		cannonPower = 1,
		rebirthMultiplier = Config.RebirthBaseMultiplier,
		slots = {},
		inventory = {},
		tutorialComplete = false,
		tutorialStepFlags = {},
		communityRewardClaimed = false,
		lastSpinTime = 0,
	}
end

local function getKey(player)
	return "player_" .. player.UserId
end

local function runMigrations(data)
	if not data.version then
		data.version = 1
	end

	if data.version > CURRENT_VERSION then
		return nil
	end

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
	for _ in slots do
		count += 1
	end
	return count
end

local function isStudioDebugEnabled()
	return RunService:IsStudio()
end

local function setDebugFailpoint(name, count)
	if not isStudioDebugEnabled() or debugFailpoints[name] == nil then
		return false
	end

	debugFailpoints[name] = math.max(0, count or 1)
	return true
end

local function consumeDebugFailpoint(name)
	if not isStudioDebugEnabled() then
		return false
	end

	local remaining = debugFailpoints[name]
	if not remaining or remaining <= 0 then
		return false
	end

	debugFailpoints[name] = remaining - 1
	return true
end

local function isNonEmptyString(value)
	return type(value) == "string" and value ~= ""
end

local function getStoredLockOwnerId(data)
	if not data then
		return nil
	end

	if isNonEmptyString(data.lockOwnerId) then
		return data.lockOwnerId
	end

	if isNonEmptyString(data.lockJobId) then
		return data.lockJobId
	end

	return nil
end

local function setLockOwner(data)
	data.lockOwnerId = SESSION_OWNER_ID
	data.lockJobId = RAW_JOB_ID ~= "" and RAW_JOB_ID or nil
	data.lockTimestamp = os.time()
end

local function clearLockOwner(data)
	data.lockOwnerId = nil
	data.lockJobId = nil
	data.lockTimestamp = nil
end

-----READ CURRENT GAME STATE-----

local function readSlots(player)
	local slots = {}

	local base = sessionBase[player] or Base.getPlayerBase(player)
	if not base then
		return slots
	end
	local slotsFolder = base:FindFirstChild("Slots")
	if not slotsFolder then
		return slots
	end

	for i = 1, Config.MaxSlots do
		local slot = slotsFolder:FindFirstChild("Slot" .. i)
		if not slot then
			continue
		end

		for _, child in slot:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("Placed") then
				slots[tostring(i)] = {
					name = child:GetAttribute("Name"),
					rarity = child:GetAttribute("Rarity"),
					level = child:GetAttribute("Level") or 1,
					mutation = child:GetAttribute("Mutation") or "None",
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

		if money then
			data.money = money.Value
		end
		if rebirths then
			data.rebirths = rebirths.Value
		end
		data.cannonPower = player:GetAttribute("CannonPower") or 1
		data.rebirthMultiplier = player:GetAttribute("RebirthMultiplier") or Config.RebirthBaseMultiplier
		data.lastSpinTime = player:GetAttribute("LastSpinTime") or 0
	end

	data.slots = readSlots(player)
	data.inventory = {}

	-- Slot logging (parity with inventory logging)
	local slotCount = PlayerData.countSlots(data.slots)
	print("[PlayerData] Reading slots for save, count:", slotCount)
	for slotIndex, slotData in data.slots do
		print(
			"[PlayerData]   - Slot" .. slotIndex .. ":",
			slotData.name,
			slotData.rarity,
			"L" .. slotData.level,
			"$" .. slotData.accumulatedCash
		)
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
				mutation = tool:GetAttribute("Mutation") or "None",
			})
			print("[PlayerData]   - Inv:", tool.Name, tool:GetAttribute("Rarity"), "L" .. toolLevel)
		end
	end

	print("[PlayerData] Final inventory save count:", #data.inventory)
end

local function clonePersistedData(data)
	return {
		version = CURRENT_VERSION,
		money = data.money or 0,
		rebirths = data.rebirths or 0,
		cannonPower = data.cannonPower or 1,
		rebirthMultiplier = data.rebirthMultiplier or Config.RebirthBaseMultiplier,
		slots = cloneSlotData(data.slots),
		inventory = cloneInventoryData(data.inventory),
		tutorialComplete = data.tutorialComplete == true,
		tutorialStepFlags = cloneCompletedFlags(data.tutorialStepFlags),
		communityRewardClaimed = data.communityRewardClaimed == true,
		lastSpinTime = data.lastSpinTime or 0,
	}
end

local function buildSaveSnapshot(player, sourceData)
	local snapshot = clonePersistedData(sourceData)
	readLiveState(player, snapshot)
	snapshot.version = CURRENT_VERSION
	return snapshot
end

local function ensureSaveState(player)
	local state = saveState[player]
	if state then
		return state
	end

	state = {
		active = false,
		rerunRequested = false,
		nextReason = nil,
		idleEvent = Instance.new("BindableEvent"),
	}
	saveState[player] = state
	return state
end

local function destroySaveState(player)
	local state = saveState[player]
	if not state then
		return
	end

	if state.idleEvent then
		state.idleEvent:Destroy()
	end

	saveState[player] = nil
end

local function mergeNormalSaveReason(currentReason, newReason)
	if currentReason == "requested" or newReason == "requested" then
		return "requested"
	end

	return currentReason or newReason
end

local function queueNormalSaveReason(player, reason)
	local state = ensureSaveState(player)
	state.rerunRequested = true
	state.nextReason = mergeNormalSaveReason(state.nextReason, reason)
	return state
end

local function signalSaveLaneIdle(state)
	if state and state.idleEvent then
		-- Waiters only care about the lane being fully idle, not mid-burst transitions.
		state.idleEvent:Fire()
	end
end

local function waitForSaveLaneIdle(player)
	local state = saveState[player]

	while state and state.active do
		state.idleEvent.Event:Wait()
		state = saveState[player]
	end
end

local function cleanupTerminalSessionState(player)
	sessionBase[player] = nil
	lastSave[player] = nil
	saveBlocked[player] = nil
	pendingSave[player] = nil
	destroySaveState(player)
end

local function createFinalizationRecord(snapshot)
	return {
		snapshot = snapshot,
		running = false,
		completed = false,
		success = false,
		reason = nil,
		event = Instance.new("BindableEvent"),
	}
end

local function destroyFinalizationRecord(player, finalizing)
	if finalizing and finalizing.event then
		local event = finalizing.event
		task.defer(function()
			event:Destroy()
		end)
	end

	if finalizingSessions[player] == finalizing then
		finalizingSessions[player] = nil
	end
end

local function logSaveAttempt(player, reason, attempt, result, storedLockOwnerId, detail)
	local message = string.format(
		"[PlayerData] SaveAttempt userId=%s name=%s reason=%s attempt=%d result=%s writerOwnerId=%s storedLockOwnerId=%s",
		tostring(player.UserId),
		player.Name,
		reason,
		attempt,
		result,
		tostring(SESSION_OWNER_ID),
		tostring(storedLockOwnerId)
	)

	if detail and detail ~= "" then
		message = message .. " detail=" .. detail
	end

	if result == "ok" then
		print(message)
	else
		warn(message)
	end
end

local function writeSnapshot(player, snapshot, reason, options)
	options = options or {}

	local key = getKey(player)
	local releaseLock = options.releaseLock == true

	for attempt = 1, MAX_RETRIES do
		local storedLockOwnerId = nil
		local lockLost = false
		local forcedLockMismatch = consumeDebugFailpoint("lockMismatchResults")
		local forcedDatastoreFailure = false

		if reason == "requested" then
			forcedDatastoreFailure = consumeDebugFailpoint("requestedSaveFailures")
		elseif reason == "final" then
			forcedDatastoreFailure = consumeDebugFailpoint("finalSaveFailures")
		end

		if forcedDatastoreFailure then
			logSaveAttempt(player, reason, attempt, "datastore_error", storedLockOwnerId, "studio_failpoint")
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAYS[attempt])
			end
			continue
		end

		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(current)
				storedLockOwnerId = getStoredLockOwnerId(current)

				if forcedLockMismatch then
					lockLost = true
					return nil
				end

				if storedLockOwnerId ~= SESSION_OWNER_ID then
					lockLost = true
					return nil
				end

				local nextData = clonePersistedData(snapshot)
				if releaseLock then
					clearLockOwner(nextData)
				else
					setLockOwner(nextData)
				end
				return nextData
			end)
		end)

		if lockLost then
			logSaveAttempt(player, reason, attempt, "lock_lost", storedLockOwnerId)
			return false, "lock_lost", storedLockOwnerId
		end

		if ok then
			logSaveAttempt(player, reason, attempt, "ok", storedLockOwnerId)
			return true, "ok", storedLockOwnerId
		end

		logSaveAttempt(player, reason, attempt, "datastore_error", storedLockOwnerId, tostring(err))
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAYS[attempt])
		end
	end

	return false, "datastore_error", nil
end

local function blockSessionAfterLockLost(player, reason, storedLockOwnerId)
	if saveBlocked[player] then
		return
	end

	saveBlocked[player] = true
	pendingSave[player] = nil

	local state = saveState[player]
	if state then
		state.rerunRequested = false
		state.nextReason = nil
	end

	if lockThreads[player] then
		task.cancel(lockThreads[player])
		lockThreads[player] = nil
	end

	warn(
		"[PlayerData] Lock lost for",
		player.Name,
		"during",
		reason,
		"storedLockOwnerId=" .. tostring(storedLockOwnerId)
	)

	task.defer(function()
		if player.Parent then
			player:Kick("Data session conflict detected - please rejoin")
		end
	end)
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
		if not base then
			task.wait(0.1)
		end
	end

	if not player.Parent then
		return
	end

	local wasLocked = false
	local loadedData = nil

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function(current)
			local storedLockOwnerId = getStoredLockOwnerId(current)
			if storedLockOwnerId and storedLockOwnerId ~= SESSION_OWNER_ID then
				if os.time() - (current.lockTimestamp or 0) < LOCK_EXPIRY then
					wasLocked = true
					return nil
				end
			end

			local data = current or createDefault()

			setLockOwner(data)

			loadedData = data
			return data
		end)

		if wasLocked then
			error("Session locked")
		end
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

	loadedData.tutorialComplete = loadedData.tutorialComplete == true
	loadedData.tutorialStepFlags = cloneCompletedFlags(loadedData.tutorialStepFlags)

	local existingFinalizing = finalizingSessions[player]
	if existingFinalizing then
		destroyFinalizationRecord(player, existingFinalizing)
	end

	destroySaveState(player)
	sessionData[player] = loadedData
	sessionBase[player] = base
	lastSave[player] = tick()
	pendingSave[player] = nil
	saveBlocked[player] = nil
	finalizingSessions[player] = nil

	leaderstats.Money.Value = loadedData.money or 0
	leaderstats.Rebirths.Value = loadedData.rebirths or 0
	player:SetAttribute("CannonPower", loadedData.cannonPower or 1)
	player:SetAttribute("RebirthMultiplier", loadedData.rebirthMultiplier or Config.RebirthBaseMultiplier)
	player:SetAttribute("LastSpinTime", loadedData.lastSpinTime or 0)

	print(
		"[PlayerData] Loaded",
		player.Name,
		"— Money:",
		loadedData.money,
		"Slots:",
		PlayerData.countSlots(loadedData.slots or {}),
		"Inventory:",
		#(loadedData.inventory or {})
	)

	if base and loadedData.slots then
		PlayerData.hydrateSlots(base, loadedData.slots)
	end

	if loadedData.inventory then
		-- Wait for character to be ready so hotbar UI can receive Tools
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(0.5) -- Give client hotbar a moment to initialize

		for _, itemData in loadedData.inventory do
			local income = getIncomeFromRegistry(itemData.name)
			Pickup.giveItem(
				player,
				itemData.name,
				itemData.rarity,
				income,
				itemData.level or 1,
				itemData.mutation or "None"
			)
			task.wait(0.05) -- Small stagger between Tool creation to let client catch up
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
					if current and getStoredLockOwnerId(current) == SESSION_OWNER_ID then
						setLockOwner(current)
						return current
					end
					return nil
				end)
			end)
		end
	end)

	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(function()
			local ok, err = pcall(callback, player)
			if not ok then
				warn("[PlayerData] onLoaded callback failed for", player.Name, err)
			end
		end)
	end
end

-----HYDRATE (rebuild)-----
local function getModelFolderName(rarity, mutation)
	if mutation and mutation ~= "None" then
		return mutation .. rarity .. "BrainRotModels"
	end
	return rarity .. "BrainRotModels"
end

function PlayerData.hydrateSlots(base, slots)
	local slotsFolder = base:FindFirstChild("Slots")
	if not slotsFolder then
		return
	end

	for slotIndex, slotData in slots do
		local slot = slotsFolder:FindFirstChild("Slot" .. slotIndex)
		if not slot then
			continue
		end

		local point = slot:FindFirstChild("PlacementPoint")
		if not point then
			continue
		end

		local mutation = slotData.mutation or "None"
		local folderName = getModelFolderName(slotData.rarity, mutation)
		local folder = ServerStorage:FindFirstChild(folderName)
		if not folder then
			warn("[PlayerData] No folder:", folderName)
			continue
		end

		local template = folder:FindFirstChild(slotData.name)
		if not template then
			warn("[PlayerData] Missing model:", slotData.name, "— skipping slot", slotIndex)
			continue
		end

		local level = slotData.level or 1
		local baseIncome = getIncomeFromRegistry(slotData.name)
		local incomePerSec = Brainrots.getIncomeWithMutation(baseIncome, slotData.rarity, level, mutation)

		local ok, clone = pcall(function()
			local c = template:Clone()
			c:SetAttribute("Name", slotData.name)
			c:SetAttribute("Rarity", slotData.rarity)
			c:SetAttribute("Level", level)
			c:SetAttribute("BaseIncome", baseIncome)
			c:SetAttribute("IncomePerSec", incomePerSec)
			c:SetAttribute("Placed", true)
			c:SetAttribute("Mutation", mutation)
			for _, part in c:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
				end
			end
			return c
		end)

		if not ok or not clone then
			warn("[PlayerData] Failed to clone", slotData.name)
			continue
		end

		local collectButton = slot:FindFirstChild("CollectButton")
		local placementCFrame = Placement.getPlacementCFrame(slotData.name, slot)
		if not placementCFrame then
			clone:Destroy()
			continue
		end
		clone:PivotTo(placementCFrame)

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
			mutation = mutation,
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

local function performSaveWrite(player, reason)
	if saveBlocked[player] then
		return false, "lock_lost"
	end

	if not sessionData[player] then
		return true, "ok"
	end

	local snapshot = buildSaveSnapshot(player, sessionData[player])
	local success, saveReason, storedLockOwnerId = writeSnapshot(player, snapshot, reason, {
		releaseLock = false,
	})

	if success then
		lastSave[player] = tick()
		print("[PlayerData] Saved", player.Name, "(" .. reason .. ")")
	elseif saveReason == "lock_lost" then
		blockSessionAfterLockLost(player, reason, storedLockOwnerId)
	else
		warn("[PlayerData] FAILED to save", player.Name, "(" .. reason .. ")")
	end

	return success, saveReason
end

-- The calling thread owns the normal-save loop and flips active before the first yield.
local function runNormalSaveLoop(player, initialReason)
	if saveBlocked[player] then
		return false, "lock_lost"
	end

	if not sessionData[player] then
		return true, "ok"
	end

	local state = ensureSaveState(player)
	if state.active then
		queueNormalSaveReason(player, initialReason)
		return true, "queued"
	end

	state.active = true
	state.rerunRequested = false
	state.nextReason = nil

	local currentReason = initialReason

	while true do
		local success, saveReason = performSaveWrite(player, currentReason)

		if saveReason == "lock_lost" or saveBlocked[player] or not sessionData[player] then
			state.active = false
			state.rerunRequested = false
			state.nextReason = nil
			signalSaveLaneIdle(state)
			return success, saveReason
		end

		if not state.rerunRequested then
			state.active = false
			state.nextReason = nil
			signalSaveLaneIdle(state)
			return success, saveReason
		end

		currentReason = state.nextReason or currentReason
		state.rerunRequested = false
		state.nextReason = nil
	end
end

-- Event-driven save. Coalesces rapid calls within REQUEST_COALESCE_WINDOW.
-- Use this from destructive event hooks (place, pickup, stash, upgrade, sell, collect).
function PlayerData.requestSave(player)
	if saveBlocked[player] or not sessionData[player] then
		return
	end

	if pendingSave[player] then
		-- Already scheduled — the pending handler will capture final state when it fires
		print("[PlayerData] requestSave coalesced for", player.Name)
		return
	end

	pendingSave[player] = true

	task.delay(REQUEST_COALESCE_WINDOW, function()
		pendingSave[player] = nil

		-- Player may have left during the coalesce window
		if saveBlocked[player] or not sessionData[player] then
			return
		end

		local state = ensureSaveState(player)
		if state.active then
			queueNormalSaveReason(player, "requested")
			return
		end

		local ok, err = pcall(runNormalSaveLoop, player, "requested")
		if not ok then
			warn("[PlayerData] requestSave handler crashed for", player.Name, err)
		end
	end)
end

-- Throttled save. Used by autosave loop as a safety-net.
-- Manual callers should prefer requestSave for destructive events.
function PlayerData.save(player)
	if saveBlocked[player] then
		return false, "lock_lost"
	end

	if not sessionData[player] then
		return true, "ok"
	end

	if pendingSave[player] then
		return true, "skipped_pending"
	end

	local state = ensureSaveState(player)
	if state.active then
		queueNormalSaveReason(player, "autosave")
		return true, "queued"
	end

	local now = tick()
	if lastSave[player] and (now - lastSave[player]) < SAVE_THROTTLE then
		print(
			"[PlayerData] save throttled for",
			player.Name,
			"(" .. string.format("%.1f", now - lastSave[player]) .. "s since last)"
		)
		return true, "ok"
	end

	return runNormalSaveLoop(player, "autosave")
end

function PlayerData.onLoaded(cb)
	table.insert(loadedCallbacks, cb)
end

function PlayerData.getTutorialState(player)
	local data = sessionData[player]
	if not data then
		return nil, nil
	end

	return data.tutorialComplete == true, cloneCompletedFlags(data.tutorialStepFlags)
end

function PlayerData.setTutorialState(player, tutorialComplete, tutorialStepFlags)
	local data = sessionData[player]
	if not data then
		return false
	end

	data.tutorialComplete = tutorialComplete == true
	data.tutorialStepFlags = cloneCompletedFlags(tutorialStepFlags)
	return true
end

function PlayerData.getCommunityRewardClaimed(player)
	local data = sessionData[player]
	if not data then
		return nil
	end

	return data.communityRewardClaimed == true
end

function PlayerData.setCommunityRewardClaimed(player)
	local data = sessionData[player]
	if not data then
		return false
	end

	data.communityRewardClaimed = true
	return true
end

function PlayerData.debugFailNextRequestedSave(count)
	return setDebugFailpoint("requestedSaveFailures", count)
end

function PlayerData.debugFailNextFinalSave(count)
	return setDebugFailpoint("finalSaveFailures", count)
end

function PlayerData.debugForceNextLockMismatch(count)
	return setDebugFailpoint("lockMismatchResults", count)
end

-----CLEAN UP-----
-- Atomic clearSession: captures a retryable final snapshot FIRST and removes sessionData
-- before any yield so concurrent callers (PlayerRemoving + BindToClose) share one finalization owner.
function PlayerData.clearSession(player)
	local finalizing = finalizingSessions[player]
	if not finalizing then
		-- This claim-and-snapshot block MUST happen before any yield.
		local data = sessionData[player]
		if not data then
			return true, "ok"
		end

		sessionData[player] = nil

		if lockThreads[player] then
			task.cancel(lockThreads[player])
			lockThreads[player] = nil
		end

		pendingSave[player] = nil
		local state = saveState[player]
		if state then
			state.rerunRequested = false
			state.nextReason = nil
		end

		if not sessionBase[player] then
			warn("[PlayerData] clearSession snapshot capture without sessionBase for", player.Name)
		end

		finalizing = createFinalizationRecord(buildSaveSnapshot(player, data))
		finalizingSessions[player] = finalizing
	end

	if finalizing.running then
		finalizing.event.Event:Wait()
		if finalizing.completed then
			return finalizing.success, finalizing.reason
		end
		return false, finalizing.reason or "datastore_error"
	end

	if finalizing.completed then
		return finalizing.success, finalizing.reason
	end

	finalizing.running = true
	finalizing.success = false
	finalizing.reason = nil

	waitForSaveLaneIdle(player)

	local success, reason = writeSnapshot(player, finalizing.snapshot, "final", {
		releaseLock = true,
	})

	finalizing.running = false

	if success then
		finalizing.completed = true
		finalizing.success = true
		finalizing.reason = "ok"
		finalizing.event:Fire()
		cleanupTerminalSessionState(player)
		print("[PlayerData] Final save", player.Name)
		print("[PlayerData] Session cleared", player.Name)
		destroyFinalizationRecord(player, finalizing)
		return true, "ok"
	end

	if reason == "lock_lost" then
		finalizing.completed = true
		finalizing.success = false
		finalizing.reason = "lock_lost"
		finalizing.event:Fire()
		cleanupTerminalSessionState(player)
		warn("[PlayerData] Final save skipped because lock was lost for", player.Name)
		print("[PlayerData] Session cleared", player.Name)
		destroyFinalizationRecord(player, finalizing)
		return false, "lock_lost"
	end

	finalizing.completed = false
	finalizing.success = false
	finalizing.reason = "datastore_error"
	finalizing.event:Fire()
	cleanupTerminalSessionState(player)
	warn("[PlayerData] Final save FAILED for", player.Name)
	return false, "datastore_error"
end

-----LIFECYCLE-----

function PlayerData.setup()
	-- PlayerRemoving is wired in Main.server.luau to control ordering with Base.releaseBase
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			pcall(PlayerData.clearSession, player)
		end

		local retryPlayers = {}
		for player in finalizingSessions do
			table.insert(retryPlayers, player)
		end

		for _, player in ipairs(retryPlayers) do
			pcall(PlayerData.clearSession, player)
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