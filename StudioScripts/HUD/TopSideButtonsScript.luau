local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. REMOTE EVENTS
local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local events = {
	Shop = remoteFolder:WaitForChild("TeleportRequest"),
	Sell = remoteFolder:WaitForChild("TeleportSellRequest"),
	Base = remoteFolder:WaitForChild("TeleportHomeEvent")
}

-- Access the Remotes module for GrabState [cite: 1, 9]
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- Track state via server updates [cite: 9]
local isCarryingUnclaimed = false

-- Listen to the grab state from the Pickup module [cite: 9]
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

		local oldT = config.Text -- Store original text from config

		-- Check if carrying unclaimed item [cite: 9]
		if isCarryingUnclaimed then
			label.Text = "STASH FIRST!"
			local originalColor = btn.BackgroundColor3
			btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

			task.wait(1.5) -- Give them time to read it

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

	-- Animations (Abbreviated)
	btn.MouseEnter:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.12, 0, 0.055, 0), "Out", "Quad", 0.1, true) end end)
	btn.MouseLeave:Connect(function() btn:TweenSize(UDim2.new(0.11, 0, 0.05, 0), "Out", "Quad", 0.1, true) end)
	btn.MouseButton1Down:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.10, 0, 0.045, 0), "In", "Quad", 0.05, true) end end)
	btn.MouseButton1Up:Connect(function() if not cooldown then btn:TweenSize(UDim2.new(0.12, 0, 0.055, 0), "Out", "Quad", 0.05, true) end end)

	return btn
end

-- 3. INITIALIZE
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