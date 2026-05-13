local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Remotes)

local GiftingClient = {}

local TOAST_DURATION = 3
local PROMPT_REFRESH_INTERVAL = 0.35

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local started = false
local activeOutgoingRequestId = nil
local activeIncomingRequestId = nil
local modalGui = nil
local modalRequestId = nil
local toastGui = nil
local activeToastFrame = nil
local activeToastToken = 0

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

local function constrainText(label, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
end

local function createTextStroke(parent, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function ensureToastGui()
	if toastGui then
		return toastGui
	end

	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "GiftToastGui"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 31
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
	constrainText(label, 14, 22)
	createTextStroke(label, 2)

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

local function getEquippedGiftTool()
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("BrainrotTool") == true and child:GetAttribute("GiftReserved") ~= true then
			return child
		end
	end

	return nil
end

local function hasEquippedGiftTool()
	return getEquippedGiftTool() ~= nil
end

local function isGiftPrompt(prompt)
	return prompt and prompt:GetAttribute("GiftPrompt") == true
end

local function shouldShowGiftPrompt(prompt)
	if not isGiftPrompt(prompt) then
		return false
	end

	local targetUserId = prompt:GetAttribute("GiftTargetUserId")
	if targetUserId == player.UserId then
		return false
	end
	if activeOutgoingRequestId ~= nil then
		return false
	end

	return hasEquippedGiftTool()
end

local function refreshGiftPrompts()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("GiftPrompt") == true then
			descendant.Enabled = shouldShowGiftPrompt(descendant)
		end
	end
end

local function closeModal()
	if modalGui then
		modalGui:Destroy()
		modalGui = nil
	end
	modalRequestId = nil
end

local function formatMutation(mutation)
	if mutation == "Gold" or mutation == "Diamond" then
		return mutation
	end
	return "Normal"
end

local function formatItemSummary(payload)
	local rarity = payload.itemRarity or "Unknown"
	local level = payload.itemLevel or 1
	local mutation = formatMutation(payload.itemMutation or "None")
	return string.format("%s  |  %s  |  L%d", rarity, mutation, level)
end

local function sendGiftDecision(requestId, accepted)
	if type(requestId) ~= "string" then
		return
	end

	Remotes.GiftDecision:FireServer({
		requestId = requestId,
		accepted = accepted == true,
	})
end

local function openIncomingRequest(payload)
	closeModal()

	local requestId = payload.requestId
	if type(requestId) ~= "string" then
		return
	end

	local timeoutSeconds = math.max(1, math.floor(payload.timeoutSeconds or 10))

	local screen = Instance.new("ScreenGui")
	screen.Name = "GiftRequestGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 27
	screen.Parent = playerGui
	modalGui = screen
	modalRequestId = requestId

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screen

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.68, 0.54)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
	main.BackgroundTransparency = 0.04
	main.BorderSizePixel = 0
	main.Parent = screen

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = main

	attachPanelTexture(main, 0.88)

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Thickness = 4
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = main

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.34
	aspect.Parent = main

	local mainScale = Instance.new("UIScale")
	mainScale.Scale = 0.92
	mainScale.Parent = main

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.18)
	header.BackgroundColor3 = Color3.fromRGB(38, 108, 74)
	header.BorderSizePixel = 0
	header.Parent = main

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 16)
	headerCorner.Parent = header

	attachPanelTexture(header, 0.75)

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = Color3.fromRGB(255, 255, 255)
	headerStroke.Thickness = 3
	headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headerStroke.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.7, 0.58)
	title.Position = UDim2.fromScale(0.05, 0.18)
	title.BackgroundTransparency = 1
	title.Text = "GIFT REQUEST"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	constrainText(title, 18, 34)
	createTextStroke(title, 4)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromScale(0.09, 0.64)
	closeButton.Position = UDim2.fromScale(0.97, 0.18)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 90, 90)
	closeButton.Font = Enum.Font.DenkOne
	closeButton.TextScaled = true
	closeButton.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(255, 255, 255)
	closeStroke.Thickness = 3
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = closeButton
	createTextStroke(closeButton, 2)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(0.9, 0.52)
	body.Position = UDim2.fromScale(0.5, 0.52)
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.BackgroundColor3 = Color3.fromRGB(54, 58, 56)
	body.BackgroundTransparency = 0.08
	body.BorderSizePixel = 0
	body.Parent = main

	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 12)
	bodyCorner.Parent = body

	attachPanelTexture(body, 0.12)

	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = Color3.fromRGB(255, 255, 255)
	bodyStroke.Thickness = 2.5
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bodyStroke.Parent = body

	local senderLabel = Instance.new("TextLabel")
	senderLabel.Name = "Sender"
	senderLabel.Size = UDim2.fromScale(0.84, 0.2)
	senderLabel.Position = UDim2.fromScale(0.5, 0.18)
	senderLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	senderLabel.BackgroundTransparency = 1
	senderLabel.Text = string.format("%s wants to gift you:", payload.senderName or "A player")
	senderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	senderLabel.Font = Enum.Font.DenkOne
	senderLabel.TextScaled = true
	senderLabel.TextWrapped = true
	senderLabel.Parent = body
	constrainText(senderLabel, 16, 28)
	createTextStroke(senderLabel, 3)

	local itemLabel = Instance.new("TextLabel")
	itemLabel.Name = "Item"
	itemLabel.Size = UDim2.fromScale(0.84, 0.22)
	itemLabel.Position = UDim2.fromScale(0.5, 0.42)
	itemLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	itemLabel.BackgroundTransparency = 1
	itemLabel.Text = payload.itemName or "Brainrot"
	itemLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
	itemLabel.Font = Enum.Font.DenkOne
	itemLabel.TextScaled = true
	itemLabel.TextWrapped = true
	itemLabel.Parent = body
	constrainText(itemLabel, 22, 38)
	createTextStroke(itemLabel, 4)

	local detailsLabel = Instance.new("TextLabel")
	detailsLabel.Name = "Details"
	detailsLabel.Size = UDim2.fromScale(0.84, 0.15)
	detailsLabel.Position = UDim2.fromScale(0.5, 0.62)
	detailsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	detailsLabel.BackgroundTransparency = 1
	detailsLabel.Text = formatItemSummary(payload)
	detailsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	detailsLabel.Font = Enum.Font.DenkOne
	detailsLabel.TextScaled = true
	detailsLabel.TextWrapped = true
	detailsLabel.Parent = body
	constrainText(detailsLabel, 12, 20)
	createTextStroke(detailsLabel, 2)

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.fromScale(0.84, 0.12)
	countdownLabel.Position = UDim2.fromScale(0.5, 0.79)
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.TextColor3 = Color3.fromRGB(255, 230, 140)
	countdownLabel.Font = Enum.Font.DenkOne
	countdownLabel.TextScaled = true
	countdownLabel.TextWrapped = true
	countdownLabel.Parent = body
	constrainText(countdownLabel, 12, 18)
	createTextStroke(countdownLabel, 2)

	local declineButton = Instance.new("TextButton")
	declineButton.Name = "DeclineButton"
	declineButton.Size = UDim2.fromScale(0.26, 0.13)
	declineButton.Position = UDim2.fromScale(0.35, 0.88)
	declineButton.AnchorPoint = Vector2.new(0.5, 0.5)
	declineButton.BackgroundColor3 = Color3.fromRGB(170, 65, 65)
	declineButton.BorderSizePixel = 0
	declineButton.Text = "DECLINE"
	declineButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	declineButton.Font = Enum.Font.DenkOne
	declineButton.TextScaled = true
	declineButton.Parent = main

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 10)
	declineCorner.Parent = declineButton

	attachPanelTexture(declineButton, 0.78)

	local declineStroke = Instance.new("UIStroke")
	declineStroke.Color = Color3.fromRGB(255, 255, 255)
	declineStroke.Thickness = 3
	declineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	declineStroke.Parent = declineButton
	createTextStroke(declineButton, 3)

	local acceptButton = Instance.new("TextButton")
	acceptButton.Name = "AcceptButton"
	acceptButton.Size = UDim2.fromScale(0.26, 0.13)
	acceptButton.Position = UDim2.fromScale(0.65, 0.88)
	acceptButton.AnchorPoint = Vector2.new(0.5, 0.5)
	acceptButton.BackgroundColor3 = Color3.fromRGB(46, 148, 85)
	acceptButton.BorderSizePixel = 0
	acceptButton.Text = "ACCEPT"
	acceptButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	acceptButton.Font = Enum.Font.DenkOne
	acceptButton.TextScaled = true
	acceptButton.Parent = main

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 10)
	acceptCorner.Parent = acceptButton

	attachPanelTexture(acceptButton, 0.78)

	local acceptStroke = Instance.new("UIStroke")
	acceptStroke.Color = Color3.fromRGB(255, 255, 255)
	acceptStroke.Thickness = 3
	acceptStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	acceptStroke.Parent = acceptButton
	createTextStroke(acceptButton, 3)

	local function declineRequest()
		if activeIncomingRequestId ~= requestId then
			return
		end
		sendGiftDecision(requestId, false)
		closeModal()
	end

	backdrop.MouseButton1Click:Connect(declineRequest)
	closeButton.MouseButton1Click:Connect(declineRequest)
	declineButton.MouseButton1Click:Connect(declineRequest)
	acceptButton.MouseButton1Click:Connect(function()
		if activeIncomingRequestId ~= requestId then
			return
		end
		sendGiftDecision(requestId, true)
		closeModal()
	end)

	TweenService:Create(
		mainScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	task.spawn(function()
		for remaining = timeoutSeconds, 0, -1 do
			if modalRequestId ~= requestId or not countdownLabel.Parent then
				return
			end

			countdownLabel.Text = string.format("Expires in %ds", remaining)
			task.wait(1)
		end

		if modalRequestId == requestId then
			closeModal()
		end
	end)
end

local function handleResolvedPayload(payload)
	if payload.requestId == activeOutgoingRequestId then
		activeOutgoingRequestId = nil
	end
	if payload.requestId == activeIncomingRequestId then
		activeIncomingRequestId = nil
	end
	if modalRequestId == payload.requestId then
		closeModal()
	end

	local itemName = payload.itemName or "brainrot"
	local counterpartName = payload.counterpartName or "player"
	local role = payload.role

	if payload.success == true then
		if role == "sender" then
			showToast(string.format("Gifted %s to %s.", itemName, counterpartName), "success")
		else
			showToast(string.format("%s gifted you %s.", counterpartName, itemName), "success")
		end
		refreshGiftPrompts()
		return
	end

	local reason = payload.reason
	local message = "Gift cancelled."

	if role == "sender" then
		if reason == "no_equipped_item" then
			message = "Equip a brainrot before gifting."
		elseif reason == "sender_busy" then
			message = "Finish your current gift first."
		elseif reason == "recipient_busy" then
			message = string.format("%s is already busy with another gift.", counterpartName)
		elseif reason == "recipient_full" then
			message = string.format("%s's inventory is full.", counterpartName)
		elseif reason == "declined" then
			message = string.format("%s declined your gift.", counterpartName)
		elseif reason == "timed_out" then
			message = string.format("Gift request to %s timed out.", counterpartName)
		elseif reason == "too_far" then
			message = "Gift cancelled because you moved too far away."
		elseif reason == "recipient_cancelled" then
			message = string.format("%s cancelled the gift.", counterpartName)
		end
	else
		if reason == "sender_cancelled" then
			message = string.format("%s cancelled the gift.", counterpartName)
		elseif reason == "recipient_full" then
			message = "Your inventory is full."
		elseif reason == "declined" then
			message = "Gift declined."
		elseif reason == "timed_out" then
			message = "Gift request expired."
		elseif reason == "too_far" then
			message = "Gift cancelled because you moved too far away."
		end
	end

	showToast(message, "error")
	refreshGiftPrompts()
end

local function handleGiftResult(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "outgoingPending" then
		activeOutgoingRequestId = payload.requestId
		showToast(string.format("Gift request sent to %s.", payload.targetName or "player"), "success")
		refreshGiftPrompts()
		return
	end

	if payload.kind == "incomingRequest" then
		activeIncomingRequestId = payload.requestId
		openIncomingRequest(payload)
		refreshGiftPrompts()
		return
	end

	if payload.kind == "resolved" then
		handleResolvedPayload(payload)
	end
end

function GiftingClient.start()
	if started then
		return
	end
	started = true

	Remotes.GiftResult.OnClientEvent:Connect(handleGiftResult)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if not isGiftPrompt(prompt) then
			return
		end

		prompt.Enabled = shouldShowGiftPrompt(prompt)
	end)

	player.CharacterAdded:Connect(function()
		task.delay(0.25, refreshGiftPrompts)
	end)

	refreshGiftPrompts()

	task.spawn(function()
		while true do
			refreshGiftPrompts()
			task.wait(PROMPT_REFRESH_INTERVAL)
		end
	end)
end

return GiftingClient
