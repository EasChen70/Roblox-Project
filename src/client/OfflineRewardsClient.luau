local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Util = require(ReplicatedStorage.Util)

local OfflineRewardsClient = {}

local PANEL_TEXTURE = "rbxassetid://6927295847"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local started = false
local popupGui = nil
local shownThisSession = false

local function createStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function createTextStroke(parent, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function constrainText(label, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	return constraint
end

local function attachPanelTexture(parent, transparency)
	local texture = Instance.new("ImageLabel")
	texture.Name = "PanelTexture"
	texture.BackgroundTransparency = 1
	texture.Image = PANEL_TEXTURE
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

local function formatOfflineTime(seconds)
	local totalSeconds = math.max(0, math.floor(seconds or 0))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)

	if hours > 0 and minutes > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	if hours > 0 then
		return string.format("%dh", hours)
	end
	if minutes > 0 then
		return string.format("%dm", minutes)
	end

	return "<1m"
end

local function closePopup()
	if popupGui then
		popupGui:Destroy()
		popupGui = nil
	end
end

local function showPopup(payload)
	if shownThisSession or not Config.OfflineIncomePopupEnabled then
		return
	end

	if type(payload) ~= "table" or type(payload.totalAmount) ~= "number" or payload.totalAmount <= 0 then
		return
	end

	shownThisSession = true

	local formattedAmount = Util.formatMoney(payload.totalAmount)
	local formattedTime = formatOfflineTime(payload.offlineSeconds)
	local slotCount = math.max(0, math.floor(payload.slotCount or 0))
	local slotLabel = slotCount == 1 and "slot" or "slots"

	local screen = Instance.new("ScreenGui")
	screen.Name = "OfflineRewardsGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 26
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	popupGui = screen

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	backdrop.MouseButton1Click:Connect(closePopup)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.62, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
	main.BackgroundTransparency = 0.04
	main.BorderSizePixel = 0
	main.Parent = screen
	createCorner(main, 16)
	attachPanelTexture(main, 0.88)
	createStroke(main, Color3.fromRGB(255, 255, 255), 4)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.45
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
	createCorner(header, 16)
	attachPanelTexture(header, 0.75)
	createStroke(header, Color3.fromRGB(255, 255, 255), 3)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.64, 0.58)
	title.Position = UDim2.fromScale(0.05, 0.18)
	title.BackgroundTransparency = 1
	title.Text = "OFFLINE EARNINGS"
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
	createCorner(closeButton, 8)
	createStroke(closeButton, Color3.fromRGB(255, 255, 255), 3)
	constrainText(closeButton, 14, 30)
	createTextStroke(closeButton, 2)
	closeButton.MouseButton1Click:Connect(closePopup)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(0.9, 0.56)
	body.Position = UDim2.fromScale(0.5, 0.53)
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.BackgroundColor3 = Color3.fromRGB(54, 58, 56)
	body.BackgroundTransparency = 0.08
	body.BorderSizePixel = 0
	body.Parent = main
	createCorner(body, 12)
	attachPanelTexture(body, 0.12)
	createStroke(body, Color3.fromRGB(255, 255, 255), 2.5)

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.Size = UDim2.fromScale(0.84, 0.26)
	amountLabel.Position = UDim2.fromScale(0.5, 0.2)
	amountLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = formattedAmount
	amountLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
	amountLabel.Font = Enum.Font.DenkOne
	amountLabel.TextScaled = true
	amountLabel.Parent = body
	constrainText(amountLabel, 26, 44)
	createTextStroke(amountLabel, 4)

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.fromScale(0.82, 0.22)
	messageLabel.Position = UDim2.fromScale(0.5, 0.5)
	messageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = "Your earnings are waiting in your base slots."
	messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	messageLabel.Font = Enum.Font.DenkOne
	messageLabel.TextScaled = true
	messageLabel.TextWrapped = true
	messageLabel.Parent = body
	constrainText(messageLabel, 16, 26)
	createTextStroke(messageLabel, 3)

	local metaLabel = Instance.new("TextLabel")
	metaLabel.Name = "Meta"
	metaLabel.Size = UDim2.fromScale(0.82, 0.14)
	metaLabel.Position = UDim2.fromScale(0.5, 0.73)
	metaLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	metaLabel.BackgroundTransparency = 1
	metaLabel.Text = string.format("%d %s filled up while you were away for %s.", slotCount, slotLabel, formattedTime)
	metaLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	metaLabel.Font = Enum.Font.DenkOne
	metaLabel.TextScaled = true
	metaLabel.TextWrapped = true
	metaLabel.Parent = body
	constrainText(metaLabel, 12, 20)
	createTextStroke(metaLabel, 2)

	local okButton = Instance.new("TextButton")
	okButton.Name = "OkButton"
	okButton.Size = UDim2.fromScale(0.26, 0.13)
	okButton.Position = UDim2.fromScale(0.5, 0.88)
	okButton.AnchorPoint = Vector2.new(0.5, 0.5)
	okButton.BackgroundColor3 = Color3.fromRGB(46, 148, 85)
	okButton.BorderSizePixel = 0
	okButton.Text = "OK"
	okButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	okButton.Font = Enum.Font.DenkOne
	okButton.TextScaled = true
	okButton.Parent = main
	createCorner(okButton, 10)
	attachPanelTexture(okButton, 0.78)
	createStroke(okButton, Color3.fromRGB(255, 255, 255), 3)
	constrainText(okButton, 16, 26)
	createTextStroke(okButton, 3)
	okButton.MouseButton1Click:Connect(closePopup)

	TweenService:Create(
		mainScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

function OfflineRewardsClient.start()
	if started then
		return
	end

	started = true
	Remotes.OfflineEarningsAwarded.OnClientEvent:Connect(showPopup)
end

return OfflineRewardsClient
