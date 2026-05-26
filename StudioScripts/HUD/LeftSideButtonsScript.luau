local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local leaderstats = player:WaitForChild("leaderstats")
local rebirthsStat = leaderstats:WaitForChild("Rebirths")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local function createSquareButton(name, text, imageId, position, bgColor, iconScale)
	iconScale = iconScale or 0.65

	local screen = Instance.new("ScreenGui")
	screen.Name = name .. "Gui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui

	local btn = Instance.new("TextButton")
	btn.Name = name .. "Button"
	btn.Size = UDim2.new(0.13, 0, 0.13, 0)
	btn.Position = position
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.BackgroundColor3 = bgColor
	btn.BackgroundTransparency = 0.4
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Parent = screen

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://" .. imageId:match("%d+")
	icon.Size = UDim2.new(iconScale, 0, iconScale, 0)
	icon.Position = UDim2.new(0.5, 0, 0.38, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ImageTransparency = 0.1
	icon.ZIndex = 2
	icon.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.9, 0, 0.2, 0)
	label.Position = UDim2.new(0.5, 0, 0.82, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.DenkOne
	label.TextScaled = true
	label.ZIndex = 3
	label.Parent = btn

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2.5
	textStroke.Parent = label

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = btn

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(0, 0, 0)
	buttonStroke.Thickness = 3.5
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = btn

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 15)

	btn.MouseEnter:Connect(function()
		btn:TweenSize(UDim2.new(0.14, 0, 0.14, 0), "Out", "Quad", 0.15, true)
		btn.BackgroundTransparency = 0.2
	end)

	btn.MouseLeave:Connect(function()
		btn:TweenSize(UDim2.new(0.13, 0, 0.13, 0), "Out", "Quad", 0.15, true)
		btn.BackgroundTransparency = 0.4
	end)

	btn.MouseButton1Down:Connect(function()
		btn:TweenSize(UDim2.new(0.12, 0, 0.12, 0), "In", "Quad", 0.05, true)
	end)

	btn.MouseButton1Up:Connect(function()
		btn:TweenSize(UDim2.new(0.14, 0, 0.14, 0), "Out", "Quad", 0.05, true)
	end)

	return btn
end

local function createCartoonyAlertBadge(parent)
	local badge = Instance.new("Frame")
	badge.Name = "ReadyAlertBadge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.BackgroundTransparency = 1
	badge.Visible = false
	badge.Rotation = -4
	badge.ZIndex = 10
	badge.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = badge

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(0.96, 0.96)
	shadow.Position = UDim2.fromScale(0.06, 0.06)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.2
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 10
	shadow.Parent = badge
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(1, 0)

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromScale(0.92, 0.92)
	bubble.BackgroundColor3 = Color3.fromRGB(235, 56, 52)
	bubble.BorderSizePixel = 0
	bubble.Rotation = 3
	bubble.ZIndex = 11
	bubble.Parent = badge
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(1, 0)

	local alertText = Instance.new("TextLabel")
	alertText.Name = "AlertText"
	alertText.Size = UDim2.fromScale(0.68, 0.68)
	alertText.Position = UDim2.fromScale(0.5, 0.48)
	alertText.AnchorPoint = Vector2.new(0.5, 0.5)
	alertText.BackgroundTransparency = 1
	alertText.Font = Enum.Font.DenkOne
	alertText.Text = "!"
	alertText.TextColor3 = Color3.fromRGB(255, 248, 198)
	alertText.TextScaled = true
	alertText.Rotation = 4
	alertText.ZIndex = 12
	alertText.Parent = badge

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.Parent = alertText

	return {
		Root = badge,
		Scale = scale,
	}
end

local function setCartoonyAlertBadgeVisible(badgeData, shouldShow)
	local badge = badgeData.Root
	if badge.Visible == shouldShow then
		return
	end

	if shouldShow then
		badge.Visible = true
		badge.Rotation = -10
		badgeData.Scale.Scale = 0.45
		TweenService:Create(
			badgeData.Scale,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1}
		):Play()
		TweenService:Create(
			badge,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Rotation = -4}
		):Play()
	else
		badge.Visible = false
		badge.Rotation = -4
		badgeData.Scale.Scale = 1
	end
