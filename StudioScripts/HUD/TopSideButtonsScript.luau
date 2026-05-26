local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. REMOTE EVENTS
local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local events = {
	Shop = remoteFolder:WaitForChild("TeleportRequest"),
	Sell = remoteFolder:WaitForChild("TeleportSellRequest"),
	Base = remoteFolder:WaitForChild("TeleportHomeEvent"),
	SpinWheel = remoteFolder:WaitForChild("SpinWheel"),
	ClaimTimedReward = remoteFolder:WaitForChild("ClaimTimedReward")
}

-- Access the Remotes module for GrabState
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- Track state via server updates
local isCarryingUnclaimed = false

-- Listen to the grab state from the Pickup module
Remotes.GrabStateChanged.OnClientEvent:Connect(function(state)
	isCarryingUnclaimed = state
end)

-- 2. BUTTON CONSTRUCTOR
local function createTopButton(config)
	local screen = Instance.new("ScreenGui")
	screen.Name = config.Name .. "Gui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui

	local btn = Instance.new("TextButton")
	btn.Name = config.Name .. "Button"
	btn.Size = UDim2.new(0.11, 0, 0.05, 0) 
	btn.Position = config.Position
	btn.AnchorPoint = Vector2.new(0.5, 0)
	btn.BackgroundColor3 = config.Color
	btn.BackgroundTransparency = 0.2 
	btn.Text = "" 
	btn.AutoButtonColor = false 
	btn.Parent = screen

	-- Texture
	local texture = Instance.new("ImageLabel")
	texture.Image = "rbxassetid://6927295847"
	texture.Size = UDim2.new(1, 0, 1, 0)
	texture.BackgroundTransparency = 1
	texture.ImageTransparency = 0.6
	texture.ZIndex = 1
	texture.Parent = btn
	local corner = Instance.new("UICorner", texture)
	corner.CornerRadius = UDim.new(0, 6)

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Text = config.Text
	label.Size = UDim2.new(0.8, 0, 0.8, 0) 
	label.Position = UDim2.new(0.5, 0, 0.5, 0) 
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.DenkOne
	label.TextScaled = true
	label.ZIndex = 3
	label.Parent = btn

	-- Styling
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	local blackStroke = Instance.new("UIStroke", btn)
	blackStroke.Thickness = 2
	blackStroke.Color = Color3.fromRGB(0,0,0)

	local whiteOutline = Instance.new("UIStroke", btn)
	whiteOutline.Thickness = 1.5
	whiteOutline.Color = Color3.fromRGB(255, 255, 255)
	whiteOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local tStroke = Instance.new("UIStroke", label)
	tStroke.Thickness = 2.5
	tStroke.Color = Color3.fromRGB(0,0,0)

	-- Logic
	local cooldown = false
	btn.MouseButton1Click:Connect(function()
		if cooldown then return end
		cooldown = true
		btn.Active = false

		local oldT = config.Text 

		-- Check if carrying unclaimed item
		if isCarryingUnclaimed then
			label.Text = "STASH FIRST!"
			local originalColor = btn.BackgroundColor3
			btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

			task.wait(1.5) 

			-- RESET EVERYTHING
			label.Text = oldT
			btn.BackgroundColor3 = originalColor
			btn.Active = true
			cooldown = false
			return 
		end

		-- Normal Teleport Logic
		label.Text = "WAIT..."
		config.Event:FireServer()

		task.wait(3)
		label.Text = oldT
		btn.Active = true
		cooldown = false
	end)

	-- Animations
	btn.MouseEnter:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.12, 0, 0.055, 0), "Out", "Quad", 0.1, true) end end)
	btn.MouseLeave:Connect(function() btn:TweenSize(UDim2.new(0.11, 0, 0.05, 0), "Out", "Quad", 0.1, true) end)
	btn.MouseButton1Down:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.10, 0, 0.045, 0), "In", "Quad", 0.05, true) end end)
	btn.MouseButton1Up:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.12, 0, 0.055, 0), "Out", "Quad", 0.05, true) end end)

	return btn
