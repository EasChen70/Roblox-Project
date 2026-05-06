local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BrainrotUI = require(ReplicatedStorage.BrainrotUI)
local Brainrots = require(ReplicatedStorage.Brainrots)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local Base = require(ServerScriptService.Base)
local Pickup = require(ServerScriptService.Pickup)
local PlayerData = require(ServerScriptService.PlayerData)

local CommunityRewards = {}

local PROMPT_HOLD_DURATION = 0.3
local PROMPT_RANGE = 8
local PROMPT_ATTACHMENT_HEIGHT = 2.5
local CLAIM_RANGE_TOLERANCE = 4

local pedestalsByBase = {}
local claimLocks = {}
local initialized = false

local function getExclusiveBaseIncome()
	for _, entry in ipairs(Brainrots) do
		if entry.name == Config.ExclusiveBrainrotName then
			return entry.incomePerSec
		end
	end

	return 0
end

local function ensurePrimaryPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local foot = model:FindFirstChild("R_Foot", true)
	if foot and foot:IsA("BasePart") then
		model.PrimaryPart = foot
		return foot
	end

	local fallback = model:FindFirstChildWhichIsA("BasePart", true)
	if fallback then
		model.PrimaryPart = fallback
		return fallback
	end

	return nil
end

local function findDecorativeModel(pedestal)
	local decorative = pedestal and pedestal:FindFirstChild(Config.ExclusiveBrainrotName, true)
	if not decorative or not decorative:IsA("Model") then
		return nil
	end

	if not ensurePrimaryPart(decorative) then
		return nil
	end

	return decorative
end

local function createPromptAttachment(primaryPart)
	local attachment = primaryPart:FindFirstChild("CommunityClaimAttachment")
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	attachment = Instance.new("Attachment")
	attachment.Name = "CommunityClaimAttachment"
	attachment.Position = Vector3.new(0, PROMPT_ATTACHMENT_HEIGHT, 0)
	attachment.Parent = primaryPart
	return attachment
end

local function setPedestalState(state, mode)
	if not state then
		return
	end

	local isClaimable = mode == "claimable"
	local isClaimed = mode == "claimed"

	if state.prompt then
		state.prompt.Enabled = isClaimable
		state.prompt:SetAttribute("CommunityClaimActive", isClaimable)
	end

	if state.billboard then
		state.billboard.Enabled = isClaimable
		state.billboard:SetAttribute("CommunityClaimActive", isClaimable)
	end

	if state.claimedBillboard then
		state.claimedBillboard.Enabled = isClaimed
		state.claimedBillboard:SetAttribute("CommunityClaimedActive", isClaimed)
	end

	if state.displayModel then
		state.displayModel:SetAttribute("CommunityClaimActive", isClaimable)
		state.displayModel:SetAttribute("CommunityClaimedActive", isClaimed)
	end
end

local function fireStateSync(player, base, claimed, isActive)
	Remotes.CommunityClaimResult:FireClient(player, {
		kind = "stateSync",
		baseName = base and base.Name or nil,
		claimed = claimed == true,
		promptActive = isActive == true,
	})
end

local function getPlayerDistanceFromPedestal(player, state)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return math.huge
	end

	local anchorPosition
	if state.promptAttachment then
		anchorPosition = state.promptAttachment.WorldPosition
	elseif state.displayModel and state.displayModel.PrimaryPart then
		anchorPosition = state.displayModel.PrimaryPart.Position
	end

	if not anchorPosition then
		return math.huge
	end

	return (rootPart.Position - anchorPosition).Magnitude
end

local function isPlayerWithinClaimRange(player, state)
	local maxDistance = PROMPT_RANGE + CLAIM_RANGE_TOLERANCE
	return getPlayerDistanceFromPedestal(player, state) <= maxDistance
end

local function getClaimState(player)
	local claimed = PlayerData.getCommunityRewardClaimed(player)
	if claimed == nil then
		return nil, false
	end

	return claimed, claimed ~= true
end

local function handlePromptTriggered(base, player)
	if claimLocks[player] then
		return
	end

	if Base.getPlayerBase(player) ~= base then
		return
	end

	if Base.getOwner(base) ~= player then
		return
	end

	local claimed, isActive = getClaimState(player)
	if claimed == nil then
		return
	end

	if not isActive then
		CommunityRewards.syncPedestalForBase(base, player)
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "already_claimed",
		})
		return
	end

	Remotes.CommunityClaimResult:FireClient(player, {
		kind = "openModal",
		baseName = base.Name,
	})
end

function CommunityRewards.syncPedestalForBase(base, player)
	local state = pedestalsByBase[base]
	if not state or not player then
		return
	end

	if Base.getOwner(base) ~= player then
		setPedestalState(state, "hidden")
		return
	end

	local claimed, isActive = getClaimState(player)
	if claimed == nil then
		setPedestalState(state, "hidden")
		return
	end

	setPedestalState(state, claimed == true and "claimed" or "claimable")
	fireStateSync(player, base, claimed, isActive)
end

function CommunityRewards.cleanupBase(base)
	local state = pedestalsByBase[base]
	if not state then
		return
	end

	setPedestalState(state, "hidden")
end

