-- server/Placement.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Base = require(game.ServerScriptService.Base)
local Pickup = require(game.ServerScriptService.Pickup)

local Placement = {}

local modelsFolder = game:GetService("ServerStorage"):WaitForChild("BrainRotModels")
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

				local template = modelsFolder:FindFirstChild(name)
				if not template then return end

				local clone = template:Clone()
				clone:SetAttribute("Name", name)
				clone:SetAttribute("Rarity", rarity)
				clone:SetAttribute("IncomePerSec", incomePerSec)

				for _, part in clone:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
					end
				end

				clone:SetPrimaryPartCFrame(CFrame.new(point.Position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(180), 0))
				clone.Parent = slot

				tool:Destroy()
				Pickup.clearInventory(player)

				prompt.Enabled = false
				Placement.refreshPrompts(player)

				print(player.Name, "placed", name, "on", slot.Name)
			end)
		end
	end
end

function Placement.refreshPrompts(player)
	print("refreshPrompts called for", player.Name)
	
	local playerBase = nil
	for _, base in bases:GetChildren() do
		if Base.getOwner(base) == player then
			playerBase = base
			break
		end
	end

	if not playerBase then
		print("No base found for", player.Name)
		return
	end

	local hasItem = Pickup.getInventoryTool(player) ~= nil
	print("Has item:", hasItem)

	local slots = playerBase:FindFirstChild("Slots")
	if not slots then return end

	for i = 1, Config.MaxSlots do
		local slot = slots:FindFirstChild("Slot" .. i)
		if not slot then continue end

		local point = slot:FindFirstChild("PlacementPoint")
		if not point then continue end

		local prompt = point:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			print("No prompt on", slot.Name)
			continue
		end

		local occupied = isSlotOccupied(slot)
		prompt.Enabled = hasItem and not occupied
		print(slot.Name, "- enabled:", prompt.Enabled, "occupied:", occupied)
	end
end

return Placement