end

-- 3. INITIALIZE TOP BUTTONS
createTopButton({
	Name = "ShopTop", Text = "UPGRADE", 
	Position = UDim2.new(0.37, 0, 0.02, 0),
	Color = Color3.fromRGB(180, 50, 255), Event = events.Shop
})

createTopButton({
	Name = "SellTop", Text = "SELL", 
	Position = UDim2.new(0.50, 0, 0.02, 0), 
	Color = Color3.fromRGB(220, 50, 50), Event = events.Sell
})

createTopButton({
	Name = "BaseTop", Text = "BASE", 
	Position = UDim2.new(0.63, 0, 0.02, 0),
	Color = Color3.fromRGB(50, 150, 255), Event = events.Base
})

-- 4. WHEEL SPIN FEATURE
local wheelAsset = "rbxassetid://123524343308399"
local panelTextureId = "rbxassetid://6927295847"
local spinSoundId = "rbxassetid://5406934065"

-- TIMER VARIABLES
local SPIN_COOLDOWN = 600 -- 15 minutes in seconds
local isSpinning = false -- State check for the button text

local wheelScreen = Instance.new("ScreenGui")
wheelScreen.Name = "WheelSpinGui"
wheelScreen.ResetOnSpawn = false
wheelScreen.IgnoreGuiInset = true
wheelScreen.Parent = playerGui

local spinSound = Instance.new("Sound")
spinSound.SoundId = spinSoundId
spinSound.Volume = 0.3
spinSound.Parent = wheelScreen

-- Styling Helper (Matching CannonShopClient) [cite: 5]
local function applyShopStyle(parent, transparency)
	local texture = Instance.new("ImageLabel")
	texture.Name = "PanelTexture"
	texture.BackgroundTransparency = 1
	texture.Image = panelTextureId
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

-- Wheel Icon
local wheelIcon = Instance.new("ImageButton")
wheelIcon.Name = "WheelIcon"
wheelIcon.AnchorPoint = Vector2.new(0.5, 0.5)
wheelIcon.Position = UDim2.new(0.85, 0, 0.08, 0)
wheelIcon.BackgroundTransparency = 1
wheelIcon.Image = wheelAsset
wheelIcon.ZIndex = 2
wheelIcon.Parent = wheelScreen

-- Scales the icon relative to the smaller viewport dimension (width OR height)
-- so it grows/shrinks correctly on any screen size or orientation
local function updateWheelIconSize()
	local vp = workspace.CurrentCamera.ViewportSize
	local minDim = math.min(vp.X, vp.Y)
	local iconSize = math.round(minDim * 0.09) -- 9% of the smaller axis; tweak to taste
	wheelIcon.Size = UDim2.fromOffset(iconSize, iconSize)
end

-- Run once immediately, then re-run whenever the window is resized
updateWheelIconSize()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateWheelIconSize)


-- Hover Animations
wheelIcon.MouseEnter:Connect(function()
	local vp = workspace.CurrentCamera.ViewportSize
	local minDim = math.min(vp.X, vp.Y)
	local hoverSize = math.round(minDim * 0.10) -- slightly larger than the base 0.09
	wheelIcon:TweenSize(UDim2.fromOffset(hoverSize, hoverSize), "Out", "Quad", 0.1, true)
end)

wheelIcon.MouseLeave:Connect(function()
	local vp = workspace.CurrentCamera.ViewportSize
	local minDim = math.min(vp.X, vp.Y)
	local normalSize = math.round(minDim * 0.09)
	wheelIcon:TweenSize(UDim2.fromOffset(normalSize, normalSize), "Out", "Quad", 0.1, true)
end)

