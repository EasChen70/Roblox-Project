local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local TutorialSteps = require(ReplicatedStorage.TutorialSteps)
local Base = require(ServerScriptService.Base)
local FunnelAnalytics = require(ServerScriptService.FunnelAnalytics)
local PlayerData = require(ServerScriptService.PlayerData)

local Tutorial = {}

local TAGS = TutorialSteps.TAGS
local STEP_ORDER = TutorialSteps.ORDER
local stepsById = TutorialSteps.STEPS

local runtimeState = {}
local structureSnapshots = {}
local cashState = {}
local cashConnections = {}
local connectedLaunchPrompts = {}
local connectedReturnPrompts = {}
local started = false
local markStepComplete

local function getStepDefinition(stepId)
	return stepsById[stepId]
end

local function addTag(instance, tag)
	if instance and not CollectionService:HasTag(instance, tag) then
		CollectionService:AddTag(instance, tag)
	end
end

local function getCurrentStepId(flags)
	for _, stepId in ipairs(STEP_ORDER) do
		if not flags[stepId] then
			return stepId
		end
	end

	return nil
end

local function getPlacedModel(slot)
	for _, child in ipairs(slot:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Placed") then
			return child
		end
	end

	return nil
end

local function getSlotsFolder(player)
	local base = Base.getPlayerBase(player)
	if not base then
		return nil
	end

	return base:FindFirstChild("Slots")
end

local function readStructureSnapshot(player)
	local snapshot = {}
	local slotsFolder = getSlotsFolder(player)
	if not slotsFolder then
		return snapshot
	end

	for i = 1, Config.MaxSlots do
		local slot = slotsFolder:FindFirstChild("Slot" .. i)
		if slot then
			local placedModel = getPlacedModel(slot)
			snapshot[i] = {
				occupied = placedModel ~= nil,
				level = placedModel and (placedModel:GetAttribute("Level") or 1) or 0,
			}
		end
	end

	return snapshot
end

local function snapshotHasUpgradedBrainrot(snapshot)
	for _, slotState in pairs(snapshot) do
		if slotState and slotState.occupied == true and (slotState.level or 0) > 1 then
			return true
		end
	end

	return false
end

local function syncUpgradeStepFromSnapshot(player)
	if snapshotHasUpgradedBrainrot(structureSnapshots[player] or {}) then
		-- Loading existing state should not backfill onboarding funnel progress.
		markStepComplete(player, "upgradeBrainrot", true)
	end
end

local function cleanupCashTracking(player)
	local playerConnections = cashConnections[player]
	if playerConnections then
		for _, connection in pairs(playerConnections) do
			connection:Disconnect()
		end
	end

	cashConnections[player] = nil
	cashState[player] = nil
end

local function bindCashTracking(player)
	cleanupCashTracking(player)

	local slotsFolder = getSlotsFolder(player)
	if not slotsFolder then
		return false
	end

	local playerCashState = {}
	local playerConnections = {}

	for i = 1, Config.MaxSlots do
		local slot = slotsFolder:FindFirstChild("Slot" .. i)
		if slot then
			local amount = slot:GetAttribute("AccumulatedCash") or 0
			playerCashState[i] = {
				previous = amount,
				current = amount,
			}

			playerConnections[i] = slot:GetAttributeChangedSignal("AccumulatedCash"):Connect(function()
				local state = playerCashState[i]
				if not state then
					return
				end

				local newAmount = slot:GetAttribute("AccumulatedCash") or 0
				state.previous = state.current
				state.current = newAmount
			end)
		end
	end

	cashState[player] = playerCashState
	cashConnections[player] = playerConnections
	return true
end

local function refreshPlayerBindings(player)
	structureSnapshots[player] = readStructureSnapshot(player)

	if not bindCashTracking(player) then
		task.delay(1, function()
			if player.Parent then
				refreshPlayerBindings(player)
			end
		end)
	end
end

local function ensurePlayerState(player)
	local state = runtimeState[player]
	if state then
		return state
	end

	local tutorialComplete, tutorialStepFlags = PlayerData.getTutorialState(player)
	if tutorialComplete == nil then
		return nil
	end

	state = {
		tutorialComplete = tutorialComplete == true,
		flags = tutorialStepFlags or {},
		suppressedAnalyticsFlags = {},
	}

	runtimeState[player] = state
	refreshPlayerBindings(player)
	return state
end

local function syncPlayer(player)
	local state = runtimeState[player]
	if not state or not player.Parent then
		return
	end

	local currentStepId = nil
	if not state.tutorialComplete then
		currentStepId = getCurrentStepId(state.flags)
		if not currentStepId then
			state.tutorialComplete = true
			PlayerData.setTutorialState(player, true, state.flags)
			PlayerData.requestSave(player)
		end
	end

	Remotes.TutorialStepChanged:FireClient(player, {
		currentStepId = state.tutorialComplete and nil or currentStepId,
		completed = state.tutorialComplete,
	})
end

markStepComplete = function(player, stepId, suppressAnalytics)
	local state = ensurePlayerState(player)
	local step = getStepDefinition(stepId)
	if not state or not step or state.tutorialComplete then
		return false
	end

	local flagId = step.completionFlag or step.id
	if state.flags[flagId] then
		return false
	end

	state.flags[flagId] = true
	if suppressAnalytics then
		state.suppressedAnalyticsFlags[flagId] = true
	else
		state.suppressedAnalyticsFlags[flagId] = nil
	end

	if not getCurrentStepId(state.flags) then
		state.tutorialComplete = true
	end

	if not suppressAnalytics then
		FunnelAnalytics.syncTutorialProgress(player, state.flags, state.suppressedAnalyticsFlags)
	end

	PlayerData.setTutorialState(player, state.tutorialComplete, state.flags)
	PlayerData.requestSave(player)
	syncPlayer(player)
	return true
end

local function queuePlayerSync(player)
	task.delay(1, function()
		if player.Parent then
			syncPlayer(player)
		end
	end)
end

local function refreshAndSyncPlayer(player)
	refreshPlayerBindings(player)
	syncUpgradeStepFromSnapshot(player)
	syncPlayer(player)
end

local function skipTutorial(player)
	local state = ensurePlayerState(player)
	if not state or state.tutorialComplete then
		return
	end

	state.tutorialComplete = true
	PlayerData.setTutorialState(player, true, state.flags)
	PlayerData.requestSave(player)
	syncPlayer(player)
end

local function loadPlayer(player)
	local state = ensurePlayerState(player)
	if not state then
		return
	end

	if not state.tutorialComplete then
		FunnelAnalytics.logOnboardingStart(player)
	end

	refreshAndSyncPlayer(player)
	if not state.tutorialComplete then
		FunnelAnalytics.primeTutorialProgress(
			player,
			state.flags,
			state.suppressedAnalyticsFlags
		)
	end

	task.delay(1, function()
		if player.Parent then
			refreshAndSyncPlayer(player)
			local refreshedState = runtimeState[player]
			if refreshedState and not refreshedState.tutorialComplete then
				FunnelAnalytics.primeTutorialProgress(
					player,
					refreshedState.flags,
					refreshedState.suppressedAnalyticsFlags
				)
			end
		end
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function()
		queuePlayerSync(player)
	end)

	if player.Character then
		queuePlayerSync(player)
	end
end

-- Placement and upgrade progress are inferred from before/after slot snapshots so
-- the tutorial stays aligned with hydrated data and existing placement callbacks.
local function detectPlacementChanges(previousSnapshot, currentSnapshot)
	local placedBrainrot = false
	local upgradedBrainrot = false

	for i = 1, Config.MaxSlots do
		local before = previousSnapshot[i] or {}
		local after = currentSnapshot[i] or {}
		local beforeOccupied = before.occupied == true
		local afterOccupied = after.occupied == true

		if not beforeOccupied and afterOccupied then
			placedBrainrot = true
		end

		if beforeOccupied and afterOccupied and (after.level or 0) > (before.level or 0) then
			upgradedBrainrot = true
		end
	end

	return placedBrainrot, upgradedBrainrot
end

local function getTrackedCashState(player)
	local playerCashState = cashState[player]
	if playerCashState then
		return playerCashState
	end

	refreshPlayerBindings(player)
	return cashState[player]
end

local function ensureTrackedSlotState(playerCashState, slotIndex, liveAmount)
	local slotState = playerCashState[slotIndex]
	if slotState then
		return slotState
	end

	slotState = {
		previous = liveAmount,
		current = liveAmount,
	}
	playerCashState[slotIndex] = slotState
	return slotState
end

local function collectedCashThisTick(slotState, liveAmount)
	local beforeCollect = math.max(slotState.previous or 0, slotState.current or 0)
	return beforeCollect > 0 and liveAmount == 0
end

local function tagBaseTargets()
	local map = Workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	if not bases then
		return
	end

	for _, base in ipairs(bases:GetChildren()) do
		local slots = base:FindFirstChild("Slots")
		if not slots then
			continue
		end

		for i = 1, Config.MaxSlots do
			local slot = slots:FindFirstChild("Slot" .. i)
			if not slot then
				continue
			end

			local point = slot:FindFirstChild("PlacementPoint")
			if point and point:IsA("BasePart") then
				addTag(point, TAGS.BrainrotSlot)
			end

			local collectButton = slot:FindFirstChild("CollectButton")
			if collectButton and collectButton:IsA("BasePart") then
				addTag(collectButton, TAGS.CollectButton)
			end
		end
	end
end

local function connectLaunchPrompt(prompt)
	if not prompt or connectedLaunchPrompts[prompt] then
		return
	end

	connectedLaunchPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		markStepComplete(player, "useLaunchCannon")
	end)
