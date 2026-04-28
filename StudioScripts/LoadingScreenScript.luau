local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local loadingGui = script.Parent:WaitForChild("LoadingScreen")

loadingGui.IgnoreGuiInset = true
loadingGui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local mainFrame = loadingGui:WaitForChild("Frame")
local barBackground = mainFrame:WaitForChild("BarBackground")
local barFill = barBackground:WaitForChild("BarFill")
local textContainer = mainFrame:WaitForChild("TextContainer")

-- 1. Setup Container & Letters
textContainer.BackgroundTransparency = 1
textContainer:ClearAllChildren()

local message = "LOADING..."
local letterLabels = {}
local charWidth = 35 
local totalWidth = #message * charWidth
textContainer.Size = UDim2.new(0, totalWidth, 0, 50)

for i = 1, #message do
	local char = string.sub(message, i, i)
	local label = Instance.new("TextLabel")
	label.Text = char
	label.Size = UDim2.new(0, charWidth, 1, 0)
	label.Position = UDim2.new(0, (i-1) * charWidth, 0, 0) 
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1) -- White Text
	label.TextSize = 45
	label.Font = Enum.Font.GothamBold
	label.Parent = textContainer

	-- ADD BLACK STROKE TO LETTERS
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3 -- Bold black outline
	stroke.Color = Color3.new(0, 0, 0) -- Black
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
			local startX = (i-1) * charWidth
			TweenService:Create(label, bounceInfo, {Position = UDim2.new(0, startX, -0.6, 0)}):Play()
			task.wait(0.1) 
		end
		task.wait(0.6)
	end
end)

-- 3. Bar Fill (10 Seconds)
barFill.Size = UDim2.new(0, 0, 1, 0)
local fillTween = TweenService:Create(barFill, TweenInfo.new(10, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
	Size = UDim2.new(1, 0, 1, 0)
})

fillTween:Play()
fillTween.Completed:Wait()

-- 4. Clean up / Fade Out
loadingActive = false
task.wait(0.5)

local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, obj in pairs(mainFrame:GetDescendants()) do
	if obj:IsA("Frame") or obj:IsA("TextLabel") or obj:IsA("UIStroke") then
		local prop = "Transparency"
		if obj:IsA("TextLabel") then prop = "TextTransparency" 
		elseif obj:IsA("Frame") then prop = "BackgroundTransparency" 
		end

		TweenService:Create(obj, fadeInfo, {[prop] = 1}):Play()
	end
end

task.wait(1.1)
loadingGui:Destroy()