-- DETACHED CONNECTOR BAR (Parented to ScreenGui)
local connectorBar = Instance.new("Frame")
connectorBar.Name = "ConnectorBar"
connectorBar.Size = UDim2.new(0.012, 0, 0.08, 0) -- Fixed scale from top
connectorBar.Position = UDim2.new(0.85, 0, 0, 0) -- Match Wheel X
connectorBar.AnchorPoint = Vector2.new(0.5, 0)
connectorBar.BackgroundColor3 = Color3.fromRGB(209, 209, 0)
connectorBar.BorderSizePixel = 0
connectorBar.ZIndex = 1 -- Behind Wheel
connectorBar.Parent = wheelScreen

local barStroke = Instance.new("UIStroke", connectorBar)
barStroke.Thickness = 1.5
barStroke.Color = Color3.fromRGB(159, 159, 0) -- Black outline

-- Main Popup Frame (Styled like CannonShop) [cite: 10]
local popupFrame = Instance.new("Frame")
popupFrame.Size = UDim2.new(0.45, 0, 0.65, 0)
popupFrame.Position = UDim2.fromScale(0.5, 0.5)
popupFrame.AnchorPoint = Vector2.new(0.5, 0.5)
popupFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
popupFrame.BackgroundTransparency = 0.1
popupFrame.Visible = false
popupFrame.Parent = wheelScreen

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 15)
mainCorner.Parent = popupFrame

applyShopStyle(popupFrame, 0.88)

local popupAspect = Instance.new("UIAspectRatioConstraint")
popupAspect.AspectRatio = 1.1
popupAspect.Parent = popupFrame

local popupStroke = Instance.new("UIStroke", popupFrame)
popupStroke.Thickness = 3
popupStroke.Color = Color3.fromRGB(255, 255, 255)
popupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Title/Info Label
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(0.8, 0, 0.08, 0)
infoLabel.Position = UDim2.new(0.5, 0, 0.1, 0)
infoLabel.AnchorPoint = Vector2.new(0.5, 0.5)
infoLabel.BackgroundTransparency = 1
infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
infoLabel.Font = Enum.Font.DenkOne
infoLabel.TextScaled = true
infoLabel.Text = "REWARD WHEEL"
infoLabel.Parent = popupFrame

-- Big Wheel Image [cite: 20]
local bigWheel = Instance.new("ImageLabel")
bigWheel.Size = UDim2.new(0.65, 0, 0.65, 0) 
bigWheel.Position = UDim2.new(0.5, 0, 0.48, 0) 
bigWheel.AnchorPoint = Vector2.new(0.5, 0.5)
bigWheel.BackgroundTransparency = 1
bigWheel.Image = wheelAsset
bigWheel.Parent = popupFrame

local bigWheelAspect = Instance.new("UIAspectRatioConstraint", bigWheel)
bigWheelAspect.AspectRatio = 1
bigWheelAspect.DominantAxis = Enum.DominantAxis.Height 

local wheelLabels = {} -- Table to store labels for the gyro effect

local labels = {
	{Text = "Random EPIC", Color = Color3.fromRGB(170, 0, 255), Deg = 0},
	{Text = "10M Cash", Color = Color3.fromRGB(0, 170, 0), Deg = 60},
	{Text = "Random LEGEND", Color = Color3.fromRGB(255, 170, 0), Deg = 120},
	{Text = "100M Cash", Color = Color3.fromRGB(0, 170, 0), Deg = 180},
	{Text = "Random Mythic", Color = Color3.fromRGB(255, 50, 50), Deg = 240},
	{Text = "1B Cash", Color = Color3.fromRGB(0, 170, 0), Deg = 300},
}