end

local function connectReturnPrompt(prompt)
	if not prompt or connectedReturnPrompts[prompt] then
		return
	end

	connectedReturnPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		markStepComplete(player, "returnToBase")
	end)
end

local function tagCannonTargets()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Model") and obj.Name == "CannonShop" then
			addTag(obj, TAGS.CannonShop)
		elseif obj:IsA("Model") and obj.Name == "ReturnCannonModel" then
			addTag(obj, TAGS.ReturnCannon)

			local prompt = obj:FindFirstChild("ProximityPrompt", true)
			if prompt then
				addTag(prompt, TAGS.ReturnCannon)
				connectReturnPrompt(prompt)
			end
		elseif obj:IsA("Model") and string.find(obj.Name, "CannonModel") and obj.Name ~= "ReturnCannonModel" then
			local seat = obj:FindFirstChild("CannonSeat", true)
			local prompt = obj:FindFirstChild("ProximityPrompt", true)
			if seat and prompt then
				addTag(obj, TAGS.LaunchCannon)
				addTag(prompt, TAGS.LaunchCannon)
				connectLaunchPrompt(prompt)
			end
		end
	end
end

function Tutorial.init()
	PlayerData.onLoaded(loadPlayer)

	Players.PlayerAdded:Connect(function(player)
		bindPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		runtimeState[player] = nil
		structureSnapshots[player] = nil
		cleanupCashTracking(player)
		FunnelAnalytics.clearPlayer(player)
	end)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

