-- client/CannonShopClient.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Util = require(ReplicatedStorage.Util)
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local CannonShopClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CANNON_BILLBOARD_DIST = 35

local RING_RADIUS = 9.5
local RING_Y_DROP = 6.35
local OPEN_DIST   = RING_RADIUS
local CLOSE_DIST  = RING_RADIUS + 1

local isOpen          = false
local manuallyClosed  = false
local purchasePending = false
local lastCheck       = 0
local CHECK_INTERVAL  = 0.5

local shopGui    = nil
local badgeLabel = nil
local rowRefs    = {}


-- ── Model finders ─────────────────────────────────────────────────────────────

local function getCannonShops()
	local map = workspace:FindFirstChild("Map")
	if not map then return {} end
	local results = {}
	for _, obj in map:GetDescendants() do
		if obj.Name == "CannonShop" and obj:IsA("Model") then
			table.insert(results, obj)
		end
	end
	return results
end

local function getCannonModels()
	local map = workspace:FindFirstChild("Map")
	if not map then return {} end
	local results = {}
	for _, obj in map:GetChildren() do
		if obj.Name == "CannonModel" and obj:IsA("Model") then
			table.insert(results, obj)
		end
	end
	return results
end

local function getClosestDist()
	local character = player.Character
	if not character then return math.huge end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end
	local closest = math.huge
	for _, shop in getCannonShops() do
		local ok, ringPos = pcall(function()
			return (shop:GetPivot() * CFrame.new(0, -RING_Y_DROP, -8)).Position
		end)
		if ok then
			-- Flat XZ distance only, same as the visual ring
			local flat = Vector3.new(ringPos.X, hrp.Position.Y, ringPos.Z)
			local d = (hrp.Position - flat).Magnitude
			if d < closest then closest = d end
		end
	end
	return closest
end

-- ── Ground rings ──────────────────────────────────────────────────────────────

local function spawnRings()
	task.wait(2)
	for _, shop in getCannonShops() do
		local shopCFrame = shop:GetPivot()
		local ringPos = (shopCFrame * CFrame.new(0, -RING_Y_DROP, -8)).Position  -- FIX: restore forward offset

		local ring = Instance.new("Part")
		ring.Anchored     = true
		ring.CanCollide   = false
		ring.CanQuery     = false
		ring.CastShadow   = false
		ring.Shape        = Enum.PartType.Cylinder
		ring.Size         = Vector3.new(0.05, RING_RADIUS * 2, RING_RADIUS * 2)
		ring.CFrame       = CFrame.new(ringPos) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material     = Enum.Material.Neon
		ring.Color        = Color3.fromRGB(145, 19, 195)  -- FIX: restore purple
		ring.Transparency = 0.78
		ring.Parent       = workspace
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
		if not cannon:FindFirstChild("PowerBillboard", true) then
			local billboard = Instance.new("BillboardGui")
			billboard.Name           = "PowerBillboard"
			billboard.Size           = UDim2.new(0, 150, 0, 70)
			local _, size = cannon:GetBoundingBox()
			billboard.StudsOffset    = Vector3.new(0, (size.Y / 2) + 8, 0)
			billboard.AlwaysOnTop    = true
			billboard.LightInfluence = 0
			local root = cannon.PrimaryPart or cannon:FindFirstChildWhichIsA("BasePart")
			if not root then continue end
			billboard.Parent = root

			local label = Instance.new("TextLabel")
			label.Name                   = "PowerLabel"
			label.Size                   = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3             = Color3.fromRGB(255, 215, 0)
			label.Font                   = Enum.Font.LuckiestGuy
			label.TextScaled             = true
			label.Parent                 = billboard

			local stroke = Instance.new("UIStroke")
			stroke.Color     = Color3.fromRGB(0, 0, 0)
			stroke.Thickness = 3
			stroke.Parent    = label

		end

		local bill = cannon:FindFirstChild("PowerBillboard", true)
		if bill then
			local lbl = bill:FindFirstChild("PowerLabel")
			if lbl then lbl.Text = text end
		end
	end
end

local function updateBillboardVisibility()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for _, cannon in getCannonModels() do
		local bill = cannon:FindFirstChild("PowerBillboard", true)
		if bill then
			local ok, pos = pcall(function() return cannon:GetPivot().Position end)
			if ok then
				local dist = (hrp.Position - pos).Magnitude
				bill.Enabled = dist <= CANNON_BILLBOARD_DIST
			end
		end
	end
