local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local CommunityRewardsClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOAST_DURATION = 3
local GROUP_PROMPT_SOFT_FAIL_WINDOW = 10

local hasClaimed = false
local myBaseName = nil
local started = false
local promptRequestPending = false
local modalGui = nil
local toastGui = nil
local activeToastFrame = nil
local activeToastToken = 0
local lastPromptStatus = nil
local lastPromptAt = 0
local claimPulseTweens = {}

local function shouldShowClaimUI(baseName)
	return baseName ~= nil and myBaseName == baseName and hasClaimed ~= true and promptRequestPending ~= true
end

local function shouldShowClaimedUI(baseName)
	return baseName ~= nil and myBaseName == baseName and hasClaimed == true
end

local function getServerActive(instance)
	return instance and instance:GetAttribute("CommunityClaimActive") == true
end

local function getServerClaimedActive(instance)
	return instance and instance:GetAttribute("CommunityClaimedActive") == true
end

local function closeModal()
	if modalGui then
		modalGui:Destroy()
		modalGui = nil
	end
end

local function ensureToastGui()
	if toastGui then
		return toastGui
	end

	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "CommunityRewardToastGui"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 30
	toastGui.Parent = playerGui
	return toastGui
end

local function applyTextSizeConstraint(label, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
end

local function showToast(message, tone)
	local screen = ensureToastGui()
	activeToastToken += 1
	local toastToken = activeToastToken

	if activeToastFrame then
		activeToastFrame:Destroy()
		activeToastFrame = nil
	end

	local bgColor = Color3.fromRGB(45, 45, 55)
	if tone == "success" then
		bgColor = Color3.fromRGB(55, 140, 75)
	elseif tone == "error" then
		bgColor = Color3.fromRGB(170, 65, 65)
	end

	local frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.Size = UDim2.fromScale(0.42, 0.09)
	frame.Position = UDim2.fromScale(0.5, 0.1)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = bgColor
	frame.BackgroundTransparency = 0.05
	frame.Parent = screen
	activeToastFrame = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.DenkOne
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = frame
	applyTextSizeConstraint(label, 14, 22)

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.Parent = label

	task.delay(TOAST_DURATION, function()
		if activeToastToken ~= toastToken then
			return
		end
		if activeToastFrame then
			activeToastFrame:Destroy()
			activeToastFrame = nil
		end
	end)
end

local function forEachPedestal(callback)
	local map = Workspace:FindFirstChild("Map")
	local basesFolder = map and map:FindFirstChild("Bases")
	if not basesFolder then
		return
	end

	for _, base in ipairs(basesFolder:GetChildren()) do
		local pedestal = base:FindFirstChild(Config.PedestalModelName)
		if pedestal then
			local prompt = pedestal:FindFirstChild("CommunityClaimPrompt", true)
			local billboard = pedestal:FindFirstChild("ClaimBillboard", true)
			local claimedBillboard = pedestal:FindFirstChild("ClaimedBillboard", true)
			callback(base.Name, prompt, billboard, claimedBillboard)
		end
	end
end

local function ensureClaimPulse(billboard)
	if not billboard or claimPulseTweens[billboard] then
		return
	end

	local container = billboard:FindFirstChild("Container")
	local claimText = container and container:FindFirstChild("ClaimText")
	if not claimText then
		return
	end

	local scale = claimText:FindFirstChild("PulseScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PulseScale"
		scale.Parent = claimText
	end

	local tween = TweenService:Create(
		scale,
		TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.04 }
	)
	tween:Play()
	claimPulseTweens[billboard] = tween

	billboard.Destroying:Connect(function()
		local activeTween = claimPulseTweens[billboard]
		if activeTween then
			activeTween:Cancel()
			claimPulseTweens[billboard] = nil
		end
	end)
end

local function refreshClaimUI()
	forEachPedestal(function(baseName, prompt, billboard, claimedBillboard)
		local showClaim = shouldShowClaimUI(baseName)
		local showClaimed = shouldShowClaimedUI(baseName)

		if prompt then
			prompt.Enabled = showClaim and getServerActive(prompt)
		end

		if billboard then
			billboard.Enabled = showClaim and getServerActive(billboard)
			if billboard.Enabled then
				ensureClaimPulse(billboard)
			end
		end

		if claimedBillboard then
			claimedBillboard.Enabled = showClaimed and getServerClaimedActive(claimedBillboard)
		end
	end)
end

local function createModalButton(parent, text, size, position, color, minTextSize, maxTextSize)
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.DenkOne
	button.TextScaled = true
	button.Parent = parent
	if minTextSize and maxTextSize then
		applyTextSizeConstraint(button, minTextSize, maxTextSize)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(45, 45, 55)
	stroke.Thickness = 2
	stroke.Parent = button

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 1
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = button

	return button
end

local function setPrimaryButtonState(button, isEnabled, text)
	if not button then
		return
	end

	button.Active = isEnabled
	button.AutoButtonColor = isEnabled
	button.Text = text
	button.BackgroundColor3 = isEnabled and Color3.fromRGB(75, 0, 130) or Color3.fromRGB(70, 70, 70)
end

local function attemptClaim()
	if promptRequestPending then
		return
	end

	local button = modalGui and modalGui:FindFirstChild("Backdrop")
	local panel = button and button:FindFirstChild("Panel")
	local cta = panel and panel:FindFirstChild("JoinButton")
	setPrimaryButtonState(cta, false, "OPENING...")

	local success, result = pcall(function()
		return GroupService:PromptJoinAsync(Config.CommunityGroupId)
	end)

	if not success then
		closeModal()
		showToast("Couldn't open the group prompt. Try again.", "error")
		refreshClaimUI()
		return
	end

	lastPromptStatus = result
	lastPromptAt = tick()
	promptRequestPending = true
	closeModal()
	refreshClaimUI()
	Remotes.CommunityClaimRequest:FireServer()
end

local function openModal()
	if modalGui or hasClaimed or promptRequestPending then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "CommunityClaimGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 25
	screen.Parent = playerGui
	modalGui = screen

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screen
	backdrop.MouseButton1Click:Connect(closeModal)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(0.52, 0.46)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Active = true
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.35
	aspect.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 255, 255)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, 0.2)
	header.BackgroundColor3 = Color3.fromRGB(75, 0, 130)
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 16)
	headerCorner.Parent = header

	local headerMask = Instance.new("Frame")
	headerMask.Size = UDim2.fromScale(1, 0.32)
	headerMask.Position = UDim2.fromScale(0, 0.68)
	headerMask.BorderSizePixel = 0
	headerMask.BackgroundColor3 = Color3.fromRGB(75, 0, 130)
	headerMask.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.8, 0.56)
	title.Position = UDim2.fromScale(0.06, 0.2)
	title.BackgroundTransparency = 1
	title.Text = "Free Community Reward!"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	applyTextSizeConstraint(title, 22, 34)

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 1
	titleStroke.Parent = title

	local closeButton = createModalButton(
		panel,
		"X",
		UDim2.fromScale(0.1, 0.12),
		UDim2.fromScale(0.94, 0.04),
		Color3.fromRGB(180, 55, 55),
		14,
		24
	)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.MouseButton1Click:Connect(closeModal)

	local body = Instance.new("TextLabel")
	body.Size = UDim2.fromScale(0.84, 0.26)
	body.Position = UDim2.fromScale(0.5, 0.38)
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.BackgroundTransparency = 1
	body.Text = "1. Like the Game!\n2. Join the Group!"
	body.TextColor3 = Color3.fromRGB(255, 255, 255)
	body.Font = Enum.Font.DenkOne
	body.TextScaled = true
	body.TextWrapped = true
	body.Parent = panel
	applyTextSizeConstraint(body, 16, 24)

	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = Color3.fromRGB(0, 0, 0)
	bodyStroke.Thickness = 1
	bodyStroke.Parent = body

	local joinButton = createModalButton(
		panel,
		"Claim",
		UDim2.fromScale(0.78, 0.14),
		UDim2.fromScale(0.5, 0.7),
		Color3.fromRGB(75, 0, 130),
		16,
		24
	)
	joinButton.Name = "JoinButton"
	joinButton.MouseButton1Click:Connect(attemptClaim)