for _, info in ipairs(labels) do
	local label = Instance.new("TextLabel")
	-- Changed Size to Scale (approx 20% width, 6% height of bigWheel)
	label.Size = UDim2.new(0.3, 0, 0.06, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)

	local radius = 0.35 
	local rad = math.rad(info.Deg - 60) 
	label.Position = UDim2.new(0.5 + math.cos(rad) * radius, 0, 0.5 + math.sin(rad) * radius, 0)

	label.Text = info.Text
	label.TextColor3 = info.Color
	label.Font = Enum.Font.DenkOne
	-- Use TextScaled so the font shrinks/grows with the box
	label.TextScaled = true 
	label.BackgroundTransparency = 1
	label.Parent = bigWheel 

	local outline = Instance.new("UIStroke")
	outline.Thickness = 2 
	outline.Color = Color3.new(0,0,0)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label

	table.insert(wheelLabels, label)
end

-- 1. DEFINE THE FUNCTION FIRST
local function addOutline(obj)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0,0,0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- Ensure it outlines the frame
	stroke.Parent = obj
end

-- 2. NOW CREATE THE ARROW (Which uses the function)
local arrowContainer = Instance.new("Frame")
arrowContainer.Name = "ArrowPointer"
arrowContainer.Size = UDim2.new(0.08, 0, 0.12, 0) 
arrowContainer.Position = UDim2.new(0.67, 0, 0.25, 0) 
arrowContainer.AnchorPoint = Vector2.new(0.5, 1)
arrowContainer.BackgroundTransparency = 1
arrowContainer.ZIndex = 100
arrowContainer.Rotation = 40 
arrowContainer.Parent = popupFrame

local arrowHead = Instance.new("Frame")
arrowHead.Name = "ArrowHead"
arrowHead.Size = UDim2.new(0.8, 0, 0.4, 0) 
arrowHead.Position = UDim2.new(0.5, 0, 0.85, 0) 
arrowHead.AnchorPoint = Vector2.new(0.5, 0.5)
arrowHead.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
arrowHead.Rotation = 45
arrowHead.BorderSizePixel = 0
arrowHead.ZIndex = 102
arrowHead.Parent = arrowContainer

local arrowBody = Instance.new("Frame")
arrowBody.Name = "ArrowBody"
arrowBody.Size = UDim2.new(0.35, 0, 0.6, 0)
arrowBody.Position = UDim2.new(0.5, 0, 0.4, 0)
arrowBody.AnchorPoint = Vector2.new(0.5, 0.5)
arrowBody.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
arrowBody.BorderSizePixel = 0
arrowBody.ZIndex = 101
arrowBody.Parent = arrowContainer

-- Add aspect ratio to keep head a triangle shape
local headAspect = Instance.new("UIAspectRatioConstraint")
headAspect.AspectRatio = 1
headAspect.Parent = arrowHead

-- 3. CALL THE FUNCTION
addOutline(arrowHead)
addOutline(arrowBody)

-- Spin Button (Now with integrated Timer)
local spinBtn = Instance.new("TextButton")
spinBtn.Size = UDim2.new(0.4, 0, 0.12, 0)
spinBtn.Position = UDim2.new(0.5, 0, 0.9, 0)
spinBtn.AnchorPoint = Vector2.new(0.5, 0.5)
spinBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
spinBtn.Text = "SPIN!"
spinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
spinBtn.Font = Enum.Font.DenkOne
spinBtn.TextScaled = true
spinBtn.Parent = popupFrame

local btnCorner = Instance.new("UICorner", spinBtn)
btnCorner.CornerRadius = UDim.new(0, 8)
local bStroke = Instance.new("UIStroke", spinBtn)
bStroke.Thickness = 3
bStroke.Color = Color3.fromRGB(255, 255, 255)
bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Close Button (Shop Style) [cite: 21]
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromScale(0.1, 0.1)
closeBtn.Position = UDim2.fromScale(0.97, 0.03)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
closeBtn.Font = Enum.Font.DenkOne
closeBtn.TextScaled = true
closeBtn.Parent = popupFrame

