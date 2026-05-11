local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local GamepassShopClient = {}

local DEBUG_GAMEPASS_SHOP = false
local PANEL_TEXTURE = "rbxassetid://6927295847"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shopGui = nil
local attributeConnections = {}
local gamepassIconCache = {}
local pendingIconRequests = {}

local entries = {
	{
		key = "DoubleCash",
		name = "2x Cash",
		description = "Earn double money from every brainrot you place",
		accent = Color3.fromRGB(48, 190, 92),
	},
	{
		key = "SpeedBoost",
		name = "1.5x Speed",
		description = "Move 50% faster everywhere",
		accent = Color3.fromRGB(73, 146, 255),
	},
}

local function logDebug(...)
	if not DEBUG_GAMEPASS_SHOP then
		return
	end

	print("[GamepassShopClient]", ...)
end

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

local function disconnectAttributeConnections()
	for _, connection in ipairs(attributeConnections) do
		connection:Disconnect()
	end

	table.clear(attributeConnections)
end

local function closeShop()
	disconnectAttributeConnections()

	if shopGui then
		shopGui:Destroy()
		shopGui = nil
	end
end

local function applyIconImage(iconLabel, iconAssetId)
	if not iconLabel or not iconLabel.Parent then
		return
	end

	if iconAssetId and iconAssetId > 0 then
		iconLabel.Image = "rbxassetid://" .. tostring(iconAssetId)
		iconLabel.ImageTransparency = 0
	else
		iconLabel.Image = ""
		iconLabel.ImageTransparency = 1
	end
end

local function fetchGamepassIconAsync(passId, callback)
	local cachedIconId = gamepassIconCache[passId]
	if cachedIconId ~= nil then
		callback(cachedIconId)
		return
	end

	if pendingIconRequests[passId] then
		table.insert(pendingIconRequests[passId], callback)
		return
	end

	pendingIconRequests[passId] = { callback }

	task.spawn(function()
		local iconAssetId = false
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfoAsync(passId, Enum.InfoType.GamePass)
		end)

		if success then
			local resolvedIconId = tonumber(productInfo.IconImageAssetId)
			if resolvedIconId and resolvedIconId > 0 then
				iconAssetId = resolvedIconId
			end
			gamepassIconCache[passId] = iconAssetId
		else
			warn(string.format("[GamepassShopClient] Failed to fetch gamepass icon for pass %d: %s", passId, tostring(productInfo)))
		end

		local callbacks = pendingIconRequests[passId] or {}
		pendingIconRequests[passId] = nil

		for _, queuedCallback in ipairs(callbacks) do
			queuedCallback(iconAssetId)
		end
	end)
end

local function updateButtonState(button, key)
	local owned = player:GetAttribute("Has" .. key) == true
	local titleLabel = button:FindFirstChild("TitleLabel")
	local buttonStroke = button:FindFirstChildOfClass("UIStroke")

	logDebug(
		"updateButtonState",
		"key=" .. key,
		"owned=" .. tostring(owned),
		"attribute=" .. tostring(player:GetAttribute("Has" .. key))
	)

	if titleLabel then
		titleLabel.Text = owned and "OWNED" or "BUY (49 R)"
		titleLabel.TextColor3 = owned and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(255, 255, 255)
	end

	button.Active = not owned
	button.AutoButtonColor = not owned
	button.BackgroundColor3 = owned and Color3.fromRGB(58, 58, 62) or Color3.fromRGB(33, 158, 76)

	if buttonStroke then
		buttonStroke.Color = owned and Color3.fromRGB(155, 155, 160) or Color3.fromRGB(255, 255, 255)
		buttonStroke.Thickness = owned and 2 or 3
	end
end

