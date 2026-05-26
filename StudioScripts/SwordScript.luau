local Tool = script.Parent
local Handle = Tool.Handle
local SwingSound = Handle:WaitForChild("SwingSound")
-- [[ NEW: Reference the Unsheathe sound ]] --
local EquipSound = Handle:WaitForChild("EquipSound") -- Ensure a sound named 'EquipSound' is in the Handle

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Gamepasses = require(ServerScriptService:WaitForChild("Gamepasses"))
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

local BaseUrl = "rbxassetid://"
local SlashAnim = Instance.new("Animation")
SlashAnim.AnimationId = BaseUrl .. "522635514"
SlashAnim.Parent = Tool

-- [[ GUARD COPIED SETTINGS ]] --
local KNOCKBACK_POWER = 25
local VERTICAL_LAUNCH = 25

local hitList = {} 
local isSwinging = false
local canSwing = true 
local cooldownTime = 3 

-- [[ NEW: Force unequip if holding an unclaimed brainrot ]] --
Tool.Equipped:Connect(function()
	local Character = Tool.Parent
	local player = game.Players:GetPlayerFromCharacter(Character)

	if player and Pickup.isCarrying(player) then
		local Humanoid = Character:FindFirstChildOfClass("Humanoid")
		if Humanoid then
			Humanoid:UnequipTools()
		end
	else
		-- [[ NEW: Only play sound if equip is allowed ]] --
		EquipSound:Play()
	end
end)

Tool.Activated:Connect(function()
	local Character = Tool.Parent
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")

	if not canSwing or isSwinging or not Humanoid then return end

	canSwing = false 
	isSwinging = true
	hitList = {} 
	SwingSound:Play()	

	local swingTrack = Humanoid:LoadAnimation(SlashAnim)
	swingTrack:Play()

	task.wait(0.5) 
	isSwinging = false

	task.wait(cooldownTime - 0.5)
	canSwing = true
end)

Handle.Touched:Connect(function(otherPart)
	if not isSwinging then return end

	local hitChar = otherPart.Parent

	-- [[ NEW: Guard Protection Check ]] --
	if hitChar.Name == "Guard" or hitChar:GetAttribute("IsGuard") then 
		return 
	end
	-- [[ END OF GUARD CHECK ]] --

	if hitChar:GetAttribute("IsInvincible") then return end

	local hitHumanoid = hitChar:FindFirstChild("Humanoid")
	local rootPart = hitChar:FindFirstChild("HumanoidRootPart")
	local myChar = Tool.Parent

	if hitHumanoid and rootPart and hitChar ~= myChar and not hitList[hitChar] and not hitChar:FindFirstChild("StunnedTag") then
		hitList[hitChar] = true 

		-- Prevent instant re-stuns
		local stunTag = Instance.new("BoolValue")
		stunTag.Name = "StunnedTag"
		stunTag.Parent = hitChar

		-- Drop item if holding one
		local player = Players:GetPlayerFromCharacter(hitChar)
		if player then
			Pickup.drop(player)
		end

		-- [[ GUARD KNOCKBACK & STATE LOGIC ]] --
		hitHumanoid.PlatformStand = true 
		hitHumanoid.AutoRotate = false
		hitHumanoid:ChangeState(Enum.HumanoidStateType.FallingDown)

		-- Apply push vectors directly to assembly
		rootPart.CFrame = rootPart.CFrame * CFrame.new(0, 2, 0) 
		local pushDir = (rootPart.Position - Handle.Position).Unit
		rootPart.AssemblyLinearVelocity = (pushDir * KNOCKBACK_POWER) + Vector3.new(0, VERTICAL_LAUNCH, 0)
		rootPart.AssemblyAngularVelocity = Vector3.zero

		-- [[ GUARD RECOVERY LOGIC (Merged with Gamepasses Speed) ]] --
		task.delay(3.0, function()
			if hitChar and hitChar.Parent then
				local tag = hitChar:FindFirstChild("StunnedTag")
				if tag then tag:Destroy() end

				if hitHumanoid then
					hitHumanoid.AutoRotate = true
					hitHumanoid.PlatformStand = false 

					local stunnedPlayer = Players:GetPlayerFromCharacter(hitChar)
					if stunnedPlayer then
						Gamepasses.applyDefaultSpeed(stunnedPlayer, hitHumanoid)
					else
						hitHumanoid.WalkSpeed = 16 -- Fallback if hit target is an NPC
					end

					hitHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					rootPart.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
				end
			end
		end)

		-- Visual feedback (Red flash)
		for _, part in pairs(hitChar:GetChildren()) do
			if part:IsA("BasePart") then
				local oldColor = part.Color
				part.Color = Color3.fromRGB(255, 0, 0)
				task.delay(0.4, function()
					if part then part.Color = oldColor end
				end)
			end
		end
	end
end)