local closeCorner = Instance.new("UICorner", closeBtn)
closeCorner.CornerRadius = UDim.new(0, 8)
applyShopStyle(closeBtn, 0.76)
local closeStroke = Instance.new("UIStroke", closeBtn)
closeStroke.Color = Color3.fromRGB(255, 255, 255)
closeStroke.Thickness = 3
closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- TIMER & BUTTON UPDATE LOOP
task.spawn(function()
	while true do
		-- NEW: Read from the server-synced attribute
		local lastSpinTime = player:GetAttribute("LastSpinTime") or 0
		local now = os.time()
		local timePassed = now - lastSpinTime

		-- Only update timer text if we aren't currently in the middle of a spin animation
		if not isSpinning then
			if timePassed < SPIN_COOLDOWN then
				local remaining = SPIN_COOLDOWN - timePassed
				local minutes = math.floor(remaining / 60)
				local seconds = remaining % 60
				spinBtn.Text = string.format("%02d:%02d", minutes, seconds)
				spinBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
				spinBtn.AutoButtonColor = false
			else
				spinBtn.Text = "SPIN!"
				spinBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
				spinBtn.AutoButtonColor = true
			end
		end
		task.wait(1)
	end
end)

-- Logic [cite: 19]
wheelIcon.MouseButton1Click:Connect(function()
	popupFrame.Visible = not popupFrame.Visible
end)

closeBtn.MouseButton1Click:Connect(function()
	popupFrame.Visible = false
end)

RunService.RenderStepped:Connect(function(deltaTime)
	-- 1. Rotate the small icon (top button)
	local rotSpeed = 15 * deltaTime
	wheelIcon.Rotation = wheelIcon.Rotation + rotSpeed

	-- 2. GYRO EFFECT: Keep wheel labels at 0 rotation
	for _, label in ipairs(wheelLabels) do
		if label and label.Parent then
			-- Set rotation to negative of the wheel's rotation to stay upright
			label.Rotation = -bigWheel.Rotation
		end
	end
end)

-- Inside TopSideButtonsScript

-- UPDATED SPIN LOGIC
spinBtn.MouseButton1Click:Connect(function()
	if isSpinning then return end

	local lastSpinTime = player:GetAttribute("LastSpinTime") or 0
	local now = os.time()
	if (now - lastSpinTime) < SPIN_COOLDOWN then return end

	isSpinning = true

	-- Request spin from server
	events.SpinWheel:FireServer()

	spinBtn.Text = "..."
	spinBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
end)

-- Receive result from server and animate
events.SpinWheel.OnClientEvent:Connect(function(rewardInfo)
	-- 1. CHANGE: Wait for the sound to load so we can read its exact "TimeLength"
	if not spinSound.IsLoaded then spinSound.Loaded:Wait() end

	-- 2. CHANGE: Set duration to match the sound exactly (solves "sound plays too long")
	local tweenDuration = 3.5

	-- Ensure playback speed is normal
	spinSound.PlaybackSpeed = spinSound.TimeLength / tweenDuration
	spinSound:Play()

	-- 3. ANIMATION LOGIC
	local fullSpins = 5
	-- Normalize the current rotation so we aren't compounding previous offsets
	local currentBase = bigWheel.Rotation - (bigWheel.Rotation % 360)
	local totalRotation = currentBase + (360 * fullSpins) - rewardInfo.Deg

	-- 4. CHANGE: Use the sound's duration (tweenDuration) for the animation speed
	local tInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local tween = TweenService:Create(bigWheel, tInfo, {Rotation = totalRotation})

	tween:Play()

	-- 5. WAIT: The script waits here until the wheel physically stops
	tween.Completed:Wait()

	-- 6. CHANGE: Small buffer before unlocking the button
	task.wait(0.5)
	isSpinning = false
end)

