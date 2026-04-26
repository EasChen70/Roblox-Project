local BrainrotUI = {}

local Util = require(game.ReplicatedStorage.Util)
local Brainrots = require(game.ReplicatedStorage.Brainrots)

local MAX_VISIBILITY_DISTANCE = 80

local RarityColors = {
	Common = Color3.fromRGB(85, 255, 85),
	Rare = Color3.fromRGB(0, 170, 255),
	Epic = Color3.fromRGB(170, 0, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
	Secret = Color3.fromRGB(50, 50, 50),
	Divine = Color3.fromRGB(209, 35, 232),
}

local LEVEL_COLOR = Color3.fromRGB(255, 215, 0)
local UPGRADE_PINK = Color3.fromRGB(255, 60, 160)
local UPGRADE_TEXT = Color3.fromRGB(255, 255, 255)

local function makeLabel(name, text, color, order)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextColor3 = color
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.2)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.LayoutOrder = order

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

local function createBillboardGui(model, studsOffset, alwaysOnTop)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BrainrotBillboard"
	billboard.Size = UDim2.fromScale(8, 5)
	billboard.MaxDistance = MAX_VISIBILITY_DISTANCE

	if not studsOffset then
		local extents = model:GetExtentsSize()
		studsOffset = Vector3.new(0, extents.Y / 2 + 8, 0)
	end

	billboard.StudsOffset = studsOffset
	billboard.AlwaysOnTop = alwaysOnTop or false
	billboard.LightInfluence = 0
	billboard.Parent = model.PrimaryPart

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	return billboard, frame
end

local function formatLevelText(level, maxLevel)
	if maxLevel and level >= maxLevel then
		return "Max Level"
	end
	return "Level " .. level
end

function BrainrotUI.createBillboard(model, data)
	local rarity = data.rarity or "Common"
	local rarityColor = RarityColors[rarity] or RarityColors.Common
	local level = data.level
	local maxLevel = data.maxLevel

	local billboard, frame = createBillboardGui(model, nil, false)
	if level then
		billboard.Size = UDim2.fromScale(8, 6)
	end
	local mutation = data.mutation or "None"
	if mutation ~= "None" then
		local mutColor = mutation == "Diamond" and Color3.fromRGB(100, 220, 255) or Color3.fromRGB(255, 200, 50)
		local mutLabel = makeLabel("Mutation", "✦ " .. mutation:upper(), mutColor, -1)
		mutLabel.Parent = frame
	end
	if level then
		local levelLabel = makeLabel("Level", formatLevelText(level, maxLevel), LEVEL_COLOR, 0)
		levelLabel.Parent = frame
	end

	local incomeLabel = makeLabel("Income", Util.formatMoney(data.incomePerSec) .. "/s", Color3.fromRGB(85, 255, 85), 1)
	incomeLabel.Parent = frame

	local nameLabel = makeLabel("Name", data.name, Color3.fromRGB(255, 255, 255), 2)
	nameLabel.Parent = frame

	local rarityLabel = makeLabel("Rarity", rarity, rarityColor, 3)
	rarityLabel.Parent = frame
	if rarity == "Secret" then
		local stroke = rarityLabel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Thickness = 0.5
		end
	end

	return billboard
end

function BrainrotUI.updateBillboardLevel(model, newLevel, newIncome, maxLevel)
	local billboard = model.PrimaryPart and model.PrimaryPart:FindFirstChild("BrainrotBillboard")
	if not billboard then
		return
	end

	local frame = billboard:FindFirstChild("Container")
	if not frame then
		return
	end

	local incomeLabel = frame:FindFirstChild("Income")
	if incomeLabel then
		incomeLabel.Text = Util.formatMoney(newIncome) .. "/s"
	end

	local levelLabel = frame:FindFirstChild("Level")
	if levelLabel then
		levelLabel.Text = formatLevelText(newLevel, maxLevel)
	end
end

