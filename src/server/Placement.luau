local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local Config = require(ReplicatedStorage.Config)
local Brainrots = require(ReplicatedStorage.Brainrots)
local Base = require(game.ServerScriptService.Base)
local Pickup = require(game.ServerScriptService.Pickup)
local BrainrotUI = require(game.ReplicatedStorage.BrainrotUI)

local Placement = {}

-- CALLBACK (data save hook)
local onDataChangedCallback = nil

function Placement.onDataChanged(cb)
	onDataChangedCallback = cb
end

local function getModelFolderName(rarity, mutation)
	if mutation and mutation ~= "None" then
		return mutation .. rarity .. "BrainRotModels"
	end
	return rarity .. "BrainRotModels"
end

local function getRegistryBaseIncome(name)
	for _, entry in ipairs(Brainrots) do
		if entry.name == name then
			return entry.incomePerSec
		end
	end

	return nil
end

local function getPlacedCorrection(name)
	local specialTransforms = Config.SpecialBrainrotTransforms
	local transformData = specialTransforms and specialTransforms[name]
	return (transformData and transformData.placedCorrection) or CFrame.new()
end

local function getPlacedBrainrotData(model)
	if not model then
		return nil
	end

	local name = model:GetAttribute("Name") or model.Name
	local rarity = model:GetAttribute("Rarity")
	if not rarity then
		return nil
	end

	return {
		name = name,
		rarity = rarity,
		baseIncome = model:GetAttribute("BaseIncome") or getRegistryBaseIncome(name) or model:GetAttribute("IncomePerSec") or 0,
		level = model:GetAttribute("Level") or 1,
		mutation = model:GetAttribute("Mutation") or "None",
	}
end

local function getEquippedToolPlacementData(tool)
	if not tool then
		return nil
	end

	local name = tool.Name
	local rarity = tool:GetAttribute("Rarity")
	if not rarity then
		return nil
	end

	return {
		name = name,
		rarity = rarity,
		baseIncome = tool:GetAttribute("BaseIncome") or getRegistryBaseIncome(name) or tool:GetAttribute("IncomePerSec") or 0,
		level = tool:GetAttribute("Level") or 1,
		mutation = tool:GetAttribute("Mutation") or "None",
	}
end

local modelFolders = {
	Common = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret = ServerStorage:WaitForChild("SecretBrainRotModels"),
	Divine = ServerStorage:WaitForChild("DivineBrainRotModels"),
	Ancient = ServerStorage:WaitForChild("AncientBrainRotModels"),
	Exclusive = ServerStorage:FindFirstChild("ExclusiveBrainRotModels"),
}

local bases = game.Workspace.Map.Bases

-- Debounce guard — prevents double-fire on rapid prompt clicks.
-- Keyed by slot so pickup/sell/place on the same slot are all gated together.
local promptDebounce = {}

local function withDebounce(key, fn)
	if promptDebounce[key] then
		return
	end
	promptDebounce[key] = true
	fn()
	task.delay(0.3, function()
		promptDebounce[key] = nil
	end)
end

local function isSlotOccupied(slot)
	for _, child in slot:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Name") then
			return true
		end
	end
	return false
end

local function createPromptAttachment(model, name, heightFromBottom)
	local parentPart = model and model.PrimaryPart
	if not parentPart then
		return nil
	end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	local worldAnchorPosition = Vector3.new(boundsCFrame.Position.X, bottomY + heightFromBottom, boundsCFrame.Position.Z)
	local localAnchorPosition = parentPart.CFrame:PointToObjectSpace(worldAnchorPosition)

	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = localAnchorPosition
	att.Parent = parentPart
	return att
end

local function destroyUpgradeBillboard(slot)
	local upgradeBillboard = slot:FindFirstChild("UpgradeBillboard")
	if upgradeBillboard then
		upgradeBillboard:Destroy()
	end
end