-- ==========================================
-- 5. TIMED REWARDS SYSTEM (ICON & GUI RESTORED)
-- ==========================================
local sessionStartTime = os.time()
local timedRewardsData = {
	{Mins = 10,  Desc = "10M Cash", Image = "rbxassetid://18209585783"},
	{Mins = 20,  Desc = "Legendary Brainrot", Image = "rbxassetid://403653614"},
	{Mins = 30,  Desc = "100M Cash", Image = "rbxassetid://18209585783"},
	{Mins = 40,  Desc = "Secret Brainrot", Image = "rbxassetid://403653614"},
	{Mins = 50, Desc = "1B Cash", Image = "rbxassetid://18209585783"},
	{Mins = 60, Desc = "Ancient Brainrot", Image = "rbxassetid://403653614"}
}

-- ── Helper Function ──────────────────────────────────────────────────────────
local function attachPanelTexture(parent, transparency)
	local texture = Instance.new("ImageLabel")
	texture.Name = "PanelTexture"
	texture.BackgroundTransparency = 1
	texture.Image = "rbxassetid://6927295847" -- [cite: 4, 9]
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



-- ── Grid Popup UI ────────────────────────────────────────────────────────────
local trFrame = Instance.new("Frame")
-- ADDED: makes rewards frame easy to find from LeftSideButtonsScript
trFrame.Name = "TimedRewardsFrame"
trFrame.Size = UDim2.new(0.55, 0, 0.60, 0)
trFrame.Position = UDim2.fromScale(0.5, 0.5)
trFrame.AnchorPoint = Vector2.new(0.5, 0.5)
trFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15) -- [cite: 9]
trFrame.BackgroundTransparency = 0.1
trFrame.Visible = false
trFrame.Parent = wheelScreen
local sizeConstraint = Instance.new("UISizeConstraint")
-- MaxWidth is 800 pixels, MaxHeight is 600 pixels (Adjust these as you like)
sizeConstraint.MaxSize = Vector2.new(800, 600) 
sizeConstraint.Parent = trFrame

local trCorner = Instance.new("UICorner", trFrame)
trCorner.CornerRadius = UDim.new(0, 15)
attachPanelTexture(trFrame, 0.88) -- [cite: 9]

local trStroke = Instance.new("UIStroke", trFrame)
trStroke.Thickness = 3
trStroke.Color = Color3.fromRGB(255, 255, 255) -- [cite: 9]
trStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Header
local trHeader = Instance.new("Frame")
trHeader.Size = UDim2.fromScale(1, 0.14)
trHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- [cite: 2, 9]
trHeader.Parent = trFrame
Instance.new("UICorner", trHeader).CornerRadius = UDim.new(0, 15)
attachPanelTexture(trHeader, 0.75) -- [cite: 9]

local headerStroke = Instance.new("UIStroke", trHeader)
headerStroke.Color = Color3.fromRGB(255, 255, 255) -- [cite: 9]
headerStroke.Thickness = 3
headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Close Button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromScale(0.08, 0.65)
closeBtn.Position = UDim2.fromScale(0.97, 0.17)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20) -- [cite: 10]
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 90, 90) -- [cite: 10]
closeBtn.Font = Enum.Font.DenkOne
closeBtn.TextScaled = true
closeBtn.Parent = trHeader
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8) -- [cite: 10]
attachPanelTexture(closeBtn, 0.76) -- [cite: 10]

local closeStroke = Instance.new("UIStroke", closeBtn)
closeStroke.Color = Color3.fromRGB(255, 255, 255) -- [cite: 10]
closeStroke.Thickness = 3
closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

closeBtn.MouseButton1Click:Connect(function() trFrame.Visible = false end)

-- Title
local trTitle = Instance.new("TextLabel")
trTitle.Size = UDim2.fromScale(0.7, 0.7)
trTitle.Position = UDim2.fromScale(0.05, 0.17)
trTitle.BackgroundTransparency = 1
trTitle.Text = "PLAYTIME REWARDS"
trTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
trTitle.Font = Enum.Font.DenkOne
trTitle.TextScaled = true
trTitle.TextXAlignment = Enum.TextXAlignment.Left
trTitle.Parent = trHeader