end

local function handleClaimResult(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "stateSync" then
		if payload.baseName then
			myBaseName = payload.baseName
		end
		hasClaimed = payload.claimed == true
		if hasClaimed then
			closeModal()
		end
		refreshClaimUI()
		return
	end

	if payload.kind == "openModal" then
		openModal()
		refreshClaimUI()
		return
	end

	if payload.kind ~= "claimResult" then
		return
	end

	promptRequestPending = false
	closeModal()

	if payload.success == true then
		hasClaimed = true
		showToast("Tung Tung Sahur claimed!", "success")
		refreshClaimUI()
		return
	end

	local reason = payload.reason
	if reason == "not_in_group" then
		local recentPrompt = tick() - lastPromptAt <= GROUP_PROMPT_SOFT_FAIL_WINDOW
		if recentPrompt and (
			lastPromptStatus == Enum.GroupMembershipStatus.Joined
			or lastPromptStatus == Enum.GroupMembershipStatus.JoinRequestPending
		) then
			showToast("Membership verification may take a moment. Try again in a few seconds.", "error")
		else
			showToast("Join the group first, then try again.", "error")
		end
	elseif reason == "verification_error" then
		showToast("Couldn't verify membership. Try again.", "error")
	elseif reason == "inventory_full" then
		showToast("Inventory full. Sell or place a brainrot, then try again.", "error")
	elseif reason == "too_far" then
		showToast("Walk up to the pedestal and try again.", "error")
	elseif reason == "already_claimed" then
		hasClaimed = true
		showToast("You already claimed this reward.", "error")
	elseif reason == "reward_unavailable" then
		showToast("Reward unavailable. Try again.", "error")
	else
		showToast("Try again in a moment.", "error")
	end

	refreshClaimUI()
end

function CommunityRewardsClient.start()
	if started then
		return
	end
	started = true

	Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
		myBaseName = baseName
		refreshClaimUI()
		Remotes.CommunityClaimRequest:FireServer("sync")
	end)

	Remotes.CommunityClaimResult.OnClientEvent:Connect(handleClaimResult)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute("CommunityClaimPrompt") ~= true then
			return
		end

		local baseName = prompt:GetAttribute("CommunityBaseName")
		prompt.Enabled = shouldShowClaimUI(baseName) and getServerActive(prompt)
	end)

	player.CharacterAdded:Connect(function()
		task.delay(1, refreshClaimUI)
	end)

	Remotes.CommunityClaimRequest:FireServer("sync")
	task.delay(2, refreshClaimUI)

	task.spawn(function()
		while true do
			refreshClaimUI()
			task.wait(1)
		end
	end)
end

return CommunityRewardsClient