end

-- ── UI ────────────────────────────────────────────────────────────────────────

local function computeCost(baseCost, currentPower, amount)
	if currentPower == 1 and amount == 1 then return 0 end
	return math.floor(baseCost * (Config.CannonCostScale ^ currentPower))
end

local function costText(baseCost, currentPower, amount)
	local cost = computeCost(baseCost, currentPower, amount)
	return cost == 0 and "FREE" or Util.formatMoney(cost)
end

local function refreshUI()
	local power = getCannonPower()
	if badgeLabel then
		badgeLabel.Text = "💥POWER:  " .. tostring(power)
	end
	for _, row in rowRefs do
		if row.label then
			row.label.Text = "+" .. row.entry.amount .. " Power\n" .. power .. " → " .. (power + row.entry.amount)
		end
		if row.btn and row.btn.Active then
			row.btn.Text = costText(row.entry.cost, power, row.entry.amount)
		end
	end
end

local function closeShop()
	if shopGui then
		shopGui:Destroy()
		shopGui    = nil
		badgeLabel = nil
		rowRefs    = {}
	end
	isOpen = false
	manuallyClosed = true  -- FIX: was missing, caused shop to instantly reopen after manual close
end

local function onPowerChanged()
	if not isOpen then return end
	purchasePending = false
	refreshUI()
	for _, row in rowRefs do
		if row.btn then
			row.btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
			row.btn.Text             = costText(row.entry.cost, getCannonPower(), row.entry.amount)
			row.btn.Active           = true
		end
	end
	updateCannonBillboards()
end