function BrainrotUI.createWorldBillboard(model, data)
    local rarity = data.rarity or "Common"
    local rarityColor = RarityColors[rarity] or RarityColors.Common

    local billboard, frame = createBillboardGui(model, Vector3.new(0, 12, 0), true)
    billboard.Size = UDim2.fromScale(8, 6)
    
    local mutation = data.mutation or "None"
    if mutation ~= "None" then
        local mutColor = mutation == "Diamond" and Color3.fromRGB(100, 220, 255) or Color3.fromRGB(255, 200, 50)
        local mutLabel = makeLabel("Mutation", "✦ " .. mutation:upper(), mutColor, -1)
        mutLabel.Parent = frame
    end
    
    local timerLabel = makeLabel("Timer", "", Color3.fromRGB(255, 255, 255), 0)

    local despawnTime = model:GetAttribute("DespawnRemaining")
    if despawnTime then
        timerLabel.Text = "🕐 " .. math.ceil(despawnTime) .. "s"
        timerLabel.Parent = frame
    end

    local incomeLabel = makeLabel("Income", Util.formatMoney(data.incomePerSec) .. "/s", Color3.fromRGB(85, 255, 85), 1)
    incomeLabel.Parent = frame

    local nameLabel = makeLabel("Name", data.name, Color3.fromRGB(255, 255, 255), 2)
    nameLabel.Parent = frame

    local rarityLabel = makeLabel("Rarity", rarity, rarityColor, 3)
    rarityLabel.Parent = frame

    if rarity == "Secret" then
        local stroke = rarityLabel:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = Color3.fromRGB(255, 255, 255)
            stroke.Thickness = 0.5
        end
    end

    -- === OPTIMIZED TICK() TIMER LOGIC ===
    if despawnTime then
        local currentRemaining = despawnTime
        local localStartTime = tick()

        -- Listen for state changes from the server (e.g. Pause/Resume)
        model:GetAttributeChangedSignal("DespawnRemaining"):Connect(function()
            currentRemaining = model:GetAttribute("DespawnRemaining") or 0
            localStartTime = tick() -- Reset our local clock to match the new server reality
        end)

        task.spawn(function()
            while model.Parent and billboard.Parent do
                -- Calculate display time locally, 0 network cost
                local elapsed = tick() - localStartTime
                local displayTime = math.max(0, currentRemaining - elapsed)
                
                timerLabel.Text = "🕐 " .. math.ceil(displayTime) .. "s"
                
                if displayTime <= 10 then
                    timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
                else
                    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- Reset color just in case
                end
                
                -- We don't break on <= 0 here because the server handles the actual destruction.
                -- It will just sit at 0s for a split second before the model is destroyed.
                
                task.wait(0.5) -- Runs twice a second for a slightly smoother visual update
            end
        end)
    end

    return billboard
end

local function getUpgradeSignCFrame(slot)
	local collectButton = slot:FindFirstChild("CollectButton")
	local point = slot:FindFirstChild("PlacementPoint")
	if not point then
		return nil
	end

	local forward = point.CFrame.LookVector
	local pos

	if collectButton then
		local pullBack = forward * 2
		pos = collectButton.Position + pullBack + Vector3.new(0, 1.5, 0)
	else
		pos = point.Position + forward * 3 + Vector3.new(0, 1.2, 0)
	end

	local facingDir = -forward
	local tiltAngle = math.rad(15)
	local baseCFrame = CFrame.new(pos, pos + facingDir)
	local tiltedCFrame = baseCFrame * CFrame.Angles(tiltAngle, 0, 0)

	return tiltedCFrame
end

