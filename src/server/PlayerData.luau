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
local Remotes = require(ReplicatedStorage.Remotes)
local Util = require(ReplicatedStorage.Util)

--Server Systems
local Base = require(ServerScriptService.Base)
local Gamepasses = require(ServerScriptService.Gamepasses)
local Pickup = require(ServerScriptService.Pickup)
local Placement = require(ServerScriptService.Placement)

local PlayerData = {}

-----CONFIG/CONSTANTS-----
local DATA_STORE_NAME = "BrainrotCannonV1"

local CURRENT_VERSION = 8 -- bumped from 7 to 8 for offline income persistence

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

-- Migration v7 -> v8: initialize offline income tracking without retroactive backpay
migrations[8] = function(data)
	data.lastIncomeTimestamp = os.time()
	data.doubleCashOwned = data.doubleCashOwned == true
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
		lastIncomeTimestamp = os.time(),
		doubleCashOwned = false,
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
		if i < MAX_RETRIES then
			task.wait(RETRY_DELAYS[i])
		end
	end
	return false, nil
end

local getIncomeFromRegistry

getIncomeFromRegistry = function(name)
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

local function applyOfflineIncome(data, gamepassOwnership)
	local now = os.time()
	local previousTimestamp = data.lastIncomeTimestamp or now
	local offlineSeconds = math.max(0, math.min(Config.OfflineIncomeCapSeconds, now - previousTimestamp))
	local doubleCashResolved = gamepassOwnership
		and gamepassOwnership.resolved
		and gamepassOwnership.resolved.DoubleCash == true
	local doubleCashOwned = if doubleCashResolved
		then gamepassOwnership.ownership.DoubleCash == true
		else data.doubleCashOwned == true
	local totalAmount = 0
	local slotCount = 0

	if Config.OfflineIncomeEnabled and offlineSeconds > 0 then
		local totalMultiplier = data.rebirthMultiplier or Config.RebirthBaseMultiplier
		if doubleCashOwned then
			totalMultiplier *= Config.GamepassValues.DoubleCashMultiplier
		end

		for _, slotData in pairs(data.slots or {}) do
			local level = slotData.level or 1
			local mutation = slotData.mutation or "None"
			local baseIncome = getIncomeFromRegistry(slotData.name)
			local incomePerSec = Brainrots.getIncomeWithMutation(baseIncome, slotData.rarity, level, mutation)
			local effectiveIncomePerSec = math.floor(incomePerSec * totalMultiplier)
			if effectiveIncomePerSec > 0 then
				local awardedAmount = effectiveIncomePerSec * offlineSeconds
				slotData.accumulatedCash = (slotData.accumulatedCash or 0) + awardedAmount
				totalAmount += awardedAmount
				slotCount += 1
			end
		end
	else
		offlineSeconds = 0
	end

	data.lastIncomeTimestamp = now
	if doubleCashResolved then
		data.doubleCashOwned = gamepassOwnership.ownership.DoubleCash == true
	else
		data.doubleCashOwned = data.doubleCashOwned == true
	end

	return {
		totalAmount = totalAmount,
		offlineSeconds = offlineSeconds,
		slotCount = slotCount,
		doubleCashResolved = doubleCashResolved,
		doubleCashOwned = doubleCashOwned,
	}
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
		data.lastIncomeTimestamp = os.time()
		data.doubleCashOwned = player:GetAttribute("HasDoubleCash") == true
	end

	data.slots = readSlots(player)
	data.inventory = {}

	local items = Pickup.getInventory(player)

	for _, tool in items do
		if tool then
			local toolLevel = tool:GetAttribute("Level") or 1
			table.insert(data.inventory, {
				name = tool.Name,
				rarity = tool:GetAttribute("Rarity"),
				level = toolLevel,
				mutation = tool:GetAttribute("Mutation") or "None",
			})
		end
	end
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
		lastIncomeTimestamp = data.lastIncomeTimestamp or os.time(),
		doubleCashOwned = data.doubleCashOwned == true,
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
			return false, "lock_lost", storedLockOwnerId
		end

		if ok then
			return true, "ok", storedLockOwnerId
		end

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
	local migrationFailed = false
	local loadedData = nil
	local offlineAwardPayload = nil
	local gamepassOwnership = Gamepasses.refreshOwnershipNow(player)

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function(current)
			local storedLockOwnerId = getStoredLockOwnerId(current)
			if storedLockOwnerId and storedLockOwnerId ~= SESSION_OWNER_ID then
				if os.time() - (current.lockTimestamp or 0) < LOCK_EXPIRY then
					wasLocked = true
					return nil
				end
			end

			local data = runMigrations(current or createDefault())
			if not data then
				migrationFailed = true
				return nil
			end

			offlineAwardPayload = applyOfflineIncome(data, gamepassOwnership)

			setLockOwner(data)

			loadedData = data
			return data
		end)

		if wasLocked then
			error("Session locked")
		end
	end)

	if migrationFailed then
		player:Kick("Version mismatch")
		return
	end

	if not success or not loadedData then
		player:Kick("Data locked — rejoin")
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
	if not (gamepassOwnership.resolved and gamepassOwnership.resolved.DoubleCash == true)
		and loadedData.doubleCashOwned == true then
		player:SetAttribute("HasDoubleCash", true)
	end

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
			pcall(callback, player)
		end)
	end

	if offlineAwardPayload and offlineAwardPayload.totalAmount > 0 then
		if Config.OfflineIncomePopupEnabled then
			local popupPayload = {
				totalAmount = offlineAwardPayload.totalAmount,
				offlineSeconds = offlineAwardPayload.offlineSeconds,
				slotCount = offlineAwardPayload.slotCount,
			}

			task.delay(2, function()
				if player.Parent then
					Remotes.OfflineEarningsAwarded:FireClient(player, popupPayload)
				end
			end)
		end
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
			continue
		end

		local template = folder:FindFirstChild(slotData.name)
		if not template then
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
	elseif saveReason == "lock_lost" then
		blockSessionAfterLockLost(player, reason, storedLockOwnerId)
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

		pcall(runNormalSaveLoop, player, "requested")
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
		destroyFinalizationRecord(player, finalizing)
		return true, "ok"
	end

	if reason == "lock_lost" then
		finalizing.completed = true
		finalizing.success = false
		finalizing.reason = "lock_lost"
		finalizing.event:Fire()
		cleanupTerminalSessionState(player)
		destroyFinalizationRecord(player, finalizing)
		return false, "lock_lost"
	end

	finalizing.completed = false
	finalizing.success = false
	finalizing.reason = "datastore_error"
	finalizing.event:Fire()
	cleanupTerminalSessionState(player)
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
