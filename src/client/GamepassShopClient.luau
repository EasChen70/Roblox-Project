local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local GamepassShopClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shopGui = nil
local attributeConnections = {}

local entries = {
	{
		key = "DoubleCash",
		name = "2x Cash",
		description = "Earn double money from every brainrot you place",
	},
	{
		key = "SpeedBoost",
		name = "1.5x Speed",
		description = "Move 50% faster everywhere",
	},
}

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

local function createStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function createButton(parent, text)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.DenkOne
	button.TextScaled = true
	button.Parent = parent
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	createStroke(button, Color3.fromRGB(255, 255, 255), 3)
	return button
end

local function updateButtonState(button, key)
	local owned = player:GetAttribute("Has" .. key) == true
	button.Text = owned and "OWNED" or "BUY (49 R)"
	button.Active = not owned
	button.AutoButtonColor = not owned
	button.BackgroundColor3 = owned and Color3.fromRGB(110, 110, 110) or Color3.fromRGB(80, 200, 80)
end

local function buildRow(parent, entry)
	local row = Instance.new("Frame")
	row.Name = entry.key .. "Row"
	row.Size = UDim2.new(1, 0, 0, 110)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
	createStroke(row, Color3.fromRGB(255, 255, 255), 2)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(80, 80)
	icon.Position = UDim2.new(0, 15, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Image = string.format("rbxthumb://type=GamePass&id=%d&w=150&h=150", Config.Gamepasses[entry.key])
	icon.Parent = row

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.46, 0, 0.28, 0)
	title.Position = UDim2.new(0, 110, 0, 16)
	title.Text = entry.name
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = row
	createStroke(title, Color3.fromRGB(0, 0, 0), 3)

	local description = Instance.new("TextLabel")
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(0.46, 0, 0.4, 0)
	description.Position = UDim2.new(0, 110, 0, 48)
	description.Text = entry.description
	description.TextColor3 = Color3.fromRGB(220, 220, 220)
	description.Font = Enum.Font.DenkOne
	description.TextWrapped = true
	description.TextScaled = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.Parent = row
	createStroke(description, Color3.fromRGB(0, 0, 0), 2)

	local buyButton = createButton(row, "BUY (49 R)")
	buyButton.Name = entry.key .. "Button"
	buyButton.Size = UDim2.fromScale(0.24, 0.55)
	buyButton.Position = UDim2.new(0.96, 0, 0.5, 0)
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	updateButtonState(buyButton, entry.key)

	buyButton.MouseButton1Click:Connect(function()
		if player:GetAttribute("Has" .. entry.key) == true then
			return
		end

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

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	backdrop.MouseButton1Click:Connect(closeShop)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(0.56, 0.6)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	createStroke(panel, Color3.fromRGB(255, 255, 255), 3)

	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.Size = UDim2.fromScale(0.7, 0.12)
	header.Position = UDim2.fromScale(0.08, 0.06)
	header.BackgroundTransparency = 1
	header.Text = "STORE"
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.Font = Enum.Font.DenkOne
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel
	createStroke(header, Color3.fromRGB(0, 0, 0), 3)

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromScale(0.08, 0.11)
	closeButton.Position = UDim2.fromScale(0.96, 0.04)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Font = Enum.Font.DenkOne
	closeButton.TextScaled = true
	closeButton.Parent = panel
	Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 8)
	createStroke(closeButton, Color3.fromRGB(0, 0, 0), 3)
	closeButton.MouseButton1Click:Connect(closeShop)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(0.88, 0.66)
	content.Position = UDim2.fromScale(0.5, 0.58)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = content

	for _, entry in ipairs(entries) do
		buildRow(content, entry)
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
