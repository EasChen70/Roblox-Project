--Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:getService("ServerStorage")
local ReplicatedStorage = game:getService("ReplicatedStorage")
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

--Versioning system (lets us evolve save format safely later on)
local CURRENT_VERSION = 1

--Locks (for session locks)
local LOCK_EXPIRY = 60 --expires after 60s
local LOCK_REFRESH = 30 --refresh lock every 30s

--Autosave system
local AUTOSAVE_INTERVAL = 60
local SAVE_THROTTLE = 6 --minimum seconds between saves

--Retry system (for pcalls)
local MAX_RETRIES = 3
local RETRY_DELAYS = {1, 2, 4} --exponential backoff (gives system time to recover)

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-----RUNTIME STATE-----
--Live data
local sessionData = {} -- player → data table
local sessionBase = {} -- player → base reference
local lastSave = {} -- player → last save timestamp
local lockThreads = {} -- player → lock refresh thread

-- Model Storage for rebuilding placed items
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

--Create brand new save file for new player
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

--Unique key per player in DataStore
local function getKey(player)
    return "player_" .. player.UserId
end

--Runs migrations if save version is outdated
local function runMigrations(data)
    if not data.version then data.version = 1 end

	-- If data is newer than your code → reject (rare but important)
	if data.version > CURRENT_VERSION then return nil end

	-- Apply each migration step
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

-- Retries DataStore operations
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

-- Lookup income from Brainrots
local function getIncomeFromRegistry(name)
	for _, entry in Brainrots do
		if entry.name == name then
			return entry.incomePerSec
		end
	end
	return 0
end

-- Count occupied slots in save data
function PlayerData.countSlots(slots)
    local count = 0
    for _ in slots do count += 1 end
    return count
end

-----READ CURRENT GAME STATE-----

--Read placed brainrots from base to savable format
local function readSlots(player)
	local slots = {}

	-- Use stored base OR fallback to live lookup
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


-- Reads ALL live player data (money, rebirths, slots)
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
	end

	data.slots = readSlots(player)
    data.inventory = {}
    local items = Pickup.getInventory(player)
    for _, tool in items do
        if tool then
            table.insert(data.inventory, {
                name = tool.Name,
                rarity = tool:GetAttribute("Rarity"),
            })
        end
    end    
end

