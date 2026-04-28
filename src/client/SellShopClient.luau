-- client/SellShopClient.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Util = require(ReplicatedStorage.Util)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local SellShopClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RING_RADIUS = Config.ShopRingRadius
local RING_Y_DROP = Config.ShopRingYDrop
local RING_FORWARD_OFFSET = Config.ShopRingForwardOffset
local OPEN_DIST = RING_RADIUS
local CLOSE_DIST = RING_RADIUS + Config.ShopRingClosePadding

local isOpen = false
local manuallyClosed = false
local requestPending = false
local lastCheck = 0
local CHECK_INTERVAL = 0.5

local shopGui = nil
local mainFrame = nil
local summaryLabel = nil
local sellAllButton = nil
local scrollFrame = nil
local listLayout = nil

local backpackAddedConn = nil
local backpackRemovedConn = nil
local playerChildAddedConn = nil
local playerChildRemovedConn = nil
local charAddedConn = nil
local charRemovedConn = nil
local charChildAddedConn = nil
local charChildRemovedConn = nil

local function getSellShops()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return {}
	end

	local results = {}
	for _, obj in map:GetDescendants() do
		if obj.Name == "SellShop" and obj:IsA("Model") then
			table.insert(results, obj)
		end
	end

	return results
end

local function getRingPos(shop)
	return (shop:GetPivot() * CFrame.new(0, -RING_Y_DROP, RING_FORWARD_OFFSET)).Position
end

local function getClosestDist()
	local character = player.Character
	if not character then
		return math.huge
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return math.huge
	end

	local closest = math.huge
	for _, shop in getSellShops() do
		local ok, ringPos = pcall(function()
			return getRingPos(shop)
		end)
		if ok then
			local flat = Vector3.new(ringPos.X, hrp.Position.Y, ringPos.Z)
			local dist = (hrp.Position - flat).Magnitude
			if dist < closest then
				closest = dist
			end
		end
	end

	return closest
end

local function formatMutation(mutation)
	if mutation == "Gold" or mutation == "Diamond" then
		return mutation
	end
	return "Normal"
end

local function getBackpack()
	return player:FindFirstChild("Backpack")
end

local function isEligibleTool(tool)
	return tool:IsA("Tool") and tool:GetAttribute("BrainrotTool") == true
end

local function getEligibleTools()
	local results = {}
	local seen = {}
	local currentBackpack = getBackpack()

	if currentBackpack then
		for _, child in ipairs(currentBackpack:GetChildren()) do
			if isEligibleTool(child) and not seen[child] then
				seen[child] = true
				table.insert(results, child)
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if isEligibleTool(child) and not seen[child] then
				seen[child] = true
				table.insert(results, child)
			end
		end
	end

	table.sort(results, function(a, b)
		local aIncome = a:GetAttribute("IncomePerSec") or 0
		local bIncome = b:GetAttribute("IncomePerSec") or 0
		if aIncome ~= bIncome then
			return aIncome > bIncome
		end
		return a.Name < b.Name
	end)

	return results
end

local function getSellValue(tool)
	return math.floor((tool:GetAttribute("IncomePerSec") or 0) * 10)
end

local function disconnectCharacterConnections()
	if charChildAddedConn then
		charChildAddedConn:Disconnect()
		charChildAddedConn = nil
	end
	if charChildRemovedConn then
		charChildRemovedConn:Disconnect()
		charChildRemovedConn = nil
	end
end

local function disconnectBackpackConnections()
	if backpackAddedConn then
		backpackAddedConn:Disconnect()
		backpackAddedConn = nil
	end
	if backpackRemovedConn then
		backpackRemovedConn:Disconnect()
		backpackRemovedConn = nil
	end
end

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

local function setButtonsEnabled(enabled)
	if sellAllButton then
		sellAllButton.Active = enabled
		sellAllButton.AutoButtonColor = enabled
	end

	if not scrollFrame then
		return
	end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			local btn = child:FindFirstChild("SellButton")
			if btn and btn:IsA("TextButton") then
				btn.Active = enabled
				btn.AutoButtonColor = enabled
			end
		end
	end
end

