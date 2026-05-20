-- client/CannonShopClient.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Util = require(ReplicatedStorage.Util)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ShopZones = require(ReplicatedStorage.ShopZones)

local CannonShopClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CANNON_BILLBOARD_DIST = 35

local RING_RADIUS = Config.ShopRingRadius
local OPEN_DIST = RING_RADIUS
local CLOSE_DIST = RING_RADIUS + Config.ShopRingClosePadding
local CASH_SOUND_ID = "rbxassetid://96267401354076"
local ENABLED_BUTTON_COLOR = Color3.fromRGB(0, 170, 0)
local DISABLED_BUTTON_COLOR = Color3.fromRGB(120, 120, 120)
local PENDING_BUTTON_COLOR = Color3.fromRGB(150, 150, 150)

local isOpen = false
local manuallyClosed = false
local purchasePending = false
local lastCheck = 0
local CHECK_INTERVAL = 0.5

local shopGui = nil
local badgeLabel = nil
local rowRefs = {}

-- ── Model finders ─────────────────────────────────────────────────────────────

local function getCannonModels()
	local map = workspace:FindFirstChild("Map")
	if not map then return {} end
	local results = {}
	for _, obj in map:GetDescendants() do
		if obj:IsA("Model") and string.find(obj.Name, "CannonModel") then
			table.insert(results, obj)
		end
	end
	return results
end

local function getClosestDist(verticalPadding)
	local character = player.Character
	if not character then
		return math.huge
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return math.huge
	end

	return ShopZones.getClosestHorizontalDistance(hrp.Position, "CannonShop", verticalPadding)
end

-- ── Ground rings ──────────────────────────────────────────────────────────────