function BrainrotUI.createUpgradeBillboard(slot, data)
	local rarity = data.rarity
	local level = data.level or 1
	local baseIncome = data.baseIncome

	local anchor = getUpgradeSignCFrame(slot)
	if not anchor then
		return nil
	end

	local existing = slot:FindFirstChild("UpgradeBillboard")
	if existing then
		existing:Destroy()
	end

	local sign = Instance.new("Part")
	sign.Name = "UpgradeAnchor"
	sign.Size = Vector3.new(4, 1.5, 0.1)
	sign.Material = Enum.Material.SmoothPlastic
	sign.Color = UPGRADE_PINK
	sign.CanCollide = false
	sign.Anchored = true
	sign.CFrame = anchor
	sign.TopSurface = Enum.SurfaceType.Smooth
	sign.BottomSurface = Enum.SurfaceType.Smooth

	local outline = Instance.new("SelectionBox")
	outline.Name = "Outline"
	outline.Adornee = sign
	outline.LineThickness = 0.02
	outline.Color3 = Color3.fromRGB(0, 0, 0)
	outline.SurfaceColor3 = Color3.fromRGB(0, 0, 0)
	outline.SurfaceTransparency = 1
	outline.Parent = sign

	local model = Instance.new("Model")
	model.Name = "UpgradeBillboard"
	sign.Parent = model
	model.PrimaryPart = sign
	model.Parent = slot

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "UpgradeGui"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(400, 200)
	surfaceGui.LightInfluence = 0
	surfaceGui.AlwaysOnTop = false
	surfaceGui.Parent = sign

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = surfaceGui

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.fromScale(1, 0.65)
	topRow.Position = UDim2.new(0, 0, 0, 0)
	topRow.BackgroundTransparency = 1
	topRow.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Text = "⬆"
	arrow.Font = Enum.Font.LuckiestGuy
	arrow.TextScaled = true
	arrow.TextColor3 = LEVEL_COLOR
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(0.22, 1)
	arrow.Position = UDim2.fromScale(0.04, 0)
	arrow.Parent = topRow

	local arrowStroke = Instance.new("UIStroke")
	arrowStroke.Color = Color3.fromRGB(0, 0, 0)
	arrowStroke.Thickness = 3
	arrowStroke.Parent = arrow

	local cost = Brainrots.getUpgradeCost(baseIncome, rarity, level) or 0
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Text = Util.formatMoney(cost)
	costLabel.Font = Enum.Font.LuckiestGuy
	costLabel.TextScaled = true
	costLabel.TextColor3 = UPGRADE_TEXT
	costLabel.BackgroundTransparency = 1
	costLabel.Size = UDim2.fromScale(0.7, 1)
	costLabel.Position = UDim2.fromScale(0.28, 0)
	costLabel.Parent = topRow

	local costStroke = Instance.new("UIStroke")
	costStroke.Color = Color3.fromRGB(0, 0, 0)
	costStroke.Thickness = 3
	costStroke.Parent = costLabel

	local transitionLabel = Instance.new("TextLabel")
	transitionLabel.Name = "Transition"
	transitionLabel.Text = "Level " .. level .. " → Level " .. (level + 1)
	transitionLabel.Font = Enum.Font.LuckiestGuy
	transitionLabel.TextScaled = true
	transitionLabel.TextColor3 = UPGRADE_TEXT
	transitionLabel.BackgroundTransparency = 1
	transitionLabel.Size = UDim2.fromScale(1, 0.3)
	transitionLabel.Position = UDim2.fromScale(0, 0.68)
	transitionLabel.Parent = frame

	local transitionStroke = Instance.new("UIStroke")
	transitionStroke.Color = Color3.fromRGB(0, 0, 0)
	transitionStroke.Thickness = 2
	transitionStroke.Parent = transitionLabel

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Name = "UpgradePrompt"
	clickDetector.MaxActivationDistance = 16
	clickDetector.CursorIcon = ""
	clickDetector.Parent = sign

	return model
end

function BrainrotUI.updateUpgradeBillboard(billboardModel, newCost, newLevel)
	if not billboardModel then
		return
	end
	local sign = billboardModel.PrimaryPart
	if not sign then
		return
	end

	local gui = sign:FindFirstChild("UpgradeGui")
	if not gui then
		return
	end

	local container = gui:FindFirstChild("Container")
	if not container then
		return
	end

	local topRow = container:FindFirstChild("TopRow")
	if topRow then
		local costLabel = topRow:FindFirstChild("Cost")
		if costLabel then
			costLabel.Text = Util.formatMoney(newCost)
		end
	end

	local transitionLabel = container:FindFirstChild("Transition")
	if transitionLabel then
		transitionLabel.Text = "Level " .. newLevel .. " → Level " .. (newLevel + 1)
	end
end

function BrainrotUI.setUpgradeBillboardMax(billboardModel)
	if not billboardModel then
		return
	end
	local sign = billboardModel.PrimaryPart
	if not sign then
		return
	end

	local gui = sign:FindFirstChild("UpgradeGui")
	if not gui then
		return
	end

	local container = gui:FindFirstChild("Container")
	if not container then
		return
	end

	local topRow = container:FindFirstChild("TopRow")
	if topRow then
		local arrow = topRow:FindFirstChild("Arrow")
		if arrow then
			arrow.Visible = false
		end

		local costLabel = topRow:FindFirstChild("Cost")
		if costLabel then
			costLabel.Text = "MAX"
			costLabel.Size = UDim2.fromScale(1, 1)
			costLabel.Position = UDim2.fromScale(0, 0)
			costLabel.TextColor3 = LEVEL_COLOR
		end
	end

	local transitionLabel = container:FindFirstChild("Transition")
	if transitionLabel then
		transitionLabel.Text = "Max Level"
		transitionLabel.TextColor3 = LEVEL_COLOR
	end

	local prompt = sign:FindFirstChild("UpgradePrompt")
	if prompt then
		prompt.MaxActivationDistance = 0
	end
end

return BrainrotUI
