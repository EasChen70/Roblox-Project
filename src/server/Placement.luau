local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Base = require(game.ServerScriptService.Base)
local Pickup = require(game.ServerScriptService.Pickup)
local BrainrotUI = require(game.ReplicatedStorage.BrainrotUI)

local Placement = {}

local modelsFolder = game:GetService("ServerStorage"):WaitForChild("CommonBrainRotModels")
local bases = game.Workspace.Map.Bases

local function isSlotOccupied(slot)
	for _, child in slot:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Name") then
			return true
		end
	end
	return false
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
			prompt.HoldDuration = Config.PickupHoldDuration
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

				local template = modelsFolder:FindFirstChild(name)
				if not template then return end

				local clone = template:Clone()
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
				local spawnPos = point.Position

				if collectButton then
					local targetFlat = Vector3.new(collectButton.Position.X, spawnPos.Y, collectButton.Position.Z)
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

				-- Pick up prompt on placed brainrot
				local pickupPrompt = Instance.new("ProximityPrompt")
				pickupPrompt.ActionText = "Pick Up"
				pickupPrompt.ObjectText = name
				pickupPrompt.HoldDuration = Config.PickupHoldDuration
				pickupPrompt.MaxActivationDistance = 8
				pickupPrompt.RequiresLineOfSight = false
				pickupPrompt.Parent = clone.PrimaryPart

				pickupPrompt.Triggered:Connect(function(triggerPlayer)
					if Base.getOwner(base) ~= triggerPlayer then return end
					if Pickup.isCarrying(triggerPlayer) then return end

					local success = Pickup.giveItem(
						triggerPlayer,
						clone:GetAttribute("Name"),
						clone:GetAttribute("Rarity"),
						clone:GetAttribute("IncomePerSec")
					)

					if not success then return end

					clone:Destroy()
					Placement.refreshPrompts(triggerPlayer)
					print(triggerPlayer.Name, "picked up", name, "from", slot.Name)
				end)

				Pickup.removeFromInventory(player, tool)
				tool:Destroy()

				prompt.Enabled = false
				Placement.refreshPrompts(player)

				print(player.Name, "placed", name, "on", slot.Name)
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

		local occupied = isSlotOccupied(slot)
		prompt.Enabled = Pickup.isItemEquipped(player) and not occupied
	end
end

return Placement