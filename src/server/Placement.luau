local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Base = require(game.ServerScriptService.Base)
local Pickup = require(game.ServerScriptService.Pickup)
local BrainrotUI = require(game.ReplicatedStorage.BrainrotUI)

local Placement = {}

local ServerStorage = game:GetService("ServerStorage")

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
}

local bases = game.Workspace.Map.Bases

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
				if Base.getOwner(base) ~= player then return end

				local tool = Pickup.getInventoryTool(player)
				if not tool then return end

				if isSlotOccupied(slot) then return end

				local name = tool.Name
				local rarity = tool:GetAttribute("Rarity")
				local incomePerSec = tool:GetAttribute("IncomePerSec")

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
				clone:SetAttribute("IncomePerSec", incomePerSec)
				clone:SetAttribute("Placed", true)

				for _, part in clone:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
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

				BrainrotUI.createBillboard(clone, {
					name = name,
					rarity = rarity,
					incomePerSec = incomePerSec,
				})

				-- PICKUP
				local pickupPrompt = Instance.new("ProximityPrompt")
				pickupPrompt.ActionText = "Pick Up"
				pickupPrompt.ObjectText = name
				pickupPrompt.HoldDuration = Config.PickupHoldDuration
				pickupPrompt.Parent = createPromptAttachment(clone.PrimaryPart, "PickupAttachment", 2.5)

				pickupPrompt.Triggered:Connect(function(triggerPlayer)
					if Base.getOwner(base) ~= triggerPlayer then return end
					if Pickup.isCarrying(triggerPlayer) then return end

					local success = Pickup.giveItem(triggerPlayer, name, rarity, incomePerSec)
					if not success then return end

					clone:Destroy()

					if onDataChangedCallback then
						onDataChangedCallback(triggerPlayer)
					end

					Placement.refreshPrompts(triggerPlayer)
				end)

				-- SELL
				local sellPrompt = Instance.new("ProximityPrompt")
				sellPrompt.ActionText = "Sell"
				sellPrompt.ObjectText = "$" .. (incomePerSec * 10)
				sellPrompt.HoldDuration = Config.PickupHoldDuration + 0.05
				sellPrompt.Parent = createPromptAttachment(clone.PrimaryPart, "SellAttachment", 6)

				sellPrompt.Triggered:Connect(function(triggerPlayer)
					if Base.getOwner(base) ~= triggerPlayer then return end

					local sellValue = incomePerSec * 10
					local stats = triggerPlayer:FindFirstChild("leaderstats")
					if stats then
						local money = stats:FindFirstChild("Money")
						if money then
							money.Value += sellValue
						end
					end

					slot:SetAttribute("AccumulatedCash", 0)
					clone:Destroy()

					if onDataChangedCallback then
						onDataChangedCallback(triggerPlayer)
					end

					Placement.refreshPrompts(triggerPlayer)
				end)

				Pickup.removeFromInventory(player, tool)
				tool:Destroy()

				prompt.Enabled = false
				Placement.refreshPrompts(player)

				if onDataChangedCallback then
					onDataChangedCallback(player)
				end

				print(player.Name, "placed", name)
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