local function preparePlacedClone(slot, itemData)
	local name = itemData.name
	local rarity = itemData.rarity
	local baseIncome = itemData.baseIncome or getRegistryBaseIncome(name) or itemData.incomePerSec or 0
	local level = itemData.level or 1
	local mutation = itemData.mutation or "None"

	local folderName = getModelFolderName(rarity, mutation)
	local folder = ServerStorage:FindFirstChild(folderName) or modelFolders[rarity]
	local template = folder and folder:FindFirstChild(name)
	if not template then
		return nil, nil
	end

	local clone = template:Clone()
	if not clone.PrimaryPart then
		clone:Destroy()
		return nil, nil
	end

	clone:SetAttribute("Name", name)
	clone:SetAttribute("Rarity", rarity)
	clone:SetAttribute("Placed", true)
	clone:SetAttribute("Mutation", mutation)

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	local placementCFrame = Placement.getPlacementCFrame(name, slot)
	if not placementCFrame then
		clone:Destroy()
		return nil, nil
	end

	clone:PivotTo(placementCFrame)

	return clone, {
		name = name,
		rarity = rarity,
		baseIncome = baseIncome,
		level = level,
		mutation = mutation,
	}
end

local function attachPlacedClone(clone, slot, base, itemData)
	clone.Parent = slot

	local currentIncome = Brainrots.getIncomeWithMutation(
		itemData.baseIncome,
		itemData.rarity,
		itemData.level,
		itemData.mutation
	)
	BrainrotUI.createBillboard(clone, {
		name = itemData.name,
		rarity = itemData.rarity,
		incomePerSec = currentIncome,
		level = itemData.level,
		maxLevel = Brainrots.MaxLevel,
		mutation = itemData.mutation,
	})

	Placement.createSlotPrompts(clone, slot, base, {
		name = itemData.name,
		rarity = itemData.rarity,
		baseIncome = itemData.baseIncome,
		level = itemData.level,
	})
end

function Placement.getPlacementCFrame(brainrotName, slot)
	local point = slot:FindFirstChild("PlacementPoint")
	if not point then
		return nil
	end

	local collectButton = slot:FindFirstChild("CollectButton")
	local spawnPos = point.Position + Vector3.new(0, Config.PlacementYOffset, 0)
	local basePivot

	if collectButton then
		local targetFlat = Vector3.new(collectButton.Position.X, spawnPos.Y, collectButton.Position.Z)
		basePivot = CFrame.lookAt(spawnPos, targetFlat) * CFrame.Angles(0, math.rad(180), 0)
	else
		basePivot = CFrame.new(spawnPos)
	end

	return basePivot * getPlacedCorrection(brainrotName)
end