local titleStroke = Instance.new("UIStroke", trTitle)
titleStroke.Color = Color3.fromRGB(0, 0, 0) -- [cite: 10]
titleStroke.Thickness = 4
titleStroke.Parent = trTitle

--rewardButton.MouseButton1Click:Connect(function()
--	trFrame.Visible = not trFrame.Visible
--end)

-- ── Grid Container ──────────────────────────────────────────────────────────
local container = Instance.new("Frame")
container.Size = UDim2.new(0.94, 0, 0.75, 0)
container.Position = UDim2.fromScale(0.03, 0.22)
container.BackgroundTransparency = 1
container.Parent = trFrame

local gridLayout = Instance.new("UIGridLayout", container)
gridLayout.CellPadding = UDim2.new(0.02, 0, 0.04, 0)
gridLayout.CellSize = UDim2.new(0.31, 0, 0.46, 0) 
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local buttons = {}

for i, data in ipairs(timedRewardsData) do
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(60, 60, 60) -- [cite: 5]
	card.BackgroundTransparency = 0.1 -- [cite: 5]
	card.Parent = container
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10) -- [cite: 5]
	attachPanelTexture(card, 0.1) -- [cite: 5]

	local cardStroke = Instance.new("UIStroke", card)
	cardStroke.Color = Color3.fromRGB(255, 255, 255) -- [cite: 5]
	cardStroke.Thickness = 2.5
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(0.55, 0.5) 
	img.Position = UDim2.fromScale(0.5, 0.32)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.BackgroundTransparency = 1
	img.Image = data.Image
	img.Parent = card

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(0.9, 0.18)
	txt.Position = UDim2.fromScale(0.5, 0.62)
	txt.AnchorPoint = Vector2.new(0.5, 0.5)
	txt.BackgroundTransparency = 1
	txt.Text = data.Desc
	txt.TextColor3 = Color3.fromRGB(255, 255, 255)
	txt.Font = Enum.Font.DenkOne
	txt.TextScaled = true
	txt.Parent = card

	local txtStroke = Instance.new("UIStroke", txt)
	txtStroke.Thickness = 3
	txtStroke.Color = Color3.fromRGB(0, 0, 0) -- [cite: 6]

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(0.85, 0.22)
	btn.Position = UDim2.fromScale(0.5, 0.85)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(0, 170, 0) -- [cite: 6]
	btn.Text = "WAIT"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.DenkOne
	btn.TextScaled = true
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8) -- [cite: 7]

	local bStroke = Instance.new("UIStroke", btn)
	bStroke.Thickness = 3
	bStroke.Color = Color3.fromRGB(255, 255, 255) -- [cite: 7]
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	table.insert(buttons, {Btn = btn, Mins = data.Mins, Claimed = false})

	btn.MouseButton1Click:Connect(function()
		if buttons[i].Claimed or btn.Text ~= "CLAIM" then return end
		events.ClaimTimedReward:FireServer(i)
		buttons[i].Claimed = true
		btn.Text = "CLAIMED"
		btn.BackgroundColor3 = Color3.fromRGB(170, 0, 0) -- [cite: 7]
	end)
end

-- ── Timer Loop ──────────────────────────────────────────────────────────────
task.spawn(function()
	while true do
		local elapsed = (os.time() - sessionStartTime) / 60
		for _, info in ipairs(buttons) do
			if not info.Claimed then
				if elapsed >= info.Mins then
					info.Btn.Text = "CLAIM"
					info.Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
				else
					local left = math.ceil((info.Mins - elapsed) * 60)
					info.Btn.Text = string.format("%02d:%02d", math.floor(left/60), left%60)
					info.Btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
				end
			end
		end
		task.wait(1)
	end
end)