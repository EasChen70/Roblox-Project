local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local loadingGui = script.Parent:WaitForChild("LoadingScreen")
local LOADING_IMAGE = Config.LoadingScreenImageId
local BACKGROUND_COLOR = Color3.fromRGB(13, 13, 13)
local LOGO_HOLDER_SIZE = UDim2.new(1, 0, 0.66, 0)
local LOGO_HOLDER_POSITION = UDim2.new(0, 0, 0, 0)
local BOTTOM_CONTENT_POSITION = UDim2.new(0.5, 0, 0.93, 0)
local BOTTOM_CONTENT_SIZE = UDim2.new(0.62, 0, 0.20, 0)
local BAR_POSITION = UDim2.new(0.5, 0, 1, 0)
local BAR_SIZE = UDim2.new(0.80, 0, 0, 18)
local TEXT_POSITION = UDim2.new(0.5, 0, 0, 0)
local CHAR_WIDTH = 22
local TEXT_HEIGHT = 34
local TEXT_SIZE = 30
local TEXT_BOUNCE_Y = -0.28
local TEXT_STROKE = 2
local BASE_VIEWPORT = Vector2.new(1920, 1080)
local MIN_LOADING_SCALE = 0.78
local MAX_LOADING_SCALE = 1.16

loadingGui.IgnoreGuiInset = true
loadingGui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local mainFrame = loadingGui:WaitForChild("Frame")
local barBackground = mainFrame:WaitForChild("BarBackground")
local barFill = barBackground:WaitForChild("BarFill")
local textContainer = mainFrame:WaitForChild("TextContainer")

local backpackRestored = false

local function setBackpackEnabled(enabled)
	local success = false
	for _ = 1, 30 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
		end)
		if ok then
			success = true
			break
		end
		task.wait(0.1)
	end

	if not success then
		warn(string.format("[LoadingScreen] Failed to set backpack enabled=%s", tostring(enabled)))
	end
end

local function restoreBackpack()
	if backpackRestored then
		return
	end

	backpackRestored = true
	task.spawn(function()
		setBackpackEnabled(true)
	end)
end

loadingGui.Destroying:Connect(restoreBackpack)

local function getLoadingScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end

	local scale = math.min(viewport.X / BASE_VIEWPORT.X, viewport.Y / BASE_VIEWPORT.Y)
	return math.clamp(scale, MIN_LOADING_SCALE, MAX_LOADING_SCALE)
end

local function applyLoadingScale(bottomContentScale)
	if not bottomContentScale or not bottomContentScale.Parent then
		return
	end

	bottomContentScale.Scale = getLoadingScale()
end