-- Shared prompt setup for a placed model on a slot.
-- Called by Placement.setup() on fresh place AND PlayerData.hydrateSlots on load.
-- data = { name, rarity, baseIncome, level }
function Placement.createSlotPrompts(clone, slot, base, data)
	local name = data.name
	local rarity = data.rarity
	local baseIncome = data.baseIncome
	local level = data.level or 1

	-- Compute and set attributes based on level
	local mutation = clone:GetAttribute("Mutation") or "None"
	local currentIncome = Brainrots.getIncomeWithMutation(baseIncome, rarity, level, mutation)
	clone:SetAttribute("Level", level)
	clone:SetAttribute("BaseIncome", baseIncome)
	clone:SetAttribute("IncomePerSec", currentIncome)

	-- PICKUP / SWAP prompt
	local pickupPrompt = Instance.new("ProximityPrompt")
	pickupPrompt.ActionText = "Pick Up"
	pickupPrompt.ObjectText = name
	pickupPrompt.HoldDuration = Config.PickupHoldDuration
	pickupPrompt.MaxActivationDistance = 8
	pickupPrompt.RequiresLineOfSight = false
	pickupPrompt.Parent = createPromptAttachment(clone, "PickupAttachment", Config.PlacedPickupPromptHeight)

	pickupPrompt.Triggered:Connect(function(triggerPlayer)
		withDebounce(slot, function()
			if Base.getOwner(base) ~= triggerPlayer then
				return
			end

			local equippedTool = Pickup.getInventoryTool(triggerPlayer)
			if equippedTool then
				local outgoingData = getPlacedBrainrotData(clone)
				local incomingData = getEquippedToolPlacementData(equippedTool)
				if not outgoingData or not incomingData then
					return
				end

				local incomingClone, normalizedIncomingData = preparePlacedClone(slot, incomingData)
				if not incomingClone then
					return
				end

				Pickup.removeFromInventory(triggerPlayer, equippedTool)
				destroyUpgradeBillboard(slot)
				clone:Destroy()
				attachPlacedClone(incomingClone, slot, base, normalizedIncomingData)
				equippedTool:Destroy()

				Pickup.giveItem(
					triggerPlayer,
					outgoingData.name,
					outgoingData.rarity,
					outgoingData.baseIncome,
					outgoingData.level,
					outgoingData.mutation
				)

				if onDataChangedCallback then
					onDataChangedCallback(triggerPlayer)
				end

				Placement.refreshPrompts(triggerPlayer)
				return
			end

			if Pickup.isCarrying(triggerPlayer) then
				return
			end

			local pickupLevel = clone:GetAttribute("Level") or 1
			local pickupMutation = clone:GetAttribute("Mutation") or "None"
			local success = Pickup.giveItem(triggerPlayer, name, rarity, baseIncome, pickupLevel, pickupMutation)
			if not success then
				return
			end

			clone:Destroy()
			destroyUpgradeBillboard(slot)

			if onDataChangedCallback then
				onDataChangedCallback(triggerPlayer)
			end

			Placement.refreshPrompts(triggerPlayer)
		end)
	end)

	-- SELL prompt (flat: baseIncome × 10, no level bonus)
	local sellValue = baseIncome * 10
	local sellPrompt = Instance.new("ProximityPrompt")
	sellPrompt.ActionText = "Sell"
	sellPrompt.ObjectText = "$" .. sellValue
	sellPrompt.HoldDuration = Config.PickupHoldDuration + 0.05
	sellPrompt.MaxActivationDistance = 8
	sellPrompt.RequiresLineOfSight = false
	sellPrompt.KeyboardKeyCode = Enum.KeyCode.F
	sellPrompt.Parent = createPromptAttachment(clone, "SellAttachment", Config.PlacedSellPromptHeight)

	sellPrompt.Triggered:Connect(function(triggerPlayer)
		withDebounce(slot, function()
			if Base.getOwner(base) ~= triggerPlayer then
				return
			end

			local stats = triggerPlayer:FindFirstChild("leaderstats")
			if stats then
				local money = stats:FindFirstChild("Money")
				if money then
					money.Value += sellValue
				end
			end

			slot:SetAttribute("AccumulatedCash", 0)

			-- Reset CollectButton display
			local cb = slot:FindFirstChild("CollectButton")
			if cb then
				local bd = cb:FindFirstChild("CashDisplay")
				if bd then
					local lbl = bd:FindFirstChild("Amount")
					if lbl then
						lbl.Text = "$0"
					end
				end
			end

			clone:Destroy()
			destroyUpgradeBillboard(slot)

			if onDataChangedCallback then
				onDataChangedCallback(triggerPlayer)
			end

			Placement.refreshPrompts(triggerPlayer)
		end)
	end)

	-- UPGRADE BILLBOARD (pink, in front of slot) + upgrade prompt handler
	local upgradeBillboard = BrainrotUI.createUpgradeBillboard(slot, {
		rarity = rarity,
		level = level,
		baseIncome = baseIncome,
	})

	if upgradeBillboard and upgradeBillboard.PrimaryPart then
		local upgradePrompt = upgradeBillboard.PrimaryPart:FindFirstChild("UpgradePrompt")

		if upgradePrompt then
			upgradePrompt.MouseClick:Connect(function(triggerPlayer)
				withDebounce("upgrade_" .. slot.Name, function()
					if Base.getOwner(base) ~= triggerPlayer then
						return
					end

					local currentLevel = clone:GetAttribute("Level") or 1
					if currentLevel >= Brainrots.MaxLevel then
						return
					end

					local cost = Brainrots.getUpgradeCost(baseIncome, rarity, currentLevel)
					if not cost then
						return
					end

					local stats = triggerPlayer:FindFirstChild("leaderstats")
					local money = stats and stats:FindFirstChild("Money")
					if not money or money.Value < cost then
						return
					end

					money.Value -= cost
					Remotes.UpgradeSound:FireClient(triggerPlayer)
					local newLevel = currentLevel + 1
					local newIncome = Brainrots.getIncomeWithMutation(baseIncome, rarity, newLevel, mutation)
					clone:SetAttribute("Level", newLevel)
					clone:SetAttribute("IncomePerSec", newIncome)

					BrainrotUI.updateBillboardLevel(clone, newLevel, newIncome, Brainrots.MaxLevel)

					if newLevel >= Brainrots.MaxLevel then
						BrainrotUI.setUpgradeBillboardMax(upgradeBillboard)
						Remotes.MaxLevelGlow:FireAllClients(clone)
					else
						local nextCost = Brainrots.getUpgradeCost(baseIncome, rarity, newLevel)
						BrainrotUI.updateUpgradeBillboard(upgradeBillboard, nextCost, newLevel)
					end

					if onDataChangedCallback then
						onDataChangedCallback(triggerPlayer)
					end
				end)
			end)
		end

		-- If already at max level on placement/hydrate, reflect that now
		if level >= Brainrots.MaxLevel then
			BrainrotUI.setUpgradeBillboardMax(upgradeBillboard)
			Remotes.MaxLevelGlow:FireAllClients(clone)
		end
	end