local function spawnRings()
	task.wait(2)
	for _, shop in ShopZones.getShops("CannonShop") do
		local ring = Instance.new("Part")
		ring.Name = "CannonShopRing"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CastShadow = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.05, RING_RADIUS * 2, RING_RADIUS * 2)
		ring.CFrame = CFrame.new(ShopZones.getRingPosition(shop)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(145, 19, 195)
		ring.Transparency = 0.78
		ring.Parent = workspace
	end
end

-- ── Cannon power billboards ───────────────────────────────────────────────────

local function getCannonPower()
	return player:GetAttribute("CannonPower") or 1
end

local function updateCannonBillboards()
	local power = getCannonPower()
	local text = "💥 " .. (power > 0 and tostring(power) or "0")

	for _, cannon in getCannonModels() do
		if not cannon:FindFirstChild("PowerBillboard") then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "PowerBillboard"
			billboard.Size = UDim2.fromOffset(150, 70)
			local _, size = cannon:GetBoundingBox()
			billboard.StudsOffset = Vector3.new(0, (size.Y / 2) + 8, 0)
			billboard.AlwaysOnTop = true
			billboard.LightInfluence = 0
			billboard.Parent = cannon

			local label = Instance.new("TextLabel")
			label.Name = "PowerLabel"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(255, 215, 0)
			label.Font = Enum.Font.LuckiestGuy
			label.TextScaled = true
			label.Parent = billboard

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(0, 0, 0)
			stroke.Thickness = 3
			stroke.Parent = label
		end

		local bill = cannon:FindFirstChild("PowerBillboard")
		if bill then
			local lbl = bill:FindFirstChild("PowerLabel")
			if lbl then
				lbl.Text = text
			end
		end
	end
end

local function updateBillboardVisibility()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for _, cannon in getCannonModels() do
		local bill = cannon:FindFirstChild("PowerBillboard")
		if bill then
			local ok, pos = pcall(function()
				return cannon:GetPivot().Position
			end)
			if ok then
				local dist = (hrp.Position - pos).Magnitude
				bill.Enabled = dist <= CANNON_BILLBOARD_DIST
			end
		end
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

-- ── UI ────────────────────────────────────────────────────────────────────────

local function computeCost(baseCost, currentPower, amount)
	if currentPower == 1 and amount == 1 then
		return 0
	end
	return math.floor(baseCost * (Config.CannonCostScale ^ currentPower))
end

local function costText(baseCost, currentPower, amount)
	local cost = computeCost(baseCost, currentPower, amount)
	return cost == 0 and "FREE" or Util.formatMoney(cost)
end

local function canPurchaseUpgrade(currentPower, amount)
	return currentPower + amount <= Config.MaxCannonPower
end

local function applyRowState(row, currentPower)
	if row.label then
		row.label.Text = "+" .. row.entry.amount .. " Power\n" .. currentPower .. " → " .. (currentPower + row.entry.amount)
	end

	local btn = row.btn
	if not btn then
		return
	end

	if canPurchaseUpgrade(currentPower, row.entry.amount) then
		btn.BackgroundColor3 = ENABLED_BUTTON_COLOR
		btn.Text = costText(row.entry.cost, currentPower, row.entry.amount)
		btn.Active = true
		btn.AutoButtonColor = true
	else
		btn.BackgroundColor3 = DISABLED_BUTTON_COLOR
		btn.Text = "MAX"
		btn.Active = false
		btn.AutoButtonColor = false
	end
end

local function refreshUI()
	local power = getCannonPower()
	if badgeLabel then
		badgeLabel.Text = "💥POWER:  " .. tostring(power)
	end
	for _, row in rowRefs do
		applyRowState(row, power)
	end
end

local function buildRow(parent, entry)
	local frame = Instance.new("Frame")
	frame.Name = "UpgradeRow"
	frame.Size = UDim2.new(0.95, 0, 0, 96) -- Match standard 96 height of SellShop rows
	frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	
	attachPanelTexture(frame, 0.1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(255, 255, 255)
	rowStroke.Thickness = 2.5
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rowStroke.Parent = frame

	local power = getCannonPower()

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.6, 0.8)
	label.Position = UDim2.new(0, 15, 0.5, 0)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.BackgroundTransparency = 1
	label.Text = "+" .. entry.amount .. " Power\n" .. power .. " → " .. (power + entry.amount)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.DenkOne
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local lStroke = Instance.new("UIStroke")
	lStroke.Thickness = 3
	lStroke.Color = Color3.fromRGB(0, 0, 0)
	lStroke.Parent = label

	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.Size = UDim2.fromScale(0.3, 0.6)
	btn.Position = UDim2.fromScale(0.95, 0.5)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.BackgroundColor3 = purchasePending and PENDING_BUTTON_COLOR or ENABLED_BUTTON_COLOR
	btn.Text = purchasePending and "..." or costText(entry.cost, power, entry.amount)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.DenkOne
	btn.TextScaled = true
	btn.Active = not purchasePending
	btn.AutoButtonColor = not purchasePending
	btn.Parent = frame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	local bStroke = Instance.new("UIStroke")
	bStroke.Thickness = 3
	bStroke.Color = Color3.fromRGB(255, 255, 255)
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = btn

	table.insert(rowRefs, { label = label, btn = btn, entry = entry })

	btn.MouseButton1Click:Connect(function()
		if not btn.Active or purchasePending then
			return
		end

		local currentPower = getCannonPower()
		if not canPurchaseUpgrade(currentPower, entry.amount) then
			refreshUI()
			return
		end

		local cost = computeCost(entry.cost, currentPower, entry.amount)
		local playerMoney = player.leaderstats.Money.Value

		if playerMoney >= cost then
			purchasePending = true

			local sound = Instance.new("Sound")
			sound.SoundId = CASH_SOUND_ID
			sound.PlaybackSpeed = 1.6
			sound.Parent = game:GetService("SoundService")
			sound:Play()
			sound.Ended:Connect(function()
				sound:Destroy()
			end)

			btn.BackgroundColor3 = PENDING_BUTTON_COLOR
			btn.Text = "..."
			btn.Active = false
			btn.AutoButtonColor = false

			Remotes.UpgradeCannon:FireServer(entry.amount)

			task.delay(5, function()
				if purchasePending then
					purchasePending = false
					if btn and btn.Parent then
						refreshUI()
					end
				end
			end)
		else
			btn.Active = false
			btn.AutoButtonColor = false
			btn.Text = "X"
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)

			task.delay(1, function()
				if btn and btn.Parent then
					refreshUI()
				end
			end)
		end
	end)