local function createActionButton(parent)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Color3.fromRGB(33, 158, 76)
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	createCorner(button, 10)
	createStroke(button, Color3.fromRGB(255, 255, 255), 3)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.fromScale(0.86, 0.58)
	titleLabel.Position = UDim2.fromScale(0.5, 0.5)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.DenkOne
	titleLabel.Text = "BUY (49 R)"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Parent = button
	constrainText(titleLabel, 10, 20)
	createTextStroke(titleLabel, 2.5)

	return button
end

local function buildRow(parent, entry)
	local leftColumnScale = 0.24
	local rightColumnScale = 0.24
	local columnGap = 14
	local textInset = 6

	local row = Instance.new("Frame")
	row.Name = entry.key .. "Row"
	row.LayoutOrder = entry.layoutOrder or 0
	row.Size = UDim2.new(0.96, 0, 0, 122)
	row.BackgroundColor3 = Color3.fromRGB(48, 48, 54)
	row.BackgroundTransparency = 0.08
	row.BorderSizePixel = 0
	row.Parent = parent
	createCorner(row, 14)
	attachPanelTexture(row, 0.9)
	createStroke(row, Color3.fromRGB(255, 255, 255), 2.5)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -28, 1, -20)
	content.Position = UDim2.fromOffset(14, 10)
	content.BackgroundTransparency = 1
	content.Parent = row

	local leftColumn = Instance.new("Frame")
	leftColumn.Name = "LeftColumn"
	leftColumn.Size = UDim2.new(leftColumnScale, 0, 1, 0)
	leftColumn.BackgroundTransparency = 1
	leftColumn.Parent = content

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 10, 0.76, 0)
	accent.Position = UDim2.new(0, 8, 0.5, 0)
	accent.AnchorPoint = Vector2.new(0, 0.5)
	accent.BackgroundColor3 = entry.accent
	accent.BorderSizePixel = 0
	accent.Parent = leftColumn
	createCorner(accent, 999)

	local iconShell = Instance.new("Frame")
	iconShell.Name = "IconShell"
	iconShell.Size = UDim2.new(1, -36, 1, -18)
	iconShell.Position = UDim2.new(0, 28, 0.5, 0)
	iconShell.AnchorPoint = Vector2.new(0, 0.5)
	iconShell.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	iconShell.BorderSizePixel = 0
	iconShell.Parent = leftColumn
	createCorner(iconShell, 10)
	createStroke(iconShell, Color3.fromRGB(115, 115, 120), 2)

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Width
	iconAspect.Parent = iconShell

	local iconSizeConstraint = Instance.new("UISizeConstraint")
	iconSizeConstraint.MinSize = Vector2.new(54, 54)
	iconSizeConstraint.MaxSize = Vector2.new(88, 88)
	iconSizeConstraint.Parent = iconShell

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ImageTransparency = 1
	icon.Parent = iconShell

	fetchGamepassIconAsync(Config.Gamepasses[entry.key], function(iconAssetId)
		applyIconImage(icon, iconAssetId)
	end)

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Size = UDim2.new(1 - leftColumnScale - rightColumnScale, -(columnGap * 2), 1, 0)
	info.Position = UDim2.new(leftColumnScale, columnGap, 0, 0)
	info.BackgroundTransparency = 1
	info.ClipsDescendants = true
	info.Parent = content

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -textInset, 0.36, 0)
	title.Position = UDim2.fromOffset(textInset, 0)
	title.BackgroundTransparency = 1
	title.Text = entry.name
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = info
	constrainText(title, 14, 30)
	createTextStroke(title, 3)

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.Size = UDim2.new(1, -textInset, 0.52, 0)
	description.Position = UDim2.new(0, textInset, 0.4, 0)
	description.BackgroundTransparency = 1
	description.Text = entry.description
	description.TextColor3 = Color3.fromRGB(232, 232, 232)
	description.Font = Enum.Font.DenkOne
	description.TextWrapped = true
	description.TextScaled = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Parent = info
	constrainText(description, 11, 17)
	createTextStroke(description, 2.5)

	local actionFrame = Instance.new("Frame")
	actionFrame.Name = "ActionFrame"
	actionFrame.Size = UDim2.new(rightColumnScale, 0, 1, 0)
	actionFrame.Position = UDim2.new(1, 0, 0, 0)
	actionFrame.AnchorPoint = Vector2.new(1, 0)
	actionFrame.BackgroundTransparency = 1
	actionFrame.Parent = content

	local buyButton = createActionButton(actionFrame)
	buyButton.Name = entry.key .. "Button"
	buyButton.Size = UDim2.new(1, -6, 0, 58)
	buyButton.Position = UDim2.fromScale(0.5, 0.5)
	buyButton.AnchorPoint = Vector2.new(0.5, 0.5)
	updateButtonState(buyButton, entry.key)

	local buttonSizeConstraint = Instance.new("UISizeConstraint")
	buttonSizeConstraint.MinSize = Vector2.new(96, 50)
	buttonSizeConstraint.MaxSize = Vector2.new(148, 62)
	buttonSizeConstraint.Parent = buyButton

	buyButton.MouseButton1Click:Connect(function()
		if player:GetAttribute("Has" .. entry.key) == true then
			return
		end

		logDebug("prompt purchase", "key=" .. entry.key, "passId=" .. tostring(Config.Gamepasses[entry.key]))
		MarketplaceService:PromptGamePassPurchase(player, Config.Gamepasses[entry.key])
	end)

	table.insert(attributeConnections, player:GetAttributeChangedSignal("Has" .. entry.key):Connect(function()
		updateButtonState(buyButton, entry.key)
	end))