-- NEW Sell shop
local function rebuildRows()
	if not isOpen or not scrollFrame or not summaryLabel or not listLayout then
		return
	end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local tools = getEligibleTools()
	local totalValue = 0
	for _, tool in ipairs(tools) do
		totalValue += getSellValue(tool)
	end

	local itemWord = #tools == 1 and "Brainrot" or "Brainrots"
	summaryLabel.Text = "Sell " .. tostring(#tools) .. " " .. itemWord .. " for: " .. Util.formatMoney(totalValue)

	if sellAllButton then
		sellAllButton.Text = "SELL ALL"
		sellAllButton.Active = #tools > 0 and not requestPending
		sellAllButton.AutoButtonColor = #tools > 0 and not requestPending
		sellAllButton.BackgroundColor3 = requestPending and Color3.fromRGB(60, 60, 60) or Color3.fromRGB(20, 20, 20)
	end

	if #tools == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyLabel"
		empty.Size = UDim2.new(1, -20, 0, 120)
		empty.Position = UDim2.new(0, 10, 0, 20)
		empty.BackgroundTransparency = 1
		empty.Text = "No brainrots in inventory"
		empty.TextColor3 = Color3.fromRGB(255, 255, 255)
		empty.Font = Enum.Font.DenkOne
		empty.TextScaled = true
		empty.Parent = scrollFrame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 3
		stroke.Parent = empty

		scrollFrame.CanvasSize = UDim2.fromOffset(0, 150)
		return
	end

	for _, tool in ipairs(tools) do
		local frame = Instance.new("Frame")
		frame.Name = "SellRow"
		frame.Size = UDim2.new(0.95, 0, 0, 96)
		frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		frame.BackgroundTransparency = 0.08
		frame.BorderSizePixel = 0
		frame.Parent = scrollFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame

		attachPanelTexture(frame, 0.82)

		local frameStroke = Instance.new("UIStroke")
		frameStroke.Color = Color3.fromRGB(255, 255, 255)
		frameStroke.Thickness = 2.5
		frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		frameStroke.Parent = frame

		local info = Instance.new("TextLabel")
		info.Size = UDim2.fromScale(0.58, 0.78)
		info.Position = UDim2.new(0, 18, 0.5, 0)
		info.AnchorPoint = Vector2.new(0, 0.5)
		info.BackgroundTransparency = 1
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Center
		info.RichText = true
		info.TextScaled = true
		info.Font = Enum.Font.DenkOne
		info.TextColor3 = Color3.fromRGB(255, 255, 255)
		info.Text = string.format(
			"<b>%s</b>\nLevel: %d\n%s",
			tool.Name,
			tool:GetAttribute("Level") or 1,
			formatMutation(tool:GetAttribute("Mutation") or "None")
		)
		info.Parent = frame

		local infoStroke = Instance.new("UIStroke")
		infoStroke.Color = Color3.fromRGB(0, 0, 0)
		infoStroke.Thickness = 3
		infoStroke.Parent = info

		local btn = Instance.new("TextButton")
		btn.Name = "SellButton"
		btn.Size = UDim2.fromScale(0.34, 0.68)
		btn.Position = UDim2.fromScale(0.97, 0.5)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.BackgroundColor3 = requestPending and Color3.fromRGB(60, 60, 60) or Color3.fromRGB(20, 20, 20)
		btn.Text = "SELL (" .. Util.formatMoney(getSellValue(tool)) .. ")"
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.DenkOne
		btn.TextScaled = true
		btn.Active = not requestPending
		btn.AutoButtonColor = not requestPending
		btn.Parent = frame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		attachPanelTexture(btn, 0.78)

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(255, 255, 255)
		btnStroke.Thickness = 3
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if requestPending then
				return
			end

			requestPending = true
			setButtonsEnabled(false)
			btn.Text = "..."
			Remotes.SellInventoryItem:FireServer(tool)

			task.delay(3, function()
				if requestPending then
					requestPending = false
					rebuildRows()
				end
			end)
		end)
	end

	scrollFrame.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 25)
end

-- NEW Sell shop
local function closeShop()
	if shopGui then
		shopGui:Destroy()
		shopGui = nil
		mainFrame = nil
		summaryLabel = nil
		sellAllButton = nil
		scrollFrame = nil
		listLayout = nil
	end

	isOpen = false
	manuallyClosed = true
	requestPending = false
end