-----LOAD SYSTEM (session locked)-----
function PlayerData.load(player)
	local key = getKey(player)

	-- Wait for leaderstats (important dependency)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		player:Kick("Data failed to load — rejoin")
		return
	end

	-- Wait for base assignment
	local base = nil
	local waitStart = tick()

	while not base and tick() - waitStart < 10 do
		base = Base.getPlayerBase(player)
		if not base then task.wait(0.1) end
	end

	if not player.Parent then return end

	-- LOCK SYSTEM using UpdateAsync
	local wasLocked = false
	local loadedData = nil

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function(current)

			-- If another server owns lock → reject
			if current and current.lockJobId and current.lockJobId ~= game.JobId then
				if os.time() - (current.lockTimestamp or 0) < LOCK_EXPIRY then
					wasLocked = true
					return nil
				end
			end

			-- Either existing data OR new default
			local data = current or createDefault()

			-- Acquire lock
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

	-- Apply migrations
	loadedData = runMigrations(loadedData)
	if not loadedData then
		player:Kick("Version mismatch")
		return
	end

	-- Store session
	sessionData[player] = loadedData
	sessionBase[player] = base
	lastSave[player] = tick()

	-- Apply to UI
	leaderstats.Money.Value = loadedData.money or 0
	leaderstats.Rebirths.Value = loadedData.rebirths or 0

	print("[PlayerData] Loaded", player.Name, "— Money:", loadedData.money, "Slots:", PlayerData.countSlots(loadedData.slots or {}), "Inventory:", #(loadedData.inventory or {}))

	-- Rebuild placed brainrots
	if base and loadedData.slots then
		PlayerData.hydrateSlots(player, base, loadedData.slots)
	end

    -- Inventory rebuild
    if loadedData.inventory then
        for _, itemData in loadedData.inventory do
            local income = getIncomeFromRegistry(itemData.name)
            Pickup.giveItem(player, itemData.name, itemData.rarity, income)
        end
        if #loadedData.inventory > 0 then
            print("[PlayerData] Restored", #loadedData.inventory, "inventory items for", player.Name)
        end
    end
    

	-- LOCK REFRESH LOOP (keeps ownership)
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
-----HYDRATE(rebuild)-----
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

		-- Clone + anchor
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

		-- Position (matches Placement.luau logic)
		local collectButton = slot:FindFirstChild("CollectButton")
		local spawnPos = point.Position + Vector3.new(0, Config.PlacementYOffset, 0)

		if collectButton then
			local targetFlat = Vector3.new(collectButton.Position.X, spawnPos.Y, collectButton.Position.Z)
			clone:PivotTo(CFrame.lookAt(spawnPos, targetFlat) * CFrame.Angles(0, math.rad(180), 0))
		else
			clone:PivotTo(CFrame.new(spawnPos))
		end

		clone.Parent = slot

		-- Restore accumulated cash
		slot:SetAttribute("AccumulatedCash", slotData.accumulatedCash or 0)

		-- Update CollectButton display
		if collectButton then
			local billboard = collectButton:FindFirstChild("CashDisplay")
			if billboard then
				local label = billboard:FindFirstChild("Amount")
				if label then
					label.Text = Util.formatMoney(slotData.accumulatedCash or 0)
				end
			end
		end

		-- Billboard
		BrainrotUI.createBillboard(clone, {
			name = slotData.name,
			rarity = slotData.rarity,
			incomePerSec = incomePerSec,
		})

		-- Pick Up prompt (E)
		local pickupAtt = Instance.new("Attachment")
		pickupAtt.Name = "PickupAttachment"
		pickupAtt.Position = Vector3.new(0, 2.5, 0)
		pickupAtt.Parent = clone.PrimaryPart

		local pickupPrompt = Instance.new("ProximityPrompt")
		pickupPrompt.ActionText = "Pick Up"
		pickupPrompt.ObjectText = slotData.name
		pickupPrompt.HoldDuration = Config.PickupHoldDuration
		pickupPrompt.MaxActivationDistance = 8
		pickupPrompt.RequiresLineOfSight = false
		pickupPrompt.Parent = pickupAtt

		pickupPrompt.Triggered:Connect(function(triggerPlayer)
			if Base.getOwner(base) ~= triggerPlayer then return end
			if Pickup.isCarrying(triggerPlayer) then return end

			local giveOk = Pickup.giveItem(triggerPlayer, slotData.name, slotData.rarity, incomePerSec)
			if not giveOk then return end

			clone:Destroy()
			Placement.refreshPrompts(triggerPlayer)
			PlayerData.save(triggerPlayer)
			print(triggerPlayer.Name, "picked up", slotData.name, "from", slot.Name, "(loaded)")
		end)

		-- Sell prompt (F)
		local sellAtt = Instance.new("Attachment")
		sellAtt.Name = "SellAttachment"
		sellAtt.Position = Vector3.new(0, 6, 0)
		sellAtt.Parent = clone.PrimaryPart

		local sellPrompt = Instance.new("ProximityPrompt")
		sellPrompt.ActionText = "Sell"
		sellPrompt.ObjectText = "$" .. (incomePerSec * 10)
		sellPrompt.HoldDuration = Config.PickupHoldDuration + 0.05
		sellPrompt.MaxActivationDistance = 8
		sellPrompt.RequiresLineOfSight = false
		sellPrompt.KeyboardKeyCode = Enum.KeyCode.F
		sellPrompt.Parent = sellAtt

		sellPrompt.Triggered:Connect(function(triggerPlayer)
			if Base.getOwner(base) ~= triggerPlayer then return end

			local sellValue = incomePerSec * 10
			local stats = triggerPlayer:FindFirstChild("leaderstats")
			if stats then
				local money = stats:FindFirstChild("Money")
				if money then money.Value += sellValue end
			end

			slot:SetAttribute("AccumulatedCash", 0)
			local cb = slot:FindFirstChild("CollectButton")
			if cb then
				local bd = cb:FindFirstChild("CashDisplay")
				if bd then
					local lbl = bd:FindFirstChild("Amount")
					if lbl then lbl.Text = "$0" end
				end
			end

			clone:Destroy()
			Placement.refreshPrompts(triggerPlayer)
			PlayerData.save(triggerPlayer)
			print(triggerPlayer.Name, "sold", slotData.name, "for $" .. sellValue, "(loaded)")
		end)

		print("[PlayerData] Hydrated Slot" .. slotIndex .. ":", slotData.name)
	end
end
-----SAVE SYSTEM-----
function PlayerData.save(player)
	if not sessionData[player] then return end

	-- Prevent spam saving
	local now = tick()
	if lastSave[player] and (now - lastSave[player]) < SAVE_THROTTLE then return end
	lastSave[player] = now

	local data = sessionData[player]

	-- Pull current game state into save data
	readLiveState(player, data)

	local key = getKey(player)

	local success = retryAsync(function()
		dataStore:UpdateAsync(key, function()
			-- Maintain lock
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

	-- IMPORTANT: remove lock so next server can load
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
	-- Stop lock thread
	if lockThreads[player] then
		task.cancel(lockThreads[player])
		lockThreads[player] = nil
	end

	-- Final save
	forceSave(player)

	-- Clear memory
	sessionData[player] = nil
	sessionBase[player] = nil
	lastSave[player] = nil

	print("[PlayerData] Session cleared", player.Name)
end

-----LIFECYCLE/ORCHESTRATION-----

function PlayerData.setup()
	-- Save when player leaves
	Players.PlayerRemoving:Connect(clearSession)

	-- Save when server shuts down
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			pcall(clearSession, player)
		end
	end)
end

function PlayerData.start()
	-- Autosave loop
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)

			for _, player in Players:GetPlayers() do
				pcall(PlayerData.save, player)
			end
		end
	end)

	-- Load on join
	Players.PlayerAdded:Connect(function(player)
		PlayerData.load(player)
	end)

	-- Studio support
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			PlayerData.load(player)
		end)
	end
end

return PlayerData