end

local shopBtn = createSquareButton(
	"Shop",
	"SHOP",
	"77580506639212",
	UDim2.new(0.01, 0, 0.25, 0),
	Color3.fromRGB(30, 35, 45),
	0.80
)

local rebirthBtn = createSquareButton(
	"Rebirth",
	"REBIRTH",
	"99330025492372",
	UDim2.new(0.01, 0, 0.40, 0),
	Color3.fromRGB(30, 30, 30),
	0.65
)

local rebirthReadyBadge = createCartoonyAlertBadge(rebirthBtn)
rebirthReadyBadge.Root.Size = UDim2.fromScale(0.29, 0.29)
rebirthReadyBadge.Root.Position = UDim2.fromScale(1.03, -0.03)

local function getNextRebirthRequirement()
	return Config.RebirthRequirements[rebirthsStat.Value + 1]
end

local function canPlayerRebirthNow()
	local nextReq = getNextRebirthRequirement()
	if not nextReq then
		return false
	end

	local currentPower = player:GetAttribute("CannonPower") or 1
	return currentPower >= nextReq.power
end

local function updateRebirthReadyBadge()
	setCartoonyAlertBadgeVisible(rebirthReadyBadge, canPlayerRebirthNow())
end

local rebirthGuiOpen = false

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

local function closeRebirthGui()
	local existing = playerGui:FindFirstChild("RebirthPopupGui")
	if existing then existing:Destroy() end
	rebirthGuiOpen = false
end

