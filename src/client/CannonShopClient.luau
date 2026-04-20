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

local RING_RADIUS  = 9.5
local RING_COLOR   = Color3.fromRGB(80, 200, 255)
local RING_Y_DROP  = 6.35
local OPEN_DIST    = RING_RADIUS
local CLOSE_DIST   = RING_RADIUS + 1

local isOpen          = false
local manuallyClosed  = false
local purchasePending = false
local lastCheck       = 0
local CHECK_INTERVAL  = 0.5

local shopGui    = nil
local badgeLabel = nil
local rowRefs    = {}
local billboards = {}

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
		local ok, pos = pcall(function() return shop:GetPivot().Position end)
		if ok then
			local d = (hrp.Position - pos).Magnitude
			if d < closest then closest = d end
		end
	end
	return closest
end

-- ── Ground rings ──────────────────────────────────────────────────────────────

local function spawnRings()
	task.wait(2)
	for _, shop in getCannonShops() do
		local pivot = shop:GetPivot().Position
		local ringY = pivot.Y - RING_Y_DROP

		local ring = Instance.new("Part")
		ring.Anchored     = true
		ring.CanCollide   = false
		ring.CanQuery     = false
		ring.CastShadow   = false
		ring.Shape        = Enum.PartType.Cylinder
		ring.Size         = Vector3.new(0.05, RING_RADIUS * 2, RING_RADIUS * 2)
		ring.CFrame       = CFrame.new(pivot.X, ringY, pivot.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material     = Enum.Material.Neon
		ring.Color        = RING_COLOR
		ring.Transparency = 0.78
		ring.Parent       = workspace
	end
end

-- ── Cannon power billboards ───────────────────────────────────────────────────

local function getCannonPower()
	return player:GetAttribute("CannonPower") or 0
end

local function updateCannonBillboards()
	local power = getCannonPower()
	local text = power > 0 and tostring(power) or "0"

	for _, cannon in getCannonModels() do
		if not cannon:FindFirstChild("PowerBillboard") then
			local billboard = Instance.new("BillboardGui")
			billboard.Name           = "PowerBillboard"
			billboard.Size           = UDim2.new(0, 120, 0, 60)
			local _, size = cannon:GetBoundingBox()
            billboard.StudsOffset = Vector3.new(0, (size.Y / 2) + 8, 0)
			billboard.AlwaysOnTop    = true
			billboard.LightInfluence = 0
			billboard.Parent         = cannon

			local label = Instance.new("TextLabel")
			label.Name                   = "PowerLabel"
			label.Size                   = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3             = Color3.fromRGB(255, 215, 0)
			label.Font                   = Enum.Font.GothamBold
			label.TextScaled             = true
			label.Parent                 = billboard

			local stroke = Instance.new("UIStroke")
			stroke.Color     = Color3.fromRGB(0, 0, 0)
			stroke.Thickness = 3
			stroke.Parent    = label

			table.insert(billboards, billboard)
		end

		local bill = cannon:FindFirstChild("PowerBillboard")
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
		local bill = cannon:FindFirstChild("PowerBillboard")
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

local function computeCost(baseCost, currentPower)
	if currentPower == 0 then return 0 end
	return math.floor(baseCost * (Config.CannonCostScale ^ currentPower))
end

local function costText(baseCost, currentPower)
	local cost = computeCost(baseCost, currentPower)
	return cost == 0 and "FREE" or (Util.formatMoney(cost))
end

local function refreshUI()
	local power = getCannonPower()
	if badgeLabel then badgeLabel.Text = tostring(power) end
	for _, row in rowRefs do
		if row.label then
			row.label.Text = "+" .. row.entry.amount .. " Power\n" .. power .. " → " .. (power + row.entry.amount)
		end
		if row.btn and row.btn.Active then
			row.btn.Text = costText(row.entry.cost, power)
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
end

local function onPowerChanged()
	if not isOpen then return end
	purchasePending = false
	refreshUI()
	for _, row in rowRefs do
		if row.btn then
			row.btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
			row.btn.Text             = costText(row.entry.cost, getCannonPower())
			row.btn.Active           = true
		end
	end
	updateCannonBillboards()
end

local function buildRow(parent, yPos, entry)
	local frame = Instance.new("Frame")
	frame.Size     = UDim2.new(1, -20, 0, 80)
	frame.Position = UDim2.new(0, 10, 0, yPos)
	frame.BackgroundColor3 = Color3.fromRGB(220, 240, 255)
	frame.BorderSizePixel  = 0
	frame.Parent = parent
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local power = getCannonPower()

	local label = Instance.new("TextLabel")
	label.Size     = UDim2.new(0.6, 0, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "+" .. entry.amount .. " Power\n" .. power .. " → " .. (power + entry.amount)
	label.TextColor3     = Color3.fromRGB(0, 120, 200)
	label.Font           = Enum.Font.GothamBold
	label.TextScaled     = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Size     = UDim2.new(0.32, 0, 0.55, 0)
	btn.Position = UDim2.new(0.65, 0, 0.22, 0)
	btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	btn.Text       = costText(entry.cost, power)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font       = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.Parent = frame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	table.insert(rowRefs, {label = label, btn = btn, entry = entry})

	btn.MouseButton1Click:Connect(function()
        if not btn.Active then return end

        local currentCost = computeCost(entry.cost, getCannonPower())
        local money = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Money")

        if money and money.Value < currentCost then
            -- Can't afford — flash red X then restore
            btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            btn.Text = "X"
            task.delay(0.8, function()
                if btn and btn.Parent then
                    btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
                    btn.Text = costText(entry.cost, getCannonPower())
                end
            end)
            return
        end

        purchasePending      = true
        btn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
        btn.Text             = "..."
        btn.Active           = false
        Remotes.UpgradeCannon:FireServer(entry.amount)
    end)
end

local function openShop()
	if isOpen then return end
	isOpen  = true
	rowRefs = {}

	local rowCount    = #Config.CannonUpgradeCosts
	local frameHeight = 60 + rowCount * 95 + 20

	local screen = Instance.new("ScreenGui")
	screen.Name         = "CannonShopGui"
	screen.ResetOnSpawn = false
	screen.Parent       = playerGui
	shopGui = screen

	local main = Instance.new("Frame")
	main.Size        = UDim2.new(0, 360, 0, frameHeight)
	main.Position    = UDim2.new(0.5, 0, 0.5, 0)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Color3.fromRGB(240, 250, 255)
	main.BorderSizePixel  = 0
	main.Parent = screen
	Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

	local vp = workspace.CurrentCamera.ViewportSize
	local scale = math.clamp(math.min(vp.X / 480, vp.Y / 720), 0.5, 1.2)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale  = scale
	uiScale.Parent = main

	local title = Instance.new("TextLabel")
	title.Size     = UDim2.new(0.8, 0, 0, 50)
	title.Position = UDim2.new(0, 10, 0, 5)
	title.BackgroundTransparency = 1
	title.Text       = "⚡ UPGRADE"
	title.TextColor3 = Color3.fromRGB(30, 30, 30)
	title.Font       = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = main

	local badge = Instance.new("TextLabel")
	badge.Size     = UDim2.new(0, 50, 0, 30)
	badge.Position = UDim2.new(0, 10, 0, 55)
	badge.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	badge.Text       = tostring(getCannonPower())
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font       = Enum.Font.GothamBold
	badge.TextScaled = true
	badge.Parent = main
	badgeLabel = badge
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 6)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size     = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -45, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.Text       = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font       = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.Parent = main
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	closeBtn.MouseButton1Click:Connect(function()
		manuallyClosed  = true
		purchasePending = false
		closeShop()
		task.delay(3, function()
			manuallyClosed = false
		end)
	end)

	for i, entry in ipairs(Config.CannonUpgradeCosts) do
		buildRow(main, 55 + (i - 1) * 95 + 30, entry)
	end
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

        updateBillboardVisibility()  -- ADD THIS
    end)
end

return CannonShopClient