-- NEW Sell shop
local function openShop()
	if isOpen then
		return
	end

	isOpen = true

	local screen = Instance.new("ScreenGui")
	screen.Name = "SellShopGui"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui
	shopGui = screen

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.72, 0.74)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	main.BackgroundTransparency = 0.08
	main.Parent = screen
	mainFrame = main

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 15)
	mainCorner.Parent = main

	attachPanelTexture(main, 0.88)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.42
	aspect.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Thickness = 4
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = main

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.14)
	header.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
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
	title.Text = "SELL"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 4
	titleStroke.Parent = title

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

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(255, 255, 255)
	closeStroke.Thickness = 3
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeShop)

	local summary = Instance.new("TextLabel")
	summary.Name = "SummaryLabel"
	summary.Size = UDim2.fromScale(0.68, 0.1)
	summary.Position = UDim2.fromScale(0.04, 0.18)
	summary.BackgroundTransparency = 1
	summary.TextColor3 = Color3.fromRGB(255, 255, 255)
	summary.Font = Enum.Font.DenkOne
	summary.TextScaled = true
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Parent = main
	summaryLabel = summary

	local summaryStroke = Instance.new("UIStroke")
	summaryStroke.Color = Color3.fromRGB(0, 0, 0)
	summaryStroke.Thickness = 3
	summaryStroke.Parent = summary

	local sellAll = Instance.new("TextButton")
	sellAll.Name = "SellAllButton"
	sellAll.Size = UDim2.fromScale(0.24, 0.1)
	sellAll.Position = UDim2.fromScale(0.96, 0.18)
	sellAll.AnchorPoint = Vector2.new(1, 0)
	sellAll.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	sellAll.Text = "SELL ALL"
	sellAll.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellAll.Font = Enum.Font.DenkOne
	sellAll.TextScaled = true
	sellAll.Parent = main
	sellAllButton = sellAll

	local sellAllCorner = Instance.new("UICorner")
	sellAllCorner.CornerRadius = UDim.new(0, 8)
	sellAllCorner.Parent = sellAll

	attachPanelTexture(sellAll, 0.76)

	local sellAllStroke = Instance.new("UIStroke")
	sellAllStroke.Color = Color3.fromRGB(255, 255, 255)
	sellAllStroke.Thickness = 3
	sellAllStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sellAllStroke.Parent = sellAll

	sellAll.MouseButton1Click:Connect(function()
		local tools = getEligibleTools()
		if requestPending or #tools == 0 then
			return
		end

		requestPending = true
		setButtonsEnabled(false)
		sellAll.Text = "..."
		Remotes.SellAllInventoryItems:FireServer()

		task.delay(3, function()
			if requestPending then
				requestPending = false
				rebuildRows()
			end
		end)
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.Size = UDim2.fromScale(0.94, 0.62)
	scroll.Position = UDim2.fromScale(0.5, 0.62)
	scroll.AnchorPoint = Vector2.new(0.5, 0.5)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = main
	scrollFrame = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll
	listLayout = layout

	rebuildRows()
end

local function onInventoryChanged()
	requestPending = false
	if isOpen then
		rebuildRows()
	end
end

local function bindBackpackConnections()
	disconnectBackpackConnections()

	local currentBackpack = getBackpack()
	if not currentBackpack then
		return
	end

	backpackAddedConn = currentBackpack.ChildAdded:Connect(onInventoryChanged)
	backpackRemovedConn = currentBackpack.ChildRemoved:Connect(onInventoryChanged)
end

local function watchCharacter(character)
	disconnectCharacterConnections()
	if not character then
		return
	end

	charChildAddedConn = character.ChildAdded:Connect(onInventoryChanged)
	charChildRemovedConn = character.ChildRemoved:Connect(onInventoryChanged)
end

-- NEW Sell shop
local function connectInventoryWatchers()
	bindBackpackConnections()

	if not playerChildAddedConn then
		playerChildAddedConn = player.ChildAdded:Connect(function(child)
			if child.Name == "Backpack" then
				bindBackpackConnections()
				onInventoryChanged()
			end
		end)
	end
	if not playerChildRemovedConn then
		playerChildRemovedConn = player.ChildRemoved:Connect(function(child)
			if child.Name == "Backpack" then
				disconnectBackpackConnections()
				onInventoryChanged()
			end
		end)
	end
	if not charAddedConn then
		charAddedConn = player.CharacterAdded:Connect(function(character)
			watchCharacter(character)
			onInventoryChanged()
		end)
	end
	if not charRemovedConn then
		charRemovedConn = player.CharacterRemoving:Connect(function()
			disconnectCharacterConnections()
			onInventoryChanged()
		end)
	end

	watchCharacter(player.Character)
end

-- NEW Sell shop
local function spawnRings()
	task.wait(2)
	for _, shop in getSellShops() do
		local ring = Instance.new("Part")
		ring.Name = "SellShopRing"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CastShadow = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.05, RING_RADIUS * 2, RING_RADIUS * 2)
		ring.CFrame = CFrame.new(getRingPos(shop)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(255, 55, 55)
		ring.Transparency = 0.78
		ring.Parent = workspace
	end
end

function SellShopClient.start()
	connectInventoryWatchers()
	task.spawn(spawnRings)

	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheck < CHECK_INTERVAL then
			return
		end
		lastCheck = now

		local dist = getClosestDist()

		if not isOpen and not manuallyClosed and dist <= OPEN_DIST then
			openShop()
		elseif isOpen and dist > CLOSE_DIST then
			manuallyClosed = false
			closeShop()
		elseif not isOpen and manuallyClosed and dist > CLOSE_DIST then
			manuallyClosed = false
		end
	end)
end

return SellShopClient
