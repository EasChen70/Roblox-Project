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

		-- Get base center for facing calculation
		local platform = base:FindFirstChild("Platform")

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

				-- Face toward base center, with 180 flip for model's forward axis
                local collectButton = slot:FindFirstChild("CollectButton")
                local spawnPos = point.Position

                if collectButton then
                    local targetFlat = Vector3.new(collectButton.Position.X, spawnPos.Y, collectButton.Position.Z)
                    clone:PivotTo(CFrame.lookAt(spawnPos, targetFlat))
                else
                    clone:PivotTo(CFrame.new(spawnPos))
                end

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