end

local function closeShop()
	if shopGui then
		shopGui:Destroy()
		shopGui = nil
		badgeLabel = nil
		rowRefs = {}
	end
	isOpen = false
	manuallyClosed = true
	purchasePending = false
end

local function onPowerChanged()
	if not isOpen then
		return
	end
	purchasePending = false
	refreshUI()
	updateCannonBillboards()
end

local function openShop()
	if isOpen then
		return
	end

	isOpen = true
	rowRefs = {}

	local screen = Instance.new("ScreenGui")
	screen.Name = "CannonShopGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Parent = playerGui
	shopGui = screen

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(0.65, 0.7)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	main.BackgroundTransparency = 0.1
	main.Parent = screen

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 15)
	mainCorner.Parent = main

	attachPanelTexture(main, 0.88)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.2
	aspect.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Thickness = 3
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = main

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.14)
	header.BackgroundColor3 = Color3.fromRGB(145, 19, 195)
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
	title.Text = "UPGRADES"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 4
	titleStroke.Parent = title

	local powerHeader = Instance.new("TextLabel")
	powerHeader.Name = "PowerHeader"
	powerHeader.Size = UDim2.fromScale(0.4, 0.055)
	powerHeader.Position = UDim2.fromScale(0.06, 0.21)
	powerHeader.BackgroundTransparency = 1
	powerHeader.Text = "💥POWER: " .. getCannonPower()
	powerHeader.TextColor3 = Color3.fromRGB(80, 200, 80)
	powerHeader.Font = Enum.Font.DenkOne
	powerHeader.TextScaled = true
	powerHeader.TextXAlignment = Enum.TextXAlignment.Left
	powerHeader.Parent = main
	badgeLabel = powerHeader

	local pStroke = Instance.new("UIStroke")
	pStroke.Thickness = 2.5
	pStroke.Color = Color3.fromRGB(0, 0, 0)
	pStroke.Parent = powerHeader

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

	closeBtn.MouseButton1Click:Connect(closeShop)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.Size = UDim2.fromScale(0.92, 0.66)
	scroll.Position = UDim2.fromScale(0.5, 0.62)
	scroll.AnchorPoint = Vector2.new(0.5, 0.5)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = main

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll

	for _, entry in ipairs(Config.CannonUpgradeCosts) do
		buildRow(scroll, entry)
	end

	scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 25)
	refreshUI()
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function CannonShopClient.start()
	player.AttributeChanged:Connect(function(attr)
		if attr == "CannonPower" then
			onPowerChanged()
			updateCannonBillboards()
		end
	end)

	task.spawn(spawnRings)

	task.spawn(function()
		local map = workspace:WaitForChild("Map", 10)
		if not map then
			return
		end

		local attempts = 0
		while attempts < 20 do
			local models = getCannonModels()
			if #models > 0 then
				updateCannonBillboards()
				return
			end
			attempts += 1
			task.wait(0.5)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheck < CHECK_INTERVAL then
			return
		end
		lastCheck = now

		updateBillboardVisibility()

		if purchasePending then
			return
		end

		local dist = getClosestDist()
		local closeDist = getClosestDist(Config.ShopRingClosePadding)

		if not isOpen and not manuallyClosed and dist <= OPEN_DIST then
			openShop()
		elseif isOpen and closeDist > CLOSE_DIST then
			manuallyClosed = false
			closeShop()
		elseif not isOpen and manuallyClosed and closeDist > CLOSE_DIST then
			manuallyClosed = false
		end
	end)
end

return CannonShopClient