function CommunityRewards.handleClaimRequest(player, mode)
	if claimLocks[player] then
		return
	end

	if mode == "sync" then
		local base = Base.getPlayerBase(player)
		if base then
			CommunityRewards.syncPedestalForBase(base, player)
		else
			Remotes.CommunityClaimResult:FireClient(player, {
				kind = "stateSync",
				baseName = nil,
				claimed = PlayerData.getCommunityRewardClaimed(player) == true,
				promptActive = false,
			})
		end
		return
	end

	local base = Base.getPlayerBase(player)
	local state = base and pedestalsByBase[base]
	if not base or not state then
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "not_ready",
		})
		return
	end

	if Base.getOwner(base) ~= player then
		return
	end

	local claimed = PlayerData.getCommunityRewardClaimed(player)
	if claimed == nil then
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "not_ready",
		})
		return
	end

	if claimed == true then
		CommunityRewards.syncPedestalForBase(base, player)
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "already_claimed",
		})
		return
	end

	if not isPlayerWithinClaimRange(player, state) then
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "too_far",
		})
		return
	end

	local inventory = Pickup.getInventory(player)
	if inventory and #inventory >= Config.MaxInventory then
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "inventory_full",
		})
		return
	end

	claimLocks[player] = true

	local verifiedOk, isInGroup = pcall(function()
		return player:IsInGroupAsync(Config.CommunityGroupId)
	end)

	if not verifiedOk then
		claimLocks[player] = nil
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "verification_error",
		})
		return
	end

	if not isInGroup then
		claimLocks[player] = nil
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "not_in_group",
		})
		return
	end

	local rewardGiven = Pickup.giveItem(
		player,
		Config.ExclusiveBrainrotName,
		"Exclusive",
		getExclusiveBaseIncome(),
		1,
		"None"
	)

	if not rewardGiven then
		claimLocks[player] = nil
		Remotes.CommunityClaimResult:FireClient(player, {
			kind = "claimResult",
			success = false,
			reason = "reward_unavailable",
		})
		return
	end

	PlayerData.setCommunityRewardClaimed(player)
	PlayerData.requestSave(player)
	CommunityRewards.syncPedestalForBase(base, player)

	claimLocks[player] = nil
	Remotes.CommunityClaimResult:FireClient(player, {
		kind = "claimResult",
		success = true,
	})
end

function CommunityRewards.init()
	if initialized then
		return
	end
	initialized = true

	local map = Workspace:FindFirstChild("Map")
	local basesFolder = map and map:FindFirstChild("Bases")
	if not basesFolder then
		warn("[CommunityRewards] Workspace.Map.Bases not found")
		return
	end

	for _, base in ipairs(basesFolder:GetChildren()) do
		local pedestal = base:FindFirstChild(Config.PedestalModelName)
		if not pedestal then
			warn("[CommunityRewards] Missing pedestal on", base.Name)
			continue
		end

		local displayModel = findDecorativeModel(pedestal)
		if not displayModel then
			warn("[CommunityRewards] Missing decorative model on", base.Name)
			continue
		end

		local primaryPart = ensurePrimaryPart(displayModel)
		if not primaryPart then
			warn("[CommunityRewards] Missing primary part on", base.Name)
			continue
		end

		displayModel:SetAttribute("CommunityBaseName", base.Name)

		local promptAttachment = createPromptAttachment(primaryPart)
		local prompt = promptAttachment:FindFirstChild("CommunityClaimPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "CommunityClaimPrompt"
			prompt.ActionText = "Claim Reward"
			prompt.ObjectText = Config.ExclusiveBrainrotName
			prompt.HoldDuration = PROMPT_HOLD_DURATION
			prompt.MaxActivationDistance = PROMPT_RANGE
			prompt.RequiresLineOfSight = false
			prompt.Parent = promptAttachment
		end
		prompt:SetAttribute("CommunityClaimPrompt", true)
		prompt:SetAttribute("CommunityBaseName", base.Name)

		local billboard = BrainrotUI.createClaimBillboard(displayModel, {
			name = Config.ExclusiveBrainrotName,
			rarity = "Exclusive",
			incomePerSec = getExclusiveBaseIncome(),
		})
		if billboard then
			billboard:SetAttribute("CommunityClaimBillboard", true)
			billboard:SetAttribute("CommunityBaseName", base.Name)
		end

		local claimedBillboard = BrainrotUI.createClaimedBillboard(displayModel, {
			name = Config.ExclusiveBrainrotName,
			rarity = "Exclusive",
		})
		if claimedBillboard then
			claimedBillboard:SetAttribute("CommunityClaimedBillboard", true)
			claimedBillboard:SetAttribute("CommunityBaseName", base.Name)
		end

		local state = {
			base = base,
			pedestal = pedestal,
			displayModel = displayModel,
			promptAttachment = promptAttachment,
			prompt = prompt,
			billboard = billboard,
			claimedBillboard = claimedBillboard,
		}

		pedestalsByBase[base] = state
		setPedestalState(state, "hidden")

		prompt.Triggered:Connect(function(player)
			handlePromptTriggered(base, player)
		end)
	end

	Remotes.CommunityClaimRequest.OnServerEvent:Connect(CommunityRewards.handleClaimRequest)

	PlayerData.onLoaded(function(player)
		local base = Base.getPlayerBase(player)
		if base then
			CommunityRewards.syncPedestalForBase(base, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		claimLocks[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		local base = Base.getPlayerBase(player)
		if base then
			CommunityRewards.syncPedestalForBase(base, player)
		end
	end
end

return CommunityRewards
