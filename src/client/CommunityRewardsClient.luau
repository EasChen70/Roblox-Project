local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BaseIdentity = require(ReplicatedStorage.BaseIdentity)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local CommunityRewardsClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOAST_DURATION = 3
local GROUP_PROMPT_SOFT_FAIL_WINDOW = 10

local hasClaimed = false
local myBaseId = nil
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

-- ── Style Helpers ─────────────────────────────────────────────────────────────

local function attachPanelTexture(parent, transparency)
	local texture = Instance.new("ImageLabel")
	texture.Name = "PanelTexture"
	texture.BackgroundTransparency = 1
	texture.Image = "rbxassetid://6927295847"
	texture.Size = UDim2.fromScale(1, 1)
	texture.ScaleType = Enum.ScaleType.Tile
	texture.TileSize = UDim2.fromOffset(24, 24)
	texture.ImageTransparency = transparency
	texture.ZIndex = parent.ZIndex
	texture.Parent = parent

	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		local textureCorner = Instance.new("UICorner")
		textureCorner.CornerRadius = corner.CornerRadius
		textureCorner.Parent = texture
	end
end

local function applyTextSizeConstraint(label, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
end

-- ── Base Logic ────────────────────────────────────────────────────────────────

local function applyAssignedBase(baseId, baseName)
	myBaseId = BaseIdentity.normalizeBaseId(baseId)
	myBaseName = type(baseName) == "string" and baseName or nil
end

local function syncAssignedBaseFromAttributes()
	applyAssignedBase(player:GetAttribute("AssignedBaseId"), player:GetAttribute("AssignedBaseName"))
end

local function baseMatchesMine(baseId, baseName)
	local normalizedBaseId = BaseIdentity.normalizeBaseId(baseId)
	if myBaseId ~= nil and normalizedBaseId ~= nil then
		return myBaseId == normalizedBaseId
	end

	return baseName ~= nil and myBaseName == baseName
end

local function shouldShowClaimUI(baseId, baseName)
	return baseMatchesMine(baseId, baseName) and hasClaimed ~= true and promptRequestPending ~= true
end

local function shouldShowClaimedUI(baseId, baseName)
	return baseMatchesMine(baseId, baseName) and hasClaimed == true
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

-- ── Toasts ────────────────────────────────────────────────────────────────────

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

-- ── 3D Pedestal Syncing ───────────────────────────────────────────────────────

local function resolvePedestalBaseIdentity(base, prompt, billboard, claimedBillboard)
	local baseId = BaseIdentity.normalizeBaseId(
		(prompt and prompt:GetAttribute("CommunityBaseId"))
			or (billboard and billboard:GetAttribute("CommunityBaseId"))
			or (claimedBillboard and claimedBillboard:GetAttribute("CommunityBaseId"))
	)
	local baseName = (prompt and prompt:GetAttribute("CommunityBaseName"))
		or (billboard and billboard:GetAttribute("CommunityBaseName"))
		or (claimedBillboard and claimedBillboard:GetAttribute("CommunityBaseName"))

	if baseId == nil then
		baseId = BaseIdentity.getResolvedBaseId(base)
	end

	if type(baseName) ~= "string" then
		baseName = base.Name
	end

	return baseId, baseName
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
			local baseId, baseName = resolvePedestalBaseIdentity(base, prompt, billboard, claimedBillboard)
			callback(baseId, baseName, prompt, billboard, claimedBillboard)
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
	forEachPedestal(function(baseId, baseName, prompt, billboard, claimedBillboard)
		local showClaim = shouldShowClaimUI(baseId, baseName)
		local showClaimed = shouldShowClaimedUI(baseId, baseName)

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

-- ── Modal Actions & UI ────────────────────────────────────────────────────────

local function setPrimaryButtonState(button, isEnabled, text)
	if not button then
		return
	end

	button.Active = isEnabled
	button.AutoButtonColor = isEnabled
	button.Text = text
	-- Uses CannonShop green when active, grey when disabled
	button.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(150, 150, 150)
end

local function attemptClaim()
	if promptRequestPending then
		return
	end

	local button = modalGui and modalGui:FindFirstChild("Backdrop")
	local main = button and button:FindFirstChild("Main")
	local row = main and main:FindFirstChild("UpgradeRow")
	local cta = row and row:FindFirstChild("JoinButton")

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

	-- Main Frame (Matches CannonShop main)
	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.7, 0.6)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	main.Parent = backdrop

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 15)
	mainCorner.Parent = main

	attachPanelTexture(main, 0.88)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.35
	aspect.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Thickness = 3
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = main

	-- Header (Matches CannonShop purple header)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.22)
	header.BackgroundColor3 = Color3.fromRGB(75, 0, 130)
	header.BorderSizePixel = 0
	header.Parent = main

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 15)
	headerCorner.Parent = header

	attachPanelTexture(header, 0.75)

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = Color3.fromRGB(255, 255, 255)
	headerStroke.Thickness = 3
	headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headerStroke.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.7, 0.7)
	title.Position = UDim2.fromScale(0.05, 0.17)
	title.BackgroundTransparency = 1
	title.Text = "FREE REWARD"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 4
	titleStroke.Parent = title

	-- Close Button (Matches CannonShop Close Btn)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromScale(0.09, 0.65)
	closeBtn.Position = UDim2.fromScale(0.97, 0.17)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
	closeBtn.Font = Enum.Font.DenkOne
	closeBtn.TextScaled = true
	closeBtn.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	attachPanelTexture(closeBtn, 0.76)

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(255, 255, 255)
	closeStroke.Thickness = 3
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeModal)

	-- Info Row (Matches CannonShop UpgradeRow)
	local row = Instance.new("Frame")
	row.Name = "UpgradeRow"
	row.Size = UDim2.new(0.92, 0, 0.55, 0)
	row.Position = UDim2.fromScale(0.5, 0.6)
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Parent = main

	attachPanelTexture(row, 0.1)

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(255, 255, 255)
	rowStroke.Thickness = 2.5
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rowStroke.Parent = row

	local body = Instance.new("TextLabel")
	body.Size = UDim2.fromScale(0.6, 0.8)
	body.Position = UDim2.new(0, 15, 0.5, 0)
	body.AnchorPoint = Vector2.new(0, 0.5)
	body.BackgroundTransparency = 1
	body.Text = "1. Like the Game!\n2. Join the Group!"
	body.TextColor3 = Color3.fromRGB(255, 255, 255)
	body.Font = Enum.Font.DenkOne
	body.TextScaled = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.Parent = row

	local lStroke = Instance.new("UIStroke")
	lStroke.Thickness = 3
	lStroke.Color = Color3.fromRGB(0, 0, 0)
	lStroke.Parent = body

	-- Claim Button (Matches CannonShop Buy Button)
	local joinButton = Instance.new("TextButton")
	joinButton.Name = "JoinButton"
	joinButton.Size = UDim2.fromScale(0.3, 0.6)
	joinButton.Position = UDim2.fromScale(0.95, 0.5)
	joinButton.AnchorPoint = Vector2.new(1, 0.5)
	joinButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	joinButton.Text = "CLAIM"
	joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	joinButton.Font = Enum.Font.DenkOne
	joinButton.TextScaled = true
	joinButton.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = joinButton

	local bStroke = Instance.new("UIStroke")
	bStroke.Thickness = 3
	bStroke.Color = Color3.fromRGB(255, 255, 255)
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = joinButton

	joinButton.MouseButton1Click:Connect(attemptClaim)
end

-- ── Setup & Listeners ─────────────────────────────────────────────────────────

local function handleClaimResult(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "stateSync" then
		applyAssignedBase(payload.baseId, payload.baseName)
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

	syncAssignedBaseFromAttributes()

	Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
		syncAssignedBaseFromAttributes()
		if myBaseName == nil and type(baseName) == "string" then
			myBaseName = baseName
		end
		refreshClaimUI()
		Remotes.CommunityClaimRequest:FireServer("sync")
	end)

	Remotes.CommunityClaimResult.OnClientEvent:Connect(handleClaimResult)

	player:GetAttributeChangedSignal("AssignedBaseId"):Connect(function()
		syncAssignedBaseFromAttributes()
		refreshClaimUI()
	end)

	player:GetAttributeChangedSignal("AssignedBaseName"):Connect(function()
		syncAssignedBaseFromAttributes()
		refreshClaimUI()
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute("CommunityClaimPrompt") ~= true then
			return
		end

		local baseId = prompt:GetAttribute("CommunityBaseId")
		local baseName = prompt:GetAttribute("CommunityBaseName")
		prompt.Enabled = shouldShowClaimUI(baseId, baseName) and getServerActive(prompt)
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