function Tutorial.start()
	if started then
		return
	end
	started = true

	tagBaseTargets()
	tagCannonTargets()

	Remotes.UpgradeCannon.OnServerEvent:Connect(function(player)
		task.defer(function()
			if not player.Parent then
				return
			end

			if (player:GetAttribute("CannonPower") or 1) == 2 then
				markStepComplete(player, "freeCannonUpgrade")
			end
		end)
	end)

	Remotes.TutorialSkipRequested.OnServerEvent:Connect(function(player)
		skipTutorial(player)
	end)
end

function Tutorial.handleGrab(player, model)
	if not model or not player.Character then
		return
	end

	if model:GetAttribute("IsWorldItem") == true and model:IsDescendantOf(player.Character) then
		markStepComplete(player, "grabBrainrot")
	end
end

function Tutorial.handleStash(player)
	if not player then
		return
	end

	-- Stashing is still part of the gameplay loop, but it no longer completes the
	-- return-cannon tutorial step. That step is now tied to the actual cannon prompt.
end

function Tutorial.handlePlacementDataChanged(player)
	local currentSnapshot = readStructureSnapshot(player)
	local previousSnapshot = structureSnapshots[player]
	structureSnapshots[player] = currentSnapshot

	if not previousSnapshot then
		return
	end

	local placedBrainrot, upgradedBrainrot = detectPlacementChanges(previousSnapshot, currentSnapshot)

	if placedBrainrot then
		markStepComplete(player, "placeBrainrot")
		refreshPlayerBindings(player)
	end

	if upgradedBrainrot or snapshotHasUpgradedBrainrot(currentSnapshot) then
		markStepComplete(player, "upgradeBrainrot")
	end
end

function Tutorial.handleIncomeDataChanged(player)
	local slotsFolder = getSlotsFolder(player)
	if not slotsFolder then
		return
	end

	local playerCashState = getTrackedCashState(player)
	if not playerCashState then
		return
	end

	-- Cash collection is inferred from tracked slot amounts so existing touch-based
	-- collection continues to drive tutorial progress without extra prompt hooks.
	for i = 1, Config.MaxSlots do
		local slot = slotsFolder:FindFirstChild("Slot" .. i)
		if slot then
			local liveAmount = slot:GetAttribute("AccumulatedCash") or 0
			local slotState = ensureTrackedSlotState(playerCashState, i, liveAmount)

			if collectedCashThisTick(slotState, liveAmount) then
				markStepComplete(player, "collectCash")
			end

			slotState.previous = liveAmount
			slotState.current = liveAmount
		end
	end

	for _, slotState in pairs(playerCashState) do
		if slotState.previous > 0 and slotState.current == 0 then
			markStepComplete(player, "collectCash")
			break
		end
	end

	for _, slotState in pairs(playerCashState) do
		slotState.previous = slotState.current
	end
end

return Tutorial
