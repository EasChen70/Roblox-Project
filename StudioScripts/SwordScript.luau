local Tool = script.Parent
local Handle = Tool.Handle
local SwingSound = Handle:WaitForChild("SwingSound")
-- [[ NEW: Reference the Unsheathe sound ]] --
local EquipSound = Handle:WaitForChild("EquipSound") -- Ensure a sound named 'EquipSound' is in the Handle

local ServerScriptService = game:GetService("ServerScriptService")
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

local BaseUrl = "rbxassetid://"
local SlashAnim = Instance.new("Animation")
SlashAnim.AnimationId = BaseUrl .. "522635514"
SlashAnim.Parent = Tool

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
	-- This checks if the hit object is named "Guard" or has an attribute called "IsGuard"
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

		local stunTag = Instance.new("BoolValue")
		stunTag.Name = "StunnedTag"
		stunTag.Parent = hitChar

		local knockbackDirection = (rootPart.Position - Handle.Position).Unit
		local attachment = Instance.new("Attachment", rootPart)

		local lv = Instance.new("LinearVelocity", rootPart)
		lv.Attachment0 = attachment
		lv.MaxForce = 2000000 

		lv.VectorVelocity = (knockbackDirection * 25) + Vector3.new(0, 35, 0) 

		local spin = Instance.new("AngularVelocity", rootPart)
		spin.Attachment0 = attachment
		spin.MaxTorque = 2000000
		spin.AngularVelocity = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))

		task.wait(0.12) 
		lv:Destroy()
		spin:Destroy()
		attachment:Destroy()

		hitHumanoid.PlatformStand = true 
		hitHumanoid.JumpPower = 0
		hitHumanoid.WalkSpeed = 0

		local player = game.Players:GetPlayerFromCharacter(hitChar)
		if player then
			pcall(function() rootPart:SetNetworkOwner(player) end)
		end

		task.delay(3, function()
			if hitChar and hitChar.Parent then
				local tag = hitChar:FindFirstChild("StunnedTag")
				if tag then tag:Destroy() end

				if hitHumanoid then
					hitHumanoid.PlatformStand = false
					hitHumanoid.JumpPower = 50 
					hitHumanoid.WalkSpeed = 16 
					hitHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					rootPart.CFrame = rootPart.CFrame * CFrame.new(0, 2, 0)
				end
			end
		end)

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