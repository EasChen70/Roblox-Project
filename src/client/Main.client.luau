--Main.client.luau
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BaseIdentity = require(ReplicatedStorage.BaseIdentity)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local CannonShopClient = require(script.Parent.CannonShopClient)
local CommunityRewardsClient = require(script.Parent.CommunityRewardsClient)
local GamepassShopClient = require(script.Parent.GamepassShopClient)
local GiftingClient = require(script.Parent.GiftingClient)
local OfflineRewardsClient = require(script.Parent.OfflineRewardsClient)
local SellShopClient = require(script.Parent.SellShopClient)
local TutorialClient = require(script.Parent.TutorialClient)
local player = Players.LocalPlayer
local myBaseId = nil
local myBaseName = nil
local cachedControls = nil
local movementRecoveryToken = 0
local MOVEMENT_RECOVERY_DELAYS = { 0, 0.15, 0.5 }
local zeroVector = Vector3.new(0, 0, 0)

local function getLocalControls(refreshCache)
	if refreshCache then
		cachedControls = nil
	end

	if cachedControls then
		return cachedControls
	end

	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end

	local ok, moduleOrErr = pcall(require, playerModule)
	if not ok or type(moduleOrErr) ~= "table" or type(moduleOrErr.GetControls) ~= "function" then
		return nil
	end

	local controlsOk, controls = pcall(function()
		return moduleOrErr:GetControls()
	end)
	if not controlsOk then
		return nil
	end

	cachedControls = controls
	return cachedControls
end

local function forceEnableLocalControls(refreshCache, bounceControls)
	local controls = getLocalControls(refreshCache)
	if bounceControls and controls and type(controls.Disable) == "function" then
		pcall(function()
			controls:Disable()
		end)
		task.wait()
		controls = getLocalControls(true)
	end

	if controls and type(controls.Enable) == "function" then
		pcall(function()
			controls:Enable()
		end)
	end
end

-- StarterPlayerScripts persist across respawns, so this can override stale
-- immobilized state left behind by character-local scripts from the old body.
local function recoverCharacterMovement(character)
	cachedControls = nil
	movementRecoveryToken += 1
	local token = movementRecoveryToken

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then
			return
		end

		for passIndex, delaySeconds in ipairs(MOVEMENT_RECOVERY_DELAYS) do
			local scheduledPassIndex = passIndex
			local scheduledDelaySeconds = delaySeconds
			task.delay(scheduledDelaySeconds, function()
				if token ~= movementRecoveryToken or player.Character ~= character or not character.Parent or not humanoid.Parent then
					return
				end

				local isFirstPass = scheduledPassIndex == 1
				local isFinalPass = scheduledPassIndex == #MOVEMENT_RECOVERY_DELAYS

				forceEnableLocalControls(true, isFirstPass)
				humanoid.PlatformStand = false
				humanoid.AutoRotate = true
				humanoid.Jump = false
				humanoid.Sit = false
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
				humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)

				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					rootPart.Anchored = false
					if isFirstPass then
						rootPart.AssemblyLinearVelocity = zeroVector
						rootPart.AssemblyAngularVelocity = zeroVector
					end
				end

				if isFirstPass then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				elseif isFinalPass then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end)
		end
	end)
end

local function applyAssignedBase(baseId, baseName)
	myBaseId = BaseIdentity.normalizeBaseId(baseId)
	myBaseName = type(baseName) == "string" and baseName or nil
end

local function syncAssignedBaseFromAttributes()
	applyAssignedBase(player:GetAttribute("AssignedBaseId"), player:GetAttribute("AssignedBaseName"))
end

local function findOwningBase(instance)
	local current = instance
	while current and current ~= game.Workspace do
		if current.Parent and current.Parent.Name == "Bases" then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function baseMatchesMine(base)
	local baseId = BaseIdentity.getResolvedBaseId(base)
	if myBaseId ~= nil and baseId ~= nil then
		return myBaseId == baseId
	end

	return myBaseName ~= nil and base.Name == myBaseName
end

local function findAssignedBase()
	local bases = game.Workspace.Map.Bases
	local myBase = myBaseId ~= nil and BaseIdentity.findBaseById(bases, myBaseId) or nil
	if not myBase and myBaseName then
		myBase = bases:FindFirstChild(myBaseName)
	end
	return myBase
end

local function clearYourBaseIndicators()
	local bases = game.Workspace.Map.Bases
	for _, base in ipairs(bases:GetChildren()) do
		local sign = base:FindFirstChild("Sign")
		local indicator = sign and sign:FindFirstChild("YourBaseIndicator")
		if indicator then
			indicator:Destroy()
		end
	end
end

local function createYourBaseIndicator(base)
	if not base then
		return
	end

	local sign = base:WaitForChild("Sign", 5)
	if not sign then
		return
	end

	if sign:FindFirstChild("YourBaseIndicator") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "YourBaseIndicator"
	billboard.Size = UDim2.fromScale(10, 3)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	billboard.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Text = "YOUR BASE"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 0.4)
	arrow.Position = UDim2.fromScale(0, 0.6)
	arrow.Font = Enum.Font.LuckiestGuy
	arrow.TextScaled = true
	arrow.Parent = billboard

	local arrowStroke = Instance.new("UIStroke")
	arrowStroke.Color = Color3.fromRGB(0, 0, 0)
	arrowStroke.Thickness = 3
	arrowStroke.Parent = arrow