end

function Placement.setup()
	for _, base in bases:GetChildren() do
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
			if not point then
				continue
			end

			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Place"
			prompt.ObjectText = ""
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt.Parent = point

			prompt.Triggered:Connect(function(player)
				withDebounce(slot, function()
					if Base.getOwner(base) ~= player then
						return
					end

					local tool = Pickup.getInventoryTool(player)
					if not tool then
						return
					end

					if isSlotOccupied(slot) then
						return
					end

					local incomingData = getEquippedToolPlacementData(tool)
					if not incomingData then
						return
					end

					local clone, normalizedIncomingData = preparePlacedClone(slot, incomingData)
					if not clone then
						return
					end

					attachPlacedClone(clone, slot, base, normalizedIncomingData)

					Pickup.removeFromInventory(player, tool)
					tool:Destroy()

					prompt.Enabled = false
					Placement.refreshPrompts(player)

					if onDataChangedCallback then
						onDataChangedCallback(player)
					end
				end)
			end)
		end
	end
end

function Placement.refreshPrompts(player)
	local playerBase = nil
	for _, base in bases:GetChildren() do
		if Base.getOwner(base) == player then
			playerBase = base
			break
		end
	end

	if not playerBase then
		return
	end

	local slots = playerBase:FindFirstChild("Slots")
	if not slots then
		return
	end

	for i = 1, Config.MaxSlots do
		local slot = slots:FindFirstChild("Slot" .. i)
		if not slot then
			continue
		end

		local point = slot:FindFirstChild("PlacementPoint")
		if not point then
			continue
		end

		local prompt = point:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			continue
		end

		local hasEquippedItem = Pickup.isItemEquipped(player)
		local occupied = isSlotOccupied(slot)

		prompt.Enabled = hasEquippedItem and not occupied

		if occupied then
			local pickupAttachment = slot:FindFirstChild("PickupAttachment", true)
			local pickupPrompt = pickupAttachment and pickupAttachment:FindFirstChildOfClass("ProximityPrompt")
			if pickupPrompt then
				pickupPrompt.ActionText = hasEquippedItem and "Swap" or "Pick Up"
			end
		end
	end
end

return Placement