local function openRebirthGui()
	if rebirthGuiOpen then return end
	rebirthGuiOpen = true

	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local rebirthRemote = remotes:WaitForChild("Rebirth")

	local currentRebirths = rebirthsStat.Value
	local currentPower = player:GetAttribute("CannonPower") or 1
	local currentMult = player:GetAttribute("RebirthMultiplier") or Config.RebirthBaseMultiplier
	local nextReq = Config.RebirthRequirements[currentRebirths + 1]
	local isMaxed = nextReq == nil
	local canRebirth = not isMaxed and currentPower >= nextReq.power

	local screen = Instance.new("ScreenGui")
	screen.Name = "RebirthPopupGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui

	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.5, 0.55)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 15)
	Instance.new("UIAspectRatioConstraint", panel).AspectRatio = 1.6
	
	attachPanelTexture(panel, 0.88)

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 255, 255)
	panelStroke.Thickness = 3
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.15)
	title.Position = UDim2.fromScale(0.5, 0.06)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "⟳ REBIRTH"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.Parent = panel
	local tStroke = Instance.new("UIStroke")
	tStroke.Thickness = 3
	tStroke.Color = Color3.fromRGB(0, 0, 0)
	tStroke.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromScale(0.07, 0.12)
	closeBtn.Position = UDim2.fromScale(0.97, 0.03)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	-- CHANGED: Updated background color and text color to match closeBtn in TimedRewards 
	closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
	closeBtn.Font = Enum.Font.DenkOne
	closeBtn.TextScaled = true
	closeBtn.Parent = panel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	-- CHANGED: Applied texture to the close button 
	attachPanelTexture(closeBtn, 0.76)
	
	local xStroke = Instance.new("UIStroke")
	-- CHANGED: Updated stroke color to white and added ApplyStrokeMode to match 
	xStroke.Color = Color3.fromRGB(255, 255, 255)
	xStroke.Thickness = 3
	xStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	xStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(closeRebirthGui)

	local statsFrame = Instance.new("Frame")
	statsFrame.Size = UDim2.fromScale(0.88, 0.42)
	statsFrame.Position = UDim2.fromScale(0.5, 0.25)
	statsFrame.AnchorPoint = Vector2.new(0.5, 0)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.04, 0)
	layout.Parent = statsFrame

	local function makeStatBox(labelText, valueText, color)
		local box = Instance.new("Frame")
		box.Size = UDim2.fromScale(0.42, 1)
		box.BackgroundColor3 = color
		box.BackgroundTransparency = 0.3
		box.BorderSizePixel = 0
		box.Parent = statsFrame
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
		local bStroke = Instance.new("UIStroke")
		bStroke.Color = Color3.fromRGB(255, 255, 255)
		bStroke.Thickness = 2
		bStroke.Parent = box

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 0.4)
		lbl.Position = UDim2.fromScale(0.5, 0.15)
		lbl.AnchorPoint = Vector2.new(0.5, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = labelText
		lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
		lbl.Font = Enum.Font.DenkOne
		lbl.TextScaled = true
		lbl.Parent = box
		local lStroke = Instance.new("UIStroke")
		lStroke.Thickness = 2
		lStroke.Color = Color3.fromRGB(0, 0, 0)
		lStroke.Parent = lbl

		local val = Instance.new("TextLabel")
		val.Size = UDim2.fromScale(1, 0.45)
		val.Position = UDim2.fromScale(0.5, 0.52)
		val.AnchorPoint = Vector2.new(0.5, 0)
		val.BackgroundTransparency = 1
		val.Text = valueText
		val.TextColor3 = Color3.fromRGB(255, 255, 255)
		val.Font = Enum.Font.DenkOne
		val.TextScaled = true
		val.Parent = box
		local vStroke = Instance.new("UIStroke")
		vStroke.Thickness = 3
		vStroke.Color = Color3.fromRGB(0, 0, 0)
		vStroke.Parent = val

		return box
	end

	local currentMultText = string.format("x%.1f CASH", currentMult)
	local currentText = "Rebirth " .. currentRebirths .. "\n" .. currentMultText
	makeStatBox("CURRENT", currentText, Color3.fromRGB(40, 100, 40))

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(0.08, 1)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▶"
	arrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	arrow.Font = Enum.Font.DenkOne
	arrow.TextScaled = true
	arrow.Parent = statsFrame
	local aStroke = Instance.new("UIStroke")
	aStroke.Thickness = 3
	aStroke.Color = Color3.fromRGB(0, 0, 0)
	aStroke.Parent = arrow

	if isMaxed then
		makeStatBox("NEXT", "MAXED!", Color3.fromRGB(180, 140, 0))
	else
		local nextMultText = string.format("x%.1f CASH", nextReq.multiplier)
		local nextText = "Rebirth " .. (currentRebirths + 1) .. "\n" .. nextMultText
		makeStatBox("NEXT", nextText, Color3.fromRGB(180, 100, 0))
	end

	local barContainer = Instance.new("Frame")
	barContainer.Size = UDim2.fromScale(0.88, 0.1)
	barContainer.Position = UDim2.fromScale(0.5, 0.70)
	barContainer.AnchorPoint = Vector2.new(0.5, 0)
	barContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barContainer.BorderSizePixel = 0
	barContainer.Parent = panel
	Instance.new("UICorner", barContainer).CornerRadius = UDim.new(1, 0)
	local barContainerStroke = Instance.new("UIStroke")
	barContainerStroke.Color = Color3.fromRGB(255, 255, 255)
	barContainerStroke.Thickness = 2
	barContainerStroke.Parent = barContainer

	local fillRatio = isMaxed and 1 or math.clamp(currentPower / nextReq.power, 0, 1)
	local fillColor = canRebirth and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(220, 140, 30)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(fillRatio, 1)
	barFill.BackgroundColor3 = fillColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barContainer
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	local barLabel = Instance.new("TextLabel")
	barLabel.Size = UDim2.fromScale(1, 1)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = Enum.Font.DenkOne
	barLabel.TextScaled = true
	barLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	barLabel.ZIndex = 2
	barLabel.Parent = barContainer
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 2.5
	barStroke.Color = Color3.fromRGB(0, 0, 0)
	barStroke.Parent = barLabel

	if isMaxed then
		barLabel.Text = "✦ MAX REBIRTH REACHED ✦"
	else
		barLabel.Text = string.format("💥 %d / %d POWER", currentPower, nextReq.power)
	end

	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Size = UDim2.fromScale(0.5, 0.12)
	confirmBtn.Position = UDim2.fromScale(0.5, 0.85)
	confirmBtn.AnchorPoint = Vector2.new(0.5, 0)
	confirmBtn.BackgroundColor3 = canRebirth
		and Color3.fromRGB(220, 180, 0)
		or Color3.fromRGB(180, 40, 40)
	confirmBtn.Text = isMaxed and "MAXED" or "REBIRTH"
	confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmBtn.Font = Enum.Font.DenkOne
	confirmBtn.TextScaled = true
	confirmBtn.Active = canRebirth and not isMaxed
	confirmBtn.Parent = panel
	confirmBtn.AutoButtonColor = false
	Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 10)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Color3.fromRGB(0, 0, 0)
	cStroke.Thickness = 3
	cStroke.Parent = confirmBtn

	if canRebirth and not isMaxed then
		local TweenService = game:GetService("TweenService")
		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = Color3.fromRGB(150, 100, 0)
		glowStroke.Thickness = 4
		glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glowStroke.Parent = confirmBtn

		TweenService:Create(glowStroke,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 8 }
		):Play()

		TweenService:Create(confirmBtn,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundColor3 = Color3.fromRGB(255, 215, 0) }
		):Play()
	end

	confirmBtn.MouseButton1Click:Connect(function()
		if not confirmBtn.Active then return end
		confirmBtn.Active = false
		confirmBtn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
		confirmBtn.Text = "..."
		rebirthRemote:FireServer()

		task.delay(3, function()
			if confirmBtn and confirmBtn.Parent then
				confirmBtn.Active = true
				confirmBtn.BackgroundColor3 = Color3.fromRGB(220, 180, 0)
				confirmBtn.Text = "REBIRTH"
			end
		end)
	end)

	player:GetAttributeChangedSignal("RebirthMultiplier"):Connect(function()
		closeRebirthGui()
	end)