end

local function openShop()
	if shopGui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "GamepassShopGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 25
	screen.Parent = playerGui
	shopGui = screen

	logDebug(
		"openShop",
		"HasDoubleCash=" .. tostring(player:GetAttribute("HasDoubleCash")),
		"HasSpeedBoost=" .. tostring(player:GetAttribute("HasSpeedBoost"))
	)

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.42
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	backdrop.MouseButton1Click:Connect(closeShop)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.74, 0.76)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	main.BackgroundTransparency = 0.06
	main.BorderSizePixel = 0
	main.Parent = screen
	createCorner(main, 16)
	attachPanelTexture(main, 0.88)
	createStroke(main, Color3.fromRGB(255, 255, 255), 4)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.42
	aspect.Parent = main

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.15)
	header.BackgroundColor3 = Color3.fromRGB(40, 55, 80)
	header.BorderSizePixel = 0
	header.Parent = main
	createCorner(header, 16)
	attachPanelTexture(header, 0.75)
	createStroke(header, Color3.fromRGB(255, 255, 255), 3)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.5, 0.52)
	title.Position = UDim2.fromScale(0.05, 0.14)
	title.BackgroundTransparency = 1
	title.Text = "STORE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	constrainText(title, 20, 38)
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
	closeButton.MouseButton1Click:Connect(closeShop)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Rows"
	body.Size = UDim2.fromScale(0.94, 0.69)
	body.Position = UDim2.fromScale(0.5, 0.59)
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	body.Parent = main

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingLeft = UDim.new(0, 2)
	bodyPadding.PaddingRight = UDim.new(0, 2)
	bodyPadding.PaddingTop = UDim.new(0, 8)
	bodyPadding.PaddingBottom = UDim.new(0, 8)
	bodyPadding.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	for index, entry in ipairs(entries) do
		entry.layoutOrder = index
		buildRow(body, entry)
	end
end

function GamepassShopClient.start()
	local buttonGui = playerGui:WaitForChild("ShopGui", 10)
	if not buttonGui then
		warn("[GamepassShopClient] ShopGui not found")
		return
	end

	local shopButton = buttonGui:WaitForChild("ShopButton", 5)
	if not shopButton then
		warn("[GamepassShopClient] ShopButton not found")
		return
	end

	shopButton.MouseButton1Click:Connect(function()
		if shopGui then
			closeShop()
		else
			openShop()
		end
	end)
end

return GamepassShopClient