local function runLoadingScreen()
	task.spawn(function()
		setBackpackEnabled(false)
	end)

	mainFrame.BackgroundColor3 = BACKGROUND_COLOR
	mainFrame.BackgroundTransparency = 0
	mainFrame.BorderSizePixel = 0

	local logoHolder = Instance.new("Frame")
	logoHolder.Name = "LogoHolder"
	logoHolder.Size = LOGO_HOLDER_SIZE
	logoHolder.Position = LOGO_HOLDER_POSITION
	logoHolder.BackgroundColor3 = BACKGROUND_COLOR
	logoHolder.BackgroundTransparency = 0
	logoHolder.BorderSizePixel = 0
	logoHolder.ZIndex = 0
	logoHolder.Parent = mainFrame

	local bg = Instance.new("ImageLabel")
	bg.Name = "Background"
	bg.Image = LOADING_IMAGE
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.Position = UDim2.new(0, 0, 0, 0)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel = 0
	bg.ScaleType = Enum.ScaleType.Fit
	bg.ZIndex = 1
	bg.Parent = logoHolder

	local bottomContent = Instance.new("Frame")
	bottomContent.Name = "BottomContent"
	bottomContent.AnchorPoint = Vector2.new(0.5, 1)
	bottomContent.Position = BOTTOM_CONTENT_POSITION
	bottomContent.Size = BOTTOM_CONTENT_SIZE
	bottomContent.BackgroundTransparency = 1
	bottomContent.BorderSizePixel = 0
	bottomContent.ZIndex = 2
	bottomContent.Parent = mainFrame

	local bottomContentScale = Instance.new("UIScale")
	bottomContentScale.Name = "ResponsiveScale"
	bottomContentScale.Parent = bottomContent
	applyLoadingScale(bottomContentScale)

	barBackground.AnchorPoint = Vector2.new(0.5, 1)
	barBackground.Position = BAR_POSITION
	barBackground.Size = BAR_SIZE
	barBackground.ZIndex = 2
	barBackground.Parent = bottomContent
	barFill.ZIndex = 3

	textContainer.AnchorPoint = Vector2.new(0.5, 0)
	textContainer.Position = TEXT_POSITION
	textContainer.ZIndex = 2
	textContainer.BackgroundTransparency = 1
	textContainer.Parent = bottomContent
	textContainer:ClearAllChildren()

	local message = "LOADING..."
	local letterLabels = {}
	local totalWidth = #message * CHAR_WIDTH
	textContainer.Size = UDim2.new(0, totalWidth, 0, TEXT_HEIGHT)

	for i = 1, #message do
		local char = string.sub(message, i, i)
		local label = Instance.new("TextLabel")
		label.Text = char
		label.Size = UDim2.new(0, CHAR_WIDTH, 1, 0)
		label.Position = UDim2.new(0, (i-1) * CHAR_WIDTH, 0, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.TextSize = TEXT_SIZE
		label.Font = Enum.Font.GothamBold
		label.ZIndex = 3
		label.Parent = textContainer

		local textConstraint = Instance.new("UITextSizeConstraint")
		textConstraint.MinTextSize = 22
		textConstraint.MaxTextSize = TEXT_SIZE
		textConstraint.Parent = label

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = TEXT_STROKE
		stroke.Color = Color3.new(0, 0, 0)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label

		table.insert(letterLabels, label)
	end

	-- 2. The Wave Animation
	local loadingActive = true
	task.spawn(function()
		local bounceInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)
		while loadingActive do
			for i, label in ipairs(letterLabels) do
				if not loadingActive then break end
				local startX = (i-1) * CHAR_WIDTH
				TweenService:Create(label, bounceInfo, {Position = UDim2.new(0, startX, TEXT_BOUNCE_Y, 0)}):Play()
				task.wait(0.1) 
			end
			task.wait(0.6)
		end
	end)

	local viewportScaleConnection
	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		viewportScaleConnection = currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			applyLoadingScale(bottomContentScale)
		end)
	end

	-- 3. Bar Fill (10 Seconds)
	barFill.Size = UDim2.new(0, 0, 1, 0)
	local fillTween = TweenService:Create(barFill, TweenInfo.new(10, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0)
	})

	fillTween:Play()
	fillTween.Completed:Wait()
	if viewportScaleConnection then
		viewportScaleConnection:Disconnect()
	end

	-- 4. Clean up / Fade Out
	loadingActive = false
	task.wait(0.5)

	local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(mainFrame, fadeInfo, {
		BackgroundTransparency = 1,
	}):Play()
	for _, obj in pairs(mainFrame:GetDescendants()) do
		if obj:IsA("ImageLabel") then
			TweenService:Create(obj, fadeInfo, {
				ImageTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif obj:IsA("Frame") or obj:IsA("TextLabel") or obj:IsA("UIStroke") then
			local prop = "Transparency"
			if obj:IsA("TextLabel") then
				prop = "TextTransparency"
			elseif obj:IsA("Frame") then
				prop = "BackgroundTransparency"
			end

			TweenService:Create(obj, fadeInfo, {[prop] = 1}):Play()
		end
	end

	task.wait(1.1)
	if loadingGui.Parent then
		loadingGui:Destroy()
	else
		restoreBackpack()
	end
end

local ok, err = xpcall(runLoadingScreen, debug.traceback)
if not ok then
	restoreBackpack()
	if loadingGui.Parent then
		loadingGui:Destroy()
	end
	warn("[LoadingScreen] Failed to finish cleanly:\n" .. tostring(err))
end