end

local function refreshYourBaseIndicator()
	clearYourBaseIndicators()
	createYourBaseIndicator(findAssignedBase())
end

local function resolveAssignedBaseFromSigns()
	if myBaseId ~= nil or myBaseName ~= nil then
		return
	end

	local bases = game.Workspace.Map.Bases
	for _, base in ipairs(bases:GetChildren()) do
		local sign = base:FindFirstChild("Sign")
		if sign and sign:FindFirstChild("BaseSign") then
			local bg = sign.BaseSign:FindFirstChild("Background")
			if bg then
				local info = bg:FindFirstChild("Info")
				if info then
					local nameLabel = info:FindFirstChild("PlayerName")
					if nameLabel and nameLabel.Text == player.Name then
						applyAssignedBase(BaseIdentity.getResolvedBaseId(base), base.Name)
						return
					end
				end
			end
		end
	end
end

syncAssignedBaseFromAttributes()

Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
	syncAssignedBaseFromAttributes()
	if myBaseName == nil and type(baseName) == "string" then
		myBaseName = baseName
	end
	refreshYourBaseIndicator()
end)

player:GetAttributeChangedSignal("AssignedBaseId"):Connect(function()
	syncAssignedBaseFromAttributes()
	refreshYourBaseIndicator()
end)

player:GetAttributeChangedSignal("AssignedBaseName"):Connect(function()
	syncAssignedBaseFromAttributes()
	refreshYourBaseIndicator()
end)

task.delay(2, function()
	resolveAssignedBaseFromSigns()
	refreshYourBaseIndicator()
end)

player.CharacterAdded:Connect(recoverCharacterMovement)
if player.Character then
	recoverCharacterMovement(player.Character)
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.ActionText ~= "Pick Up" and prompt.ActionText ~= "Sell" then
		return
	end

	local base = findOwningBase(prompt)
	if base and not baseMatchesMine(base) then
		prompt.Enabled = false
	end
end)

Remotes.CollectSlot.OnClientEvent:Connect(function()
	local audio = game.Workspace.Map:FindFirstChild("Audio")
	if not audio then
		return
	end
	local cashSound = audio:FindFirstChild("cashEffect")
	if not cashSound then
		return
	end

	local sfx = cashSound:Clone()
	sfx.Parent = player.PlayerGui
	sfx:Play()
	sfx.Ended:Once(function()
		sfx:Destroy()
	end)
end)

local dropButton = nil

local function showDropButton()
	if dropButton then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "DropButtonGui"
	screen.ResetOnSpawn = false
	screen.Parent = player.PlayerGui

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(0.15, 0.08)
	btn.Position = UDim2.fromScale(0.5, 0.72)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	btn.Text = "Drop"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.DenkOne
	btn.TextScaled = true
	btn.AutoButtonColor = true -- Provides built-in click feedback
	btn.Parent = screen

	-- Texture Overlay
	local texture = Instance.new("ImageLabel")
	texture.Name = "ButtonTexture"
	texture.BackgroundTransparency = 1
	texture.Image = "rbxassetid://6927295847"
	texture.Size = UDim2.fromScale(1, 1)
	texture.ScaleType = Enum.ScaleType.Stretch -- Ensures it fills the whole button
	texture.ImageTransparency = 0.4 -- Lower this if you want the texture stronger
	texture.ZIndex = 1 -- Sits above the background but below the text
	texture.Parent = btn

	-- Important: Sync the corner with the button
	Instance.new("UICorner", texture).CornerRadius = UDim.new(0, 10)

	-- Constraints
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.66
	aspect.Parent = btn

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

	-- White button border (Placed on a high ZIndex to stay visible)
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(255, 255, 255)
	buttonStroke.Thickness = 2
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = btn

	-- Black text outline
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if Remotes and Remotes.DropBrainrot then
			Remotes.DropBrainrot:FireServer()
		end
	end)

	dropButton = screen
end

local function hideDropButton()
	if dropButton then
		dropButton:Destroy()
		dropButton = nil
	end
end

Remotes.GrabStateChanged.OnClientEvent:Connect(function(isCarrying)
	if isCarrying then
		showDropButton()
	else
		hideDropButton()
	end
end)

Remotes.UpgradeSound.OnClientEvent:Connect(function()
	local sfx = Instance.new("Sound")
	sfx.SoundId = Config.UpgradeSoundId
	sfx.Volume = 1
	sfx.Parent = player.PlayerGui
	sfx:Play()
	sfx.Ended:Once(function()
		sfx:Destroy()
	end)
end)
Remotes.MaxLevelGlow.OnClientEvent:Connect(function(model)
	if not model or not model.Parent then
		return
	end

	local existing = model:FindFirstChild("MaxGlow")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "MaxGlow"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 215, 0)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	task.spawn(function()
		while model.Parent do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local primaryPart = model.PrimaryPart or model:FindFirstChildOfClass("BasePart")
			if hrp and primaryPart then
				local dist = (hrp.Position - primaryPart.Position).Magnitude
				if dist < 80 then
					highlight.Parent = model
				else
					highlight.Parent = nil
				end
			end
			task.wait(0.5)
		end
		highlight:Destroy()
	end)
end)
OfflineRewardsClient.start()
CannonShopClient.start()
CommunityRewardsClient.start()
GamepassShopClient.start()
GiftingClient.start()
SellShopClient.start()
TutorialClient.start()