end

rebirthBtn.MouseButton1Click:Connect(openRebirthGui)
player:GetAttributeChangedSignal("CannonPower"):Connect(updateRebirthReadyBadge)
rebirthsStat:GetPropertyChangedSignal("Value"):Connect(updateRebirthReadyBadge)
updateRebirthReadyBadge()

-- ==========================================
-- ADDED: Rewards button moved from TopSideButtonsScript
-- This now uses createSquareButton so it scales/moves
-- together with the other left-side buttons.
-- ==========================================

local rewardsBtn = createSquareButton(
	"Rewards",
	"REWARDS",
	"99174903737611",
	UDim2.new(0.01, 0, 0.55, 0),
	Color3.fromRGB(30, 35, 45),
	0.65
)

local rewardsReadyBadge = createCartoonyAlertBadge(rewardsBtn)
rewardsReadyBadge.Root.Size = UDim2.fromScale(0.29, 0.29)
rewardsReadyBadge.Root.Position = UDim2.fromScale(1.03, -0.03)

-- ADDED:
-- Opens the already-existing rewards frame created
-- inside TopSideButtonsScript.
rewardsBtn.MouseButton1Click:Connect(function()
	local rewardsGui = playerGui:FindFirstChild("WheelSpinGui")

	if rewardsGui then
		local timedRewardsFrame = rewardsGui:FindFirstChild("TimedRewardsFrame")
		if timedRewardsFrame and timedRewardsFrame:IsA("Frame") then
			timedRewardsFrame.Visible = true
		end
	end
end)

task.spawn(function()
	local rewardsGui = playerGui:WaitForChild("WheelSpinGui")
	local timedRewardsFrame = rewardsGui:WaitForChild("TimedRewardsFrame")

	local function syncRewardsReadyBadge()
		setCartoonyAlertBadgeVisible(
			rewardsReadyBadge,
			timedRewardsFrame:GetAttribute("HasClaimableReward") == true
		)
	end

	syncRewardsReadyBadge()
	timedRewardsFrame:GetAttributeChangedSignal("HasClaimableReward"):Connect(syncRewardsReadyBadge)
end)

