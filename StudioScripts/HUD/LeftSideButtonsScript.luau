local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local shopBtn = createSquareButton(
	"Shop",
	"SHOP",
	"77580506639212",
	UDim2.new(0.01, 0, 0.35, 0),
	Color3.fromRGB(30, 35, 45),
	0.80
)

local rebirthBtn = createSquareButton(
	"Rebirth",
	"REBIRTH",
	"99330025492372",
	UDim2.new(0.01, 0, 0.50, 0),
	Color3.fromRGB(30, 30, 30),
	0.65
)

local rebirthGuiOpen = false

local function closeRebirthGui()
	local existing = playerGui:FindFirstChild("RebirthPopupGui")
	if existing then existing:Destroy() end
	rebirthGuiOpen = false
end

local function openRebirthGui()
	if rebirthGuiOpen then return end
	rebirthGuiOpen = true

	local remotes = game.ReplicatedStorage:WaitForChild("RemoteEvents")
	local rebirthRemote = remotes:WaitForChild("Rebirth")

	local currentRebirths = player.leaderstats.Rebirths.Value
	local currentPower = player:GetAttribute("CannonPower") or 1
	local currentMult = player:GetAttribute("RebirthMultiplier") or 1.0

	local requirements = {
		{ rebirth = 1,  power = 20,  multiplier = 1.5 },
		{ rebirth = 2,  power = 40,  multiplier = 2.0 },
		{ rebirth = 3,  power = 60,  multiplier = 2.5 },
		{ rebirth = 4,  power = 80,  multiplier = 3.0 },
		{ rebirth = 5,  power = 90,  multiplier = 3.5 },
		{ rebirth = 6,  power = 100, multiplier = 4.0 },
		{ rebirth = 7,  power = 110, multiplier = 4.5 },
		{ rebirth = 8,  power = 120, multiplier = 5.0 },
	}

	local nextReq = requirements[currentRebirths + 1]
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
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.5, 0.55)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	Instance.new("UIAspectRatioConstraint", panel).AspectRatio = 1.6

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
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.DenkOne
	closeBtn.TextScaled = true
	closeBtn.Parent = panel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	local xStroke = Instance.new("UIStroke")
	xStroke.Color = Color3.fromRGB(0, 0, 0)
	xStroke.Thickness = 3
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

local indexBtn = createSquareButton(
	"Index",
	"INDEX",
	"97629410614205",
	UDim2.new(0.01, 0, 0.65, 0),
	Color3.fromRGB(35, 30, 35),
	0.75
)