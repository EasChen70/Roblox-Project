local Players = game:GetService("Players")
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

local modelFolders = {
	Common    = ServerStorage:WaitForChild("CommonBrainRotModels"),
	Rare      = ServerStorage:WaitForChild("RareBrainRotModels"),
	Epic      = ServerStorage:WaitForChild("EpicBrainRotModels"),
	Legendary = ServerStorage:WaitForChild("LegendaryBrainRotModels"),
	Mythic    = ServerStorage:WaitForChild("MythicBrainRotModels"),
	Secret    = ServerStorage:WaitForChild("SecretBrainRotModels"),
	Divine    = ServerStorage:WaitForChild("DivineBrainRotModels"),
}

local bases = game.Workspace.Map.Bases

-- Debounce guard — prevents double-fire on rapid prompt clicks.
-- Keyed by slot so pickup/sell/place on the same slot are all gated together.
local promptDebounce = {}

local function withDebounce(key, fn)
	if promptDebounce[key] then return end
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

local function createPromptAttachment(parentPart, name, yOffset)
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = Vector3.new(0, yOffset, 0)
	att.Parent = parentPart
	return att
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
	local currentIncome = Brainrots.getIncomeAtLevel(baseIncome, rarity, level)
	clone:SetAttribute("Level", level)
	clone:SetAttribute("BaseIncome", baseIncome)
	clone:SetAttribute("IncomePerSec", currentIncome)

	-- PICKUP prompt (preserves level)
	local pickupPrompt = Instance.new("ProximityPrompt")
	pickupPrompt.ActionText = "Pick Up"
	pickupPrompt.ObjectText = name
	pickupPrompt.HoldDuration = Config.PickupHoldDuration
	pickupPrompt.MaxActivationDistance = 8
	pickupPrompt.RequiresLineOfSight = false
	pickupPrompt.Parent = createPromptAttachment(clone.PrimaryPart, "PickupAttachment", 2.5)

	pickupPrompt.Triggered:Connect(function(triggerPlayer)
		withDebounce(slot, function()
			if Base.getOwner(base) ~= triggerPlayer then return end
			if Pickup.isCarrying(triggerPlayer) then return end

			local pickupLevel = clone:GetAttribute("Level") or 1
			local success = Pickup.giveItem(triggerPlayer, name, rarity, baseIncome, pickupLevel)
			if not success then return end

			clone:Destroy()

			-- Clean up upgrade billboard for this slot
			local ub = slot:FindFirstChild("UpgradeBillboard")
			if ub then ub:Destroy() end

			if onDataChangedCallback then
				onDataChangedCallback(triggerPlayer)
			end

			Placement.refreshPrompts(triggerPlayer)
			print("[Placement] picked up", name, "L" .. pickupLevel, "from slot")
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
	sellPrompt.Parent = createPromptAttachment(clone.PrimaryPart, "SellAttachment", 6)

	sellPrompt.Triggered:Connect(function(triggerPlayer)
		withDebounce(slot, function()
			if Base.getOwner(base) ~= triggerPlayer then return end

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
					if lbl then lbl.Text = "$0" end
				end
			end

			clone:Destroy()

			-- Clean up upgrade billboard for this slot
			local ub = slot:FindFirstChild("UpgradeBillboard")
			if ub then ub:Destroy() end

			if onDataChangedCallback then
				onDataChangedCallback(triggerPlayer)
			end

			Placement.refreshPrompts(triggerPlayer)
			print("[Placement] sold", name, "for $" .. sellValue)
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
					if Base.getOwner(base) ~= triggerPlayer then return end

					local currentLevel = clone:GetAttribute("Level") or 1
					if currentLevel >= Brainrots.MaxLevel then return end

					local cost = Brainrots.getUpgradeCost(baseIncome, rarity, currentLevel)
					if not cost then return end

					local stats = triggerPlayer:FindFirstChild("leaderstats")
					local money = stats and stats:FindFirstChild("Money")
					if not money or money.Value < cost then
						print("[Placement]", triggerPlayer.Name, "can't afford upgrade ($" .. cost .. ")")
						return
					end

					money.Value -= cost
					Remotes.UpgradeSound:FireClient(triggerPlayer)
					local newLevel = currentLevel + 1
					local newIncome = Brainrots.getIncomeAtLevel(baseIncome, rarity, newLevel)

					clone:SetAttribute("Level", newLevel)
					clone:SetAttribute("IncomePerSec", newIncome)

					BrainrotUI.updateBillboardLevel(clone, newLevel, newIncome, Brainrots.MaxLevel)

					if newLevel >= Brainrots.MaxLevel then
						BrainrotUI.setUpgradeBillboardMax(upgradeBillboard)
						BrainrotUI.applyMaxLevelGlow(clone)
					else
						local nextCost = Brainrots.getUpgradeCost(baseIncome, rarity, newLevel)
						BrainrotUI.updateUpgradeBillboard(upgradeBillboard, nextCost, newLevel)
					end

					if onDataChangedCallback then
						onDataChangedCallback(triggerPlayer)
					end

					print("[Placement]", triggerPlayer.Name, "upgraded", name, "to L" .. newLevel, "for $" .. cost)
				end)
			end)
		end

		-- If already at max level on placement/hydrate, reflect that now
		if level >= Brainrots.MaxLevel then
			BrainrotUI.setUpgradeBillboardMax(upgradeBillboard)
			BrainrotUI.applyMaxLevelGlow(clone)
		end
	end
end

function Placement.setup()
	for _, base in bases:GetChildren() do
		local slots = base:FindFirstChild("Slots")
		if not slots then continue end

		for i = 1, Config.MaxSlots do
			local slot = slots:FindFirstChild("Slot" .. i)
			if not slot then continue end

			local point = slot:FindFirstChild("PlacementPoint")
			if not point then continue end

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
					if Base.getOwner(base) ~= player then return end

					local tool = Pickup.getInventoryTool(player)
					if not tool then return end

					if isSlotOccupied(slot) then return end

					local name = tool.Name
					local rarity = tool:GetAttribute("Rarity")
					local baseIncome = tool:GetAttribute("IncomePerSec")  -- Tool stores BASE income
					local level = tool:GetAttribute("Level") or 1

					local folder = modelFolders[rarity]
					if not folder then return end

					local template = folder:FindFirstChild(name)
					if not template then return end

					local clone = template:Clone()

					if not clone.PrimaryPart then
						warn("[Placement] Missing PrimaryPart:", name)
						return
					end

					clone:SetAttribute("Name", name)
					clone:SetAttribute("Rarity", rarity)
					clone:SetAttribute("Placed", true)
					-- Level, BaseIncome, IncomePerSec are set inside createSlotPrompts

					for _, part in clone:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
							part.CanQuery = false
						end
					end

					local collectButton = slot:FindFirstChild("CollectButton")
					local placementOffset = Vector3.new(0, Config.PlacementYOffset, 0)
					local spawnPos = point.Position + placementOffset

					if collectButton then
						local targetFlat = Vector3.new(
							collectButton.Position.X,
							spawnPos.Y,
							collectButton.Position.Z
						)
						clone:PivotTo(CFrame.lookAt(spawnPos, targetFlat) * CFrame.Angles(0, math.rad(180), 0))
					else
						clone:PivotTo(CFrame.new(spawnPos))
					end

					clone.Parent = slot

					-- Compute current income at this level for billboard display
					local currentIncome = Brainrots.getIncomeAtLevel(baseIncome, rarity, level)

					BrainrotUI.createBillboard(clone, {
						name = name,
						rarity = rarity,
						incomePerSec = currentIncome,
						level = level,
						maxLevel = Brainrots.MaxLevel,
					})

					-- Wire pickup + sell + upgrade prompts via shared helper
					Placement.createSlotPrompts(clone, slot, base, {
						name = name,
						rarity = rarity,
						baseIncome = baseIncome,
						level = level,
					})

					Pickup.removeFromInventory(player, tool)
					tool:Destroy()

					prompt.Enabled = false
					Placement.refreshPrompts(player)

					if onDataChangedCallback then
						onDataChangedCallback(player)
					end

					print(player.Name, "placed", name, "L" .. level)
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

	if not playerBase then return end

	local slots = playerBase:FindFirstChild("Slots")
	if not slots then return end

	for i = 1, Config.MaxSlots do
		local slot = slots:FindFirstChild("Slot" .. i)
		if not slot then continue end

		local point = slot:FindFirstChild("PlacementPoint")
		if not point then continue end

		local prompt = point:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then continue end

		prompt.Enabled = Pickup.isItemEquipped(player) and not isSlotOccupied(slot)
	end
end

return Placement