local indexBtn = createSquareButton(
	"Index",
	"INDEX",
	"97629410614205",
	UDim2.new(0.01, 0, 0.70, 0), -- ADDED: positioned under Index
	Color3.fromRGB(35, 30, 35),
	0.75
)

-- ==========================================
-- INDEX SYSTEM FUNCTIONALITY
-- ==========================================

local Brainrots = require(game.ReplicatedStorage:WaitForChild("Brainrots"))
local indexGuiOpen = false

-- Color mapping for rarities to make the UI look polished
local rarityColors = {
	Common = Color3.fromRGB(85, 255, 85),
	Rare = Color3.fromRGB(0, 170, 255),
	Epic = Color3.fromRGB(170, 0, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
	Secret = Color3.fromRGB(255, 255, 255),
	Divine = Color3.fromRGB(209, 35, 232),
	Exclusive = Color3.fromRGB(75, 0, 130),
	Ancient = Color3.fromRGB(85, 0, 0),
}

local function closeIndexGui()
	local existing = playerGui:FindFirstChild("IndexPopupGui")
	if existing then existing:Destroy() end
	indexGuiOpen = false
end

local function openIndexGui()
	if indexGuiOpen then return end
	indexGuiOpen = true

	-- 1. Main ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "IndexPopupGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui

	-- 2. Dark Backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = screen

	-- 3. Main Panel
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.6, 0.7)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	panel.BackgroundTransparency = 0.1
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 15)
	attachPanelTexture(panel, 0.9) 

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 255, 255)
	panelStroke.Thickness = 3
	panelStroke.Parent = panel

	-- 4. Title 
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.08) 
	title.Position = UDim2.fromScale(0.5, 0.03) 
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "✧ BRAINROT INDEX ✧"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.DenkOne
	title.TextScaled = true
	title.Parent = panel

	-- 5. Scrolling Frame 
	local scroll = Instance.new("ScrollingFrame")
	-- CHANGED: Reduced width from 0.92 to 0.72 and moved to the left to fit the right panel
	scroll.Size = UDim2.fromScale(0.72, 0.82) 
	scroll.Position = UDim2.fromScale(0.04, 0.12) -- CHANGED: Pushed to the left edge slightly
	scroll.AnchorPoint = Vector2.new(0, 0) -- CHANGED: Removed center anchor to align properly
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	scroll.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10) 
	padding.Parent = scroll

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(130, 160)
	layout.CellPadding = UDim2.fromOffset(15, 15)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll

	-- 6. Populate List from Brainrots Table
	for _, data in ipairs(Brainrots) do
		local card = Instance.new("Frame")
		card.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
		card.BorderSizePixel = 0
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = rarityColors[data.rarity] or Color3.fromRGB(255, 255, 255)
		cardStroke.Thickness = 2
		cardStroke.Parent = card

		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(0.7, 0.55)
		img.Position = UDim2.fromScale(0.5, 0.1)
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.BackgroundTransparency = 1
		img.Image = data.imageId and ("rbxassetid://" .. tostring(data.imageId):match("%d+")) or "rbxassetid://10614205" 
		img.Parent = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.fromScale(0.9, 0.18)
		nameLbl.Position = UDim2.fromScale(0.5, 0.7)
		nameLbl.AnchorPoint = Vector2.new(0.5, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = data.name:upper()
		nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLbl.Font = Enum.Font.DenkOne
		nameLbl.TextScaled = true
		nameLbl.Parent = card

		local rarityLbl = Instance.new("TextLabel")
		rarityLbl.Size = UDim2.fromScale(0.9, 0.12)
		rarityLbl.Position = UDim2.fromScale(0.5, 0.88)
		rarityLbl.AnchorPoint = Vector2.new(0.5, 0)
		rarityLbl.BackgroundTransparency = 1
		rarityLbl.Text = data.rarity
		rarityLbl.TextColor3 = rarityColors[data.rarity] or Color3.fromRGB(200, 200, 200)
		rarityLbl.Font = Enum.Font.DenkOne
		rarityLbl.TextScaled = true
		rarityLbl.Parent = card
	end

	-- ==========================================
	-- ADDED: Right-Side Rarity Banners
	-- ==========================================
	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Size = UDim2.fromScale(0.2, 0.82) -- Fits in the remaining 20% width space
	rightScroll.Position = UDim2.fromScale(0.78, 0.12) 
	rightScroll.BackgroundTransparency = 1
	rightScroll.BorderSizePixel = 0
	rightScroll.ScrollBarThickness = 4
	rightScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	rightScroll.Parent = panel

	local rightPadding = Instance.new("UIPadding")
	rightPadding.PaddingTop = UDim.new(0, 10)
	rightPadding.Parent = rightScroll

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 10) -- Space between the buttons
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rightLayout.Parent = rightScroll

	-- Ordered rarities array so buttons are displayed consistently
	local orderedRarities = {
		"Normal", "Gold", "Diamond", "Radioactive"
	}

	-- CHANGED: Added dictionary to define the specific colors requested for each banner
	local customBannerColors = {
		["Normal"] = Color3.fromRGB(140, 140, 140),       -- Grey
		["Gold"] = Color3.fromRGB(255, 200, 0),          -- Gold
		["Diamond"] = Color3.fromRGB(0, 160, 255),       -- Blue
		["Radioactive"] = Color3.fromRGB(0, 85, 0)    -- Green
	}

	for i, rarity in ipairs(orderedRarities) do
		local rBtn = Instance.new("TextButton")
		rBtn.Size = UDim2.new(0.9, 0, 0, 45) -- Fixed height, scales horizontally

		-- CHANGED: Used the new customBannerColors configuration for BackgroundColor3
		rBtn.BackgroundColor3 = customBannerColors[rarity] or rarityColors[rarity] or Color3.fromRGB(100, 100, 100)

		rBtn.Text = rarity:upper()
		rBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		rBtn.Font = Enum.Font.DenkOne
		rBtn.TextScaled = true
		rBtn.LayoutOrder = i
		rBtn.Parent = rightScroll

		local textPadding = Instance.new("UIPadding")
		textPadding.PaddingTop = UDim.new(0, 8)
		textPadding.PaddingBottom = UDim.new(0, 8)
		textPadding.Parent = rBtn

		Instance.new("UICorner", rBtn).CornerRadius = UDim.new(0, 6)

		-- Button Outline
		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(0, 0, 0)
		btnStroke.Thickness = 3
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Parent = rBtn

		-- Text Outline
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(0, 0, 0)
		textStroke.Thickness = 2
		textStroke.Parent = rBtn
	end

	-- Adjust right scroll canvas automatically
	rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		rightScroll.CanvasSize = UDim2.new(0, 0, 0, rightLayout.AbsoluteContentSize.Y + 20)
	end)
	-- ==========================================

	-- 7. Close Button 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromScale(0.07, 0.08)  
	closeBtn.Position = UDim2.fromScale(0.97, 0.03)  
	closeBtn.AnchorPoint = Vector2.new(1, 0) 
	closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20) 
	closeBtn.Text = "X" 
	closeBtn.TextColor3 = Color3.fromRGB(255, 90, 90) 
	closeBtn.Font = Enum.Font.DenkOne 
	closeBtn.TextScaled = true 
	closeBtn.Parent = panel 

	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8) 
	attachPanelTexture(closeBtn, 0.76) 

	local xStroke = Instance.new("UIStroke")
	xStroke.Color = Color3.fromRGB(255, 255, 255) 
	xStroke.Thickness = 3 
	xStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border 
	xStroke.Parent = closeBtn 

	closeBtn.MouseButton1Click:Connect(closeIndexGui)

	-- CHANGED: Automatically update main canvas size whenever the layout wraps or changes (Fixes mobile scrolling)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
	end)
end

indexBtn.MouseButton1Click:Connect(openIndexGui)