local function buildRow(parent, entry)  -- FIX: removed dead yPos parameter
	local frame = Instance.new("Frame")
	frame.Name                  = "UpgradeRow"
	frame.Size                  = UDim2.new(0.95, 0, 0, 90)
	frame.BackgroundColor3      = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel       = 0
	frame.Parent                = parent
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color            = Color3.fromRGB(255, 255, 255)
	rowStroke.Thickness        = 2.5
	rowStroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
	rowStroke.Parent           = frame

	local power = getCannonPower()

	local label = Instance.new("TextLabel")
	label.Size               = UDim2.new(0.6, 0, 0.8, 0)
	label.Position           = UDim2.new(0, 15, 0.5, 0)
	label.AnchorPoint        = Vector2.new(0, 0.5)
	label.BackgroundTransparency = 1
	label.Text               = "+" .. entry.amount .. " Power\n" .. power .. " → " .. (power + entry.amount)
	label.TextColor3         = Color3.fromRGB(255, 255, 255)
	label.Font               = Enum.Font.DenkOne
	label.TextScaled         = true
	label.TextXAlignment     = Enum.TextXAlignment.Left
	label.Parent             = frame

	local lStroke = Instance.new("UIStroke", label)
	lStroke.Thickness = 3
	lStroke.Color     = Color3.fromRGB(0, 0, 0)

	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(0.3, 0, 0.6, 0)
	btn.Position         = UDim2.new(0.95, 0, 0.5, 0)
	btn.AnchorPoint      = Vector2.new(1, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	btn.Text             = costText(entry.cost, power, entry.amount)
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.Font             = Enum.Font.DenkOne
	btn.TextScaled       = true
	btn.Active           = true
	btn.Parent           = frame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	local bStroke = Instance.new("UIStroke", btn)
	bStroke.Thickness = 3
	bStroke.Color     = Color3.fromRGB(0, 0, 0)

	table.insert(rowRefs, { label = label, btn = btn, entry = entry })

	btn.MouseButton1Click:Connect(function()
		if not btn.Active or purchasePending then return end

		local cost = computeCost(entry.cost, getCannonPower(), entry.amount)
		local playerMoney = player.leaderstats.Money.Value

		if playerMoney >= cost then
			purchasePending = true
			btn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
			btn.Text             = "..."
			btn.Active           = false

			Remotes.UpgradeCannon:FireServer(entry.amount)

			-- FIX: safety net if server never responds (disconnect, error, already max)
			task.delay(5, function()
				if purchasePending then
					purchasePending = false
					if btn and btn.Parent then
						btn.Active           = true
						btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
						btn.Text             = costText(entry.cost, getCannonPower(), entry.amount)
					end
				end
			end)
		else
			local oldText  = btn.Text
			local oldColor = btn.BackgroundColor3
			btn.Active           = false
			btn.Text             = "X"
			btn.TextColor3       = Color3.fromRGB(255, 255, 255)
			btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			bStroke.Color        = Color3.fromRGB(0, 0, 0)

			task.delay(1, function()
				if btn and btn.Parent then
					btn.Text             = oldText
					btn.BackgroundColor3 = oldColor
					btn.Active           = true
				end
			end)
		end
	end)
end

local function openShop()
	if isOpen then return end
	isOpen = true
	rowRefs = {}

	local screen = Instance.new("ScreenGui")
	screen.Name          = "CannonShopGui"
	screen.ResetOnSpawn  = false
	screen.Parent        = playerGui
	shopGui = screen

	local main = Instance.new("Frame")
	main.Size                  = UDim2.new(0.65, 0, 0.7, 0)
	main.Position              = UDim2.new(0.5, 0, 0.5, 0)
	main.AnchorPoint           = Vector2.new(0.5, 0.5)
	main.BackgroundColor3      = Color3.fromRGB(15, 15, 15)
	main.BackgroundTransparency = 0.1
	main.Parent                = screen
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 15)
	Instance.new("UIAspectRatioConstraint", main).AspectRatio = 1.2

	local mStroke = Instance.new("UIStroke", main)
	mStroke.Thickness       = 4
	mStroke.Color           = Color3.fromRGB(0, 0, 0)
	mStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local title = Instance.new("TextLabel")
	title.Size               = UDim2.new(1, 0, 0.12, 0)
	title.Position           = UDim2.new(0.5, 0, 0.02, 0)
	title.AnchorPoint        = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text               = "💥 UPGRADE"
	title.TextColor3         = Color3.fromRGB(255, 255, 255)
	title.Font               = Enum.Font.DenkOne
	title.TextScaled         = true
	title.Parent             = main
	Instance.new("UIStroke", title).Thickness = 4

	local powerHeader = Instance.new("TextLabel")
	powerHeader.Name             = "PowerHeader"
	powerHeader.Size             = UDim2.new(0.4, 0, 0.055, 0)
	powerHeader.Position         = UDim2.new(0.06, 0, 0.21, 0)
	powerHeader.BackgroundTransparency = 1
	powerHeader.Text             = "💥POWER: " .. getCannonPower()
	powerHeader.TextColor3       = Color3.fromRGB(80, 200, 80)
	powerHeader.Font             = Enum.Font.DenkOne
	powerHeader.TextScaled       = true
	powerHeader.TextXAlignment   = Enum.TextXAlignment.Left
	powerHeader.Parent           = main

	local pStroke = Instance.new("UIStroke", powerHeader)
	pStroke.Thickness = 2.5
	pStroke.Color     = Color3.fromRGB(0, 0, 0)
	badgeLabel = powerHeader

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0.07, 0, 0.07, 0)
	closeBtn.Position         = UDim2.new(0.97, 0, 0.03, 0)
	closeBtn.AnchorPoint      = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.Text             = "X"
	closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	closeBtn.Font             = Enum.Font.DenkOne
	closeBtn.TextScaled       = true
	closeBtn.Parent           = main
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	local xStroke = Instance.new("UIStroke", closeBtn)
	xStroke.Color           = Color3.fromRGB(0, 0, 0)
	xStroke.Thickness       = 3
	xStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	closeBtn.MouseButton1Click:Connect(closeShop)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size                = UDim2.new(0.92, 0, 0.66, 0)
	scroll.Position            = UDim2.new(0.5, 0, 0.62, 0)
	scroll.AnchorPoint         = Vector2.new(0.5, 0.5)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel     = 0
	scroll.ScrollBarThickness  = 6
	scroll.Parent              = main

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.Parent     = scroll

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding             = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	for _, entry in ipairs(Config.CannonUpgradeCosts) do
		buildRow(scroll, entry)  -- FIX: removed dead 0 argument
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 25)
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function CannonShopClient.start()
	player.AttributeChanged:Connect(function(attr)
		if attr == "CannonPower" then onPowerChanged() end
	end)

	task.spawn(spawnRings)

	task.spawn(function()
		task.wait(2)
		updateCannonBillboards()
	end)

	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheck < CHECK_INTERVAL then return end
		lastCheck = now

		updateBillboardVisibility()  -- MOVE: runs regardless of purchasePending

		if purchasePending then return end

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

return CannonShopClient