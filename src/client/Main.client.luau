--Main.client.luau
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local CannonShopClient = require(script.Parent.CannonShopClient)
local SellShopClient = require(script.Parent.SellShopClient)
local player = Players.LocalPlayer
local myBaseName = nil

local function createYourBaseIndicator(baseName)
	local bases = game.Workspace.Map.Bases
	local myBase = bases:FindFirstChild(baseName)
	if not myBase then
		return
	end

	local sign = myBase:WaitForChild("Sign", 5)
	if not sign then
		return
	end

	if sign:FindFirstChild("YourBaseIndicator") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "YourBaseIndicator"
	billboard.Size = UDim2.fromScale(10, 3)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	billboard.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Text = "YOUR BASE"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 0.4)
	arrow.Position = UDim2.fromScale(0, 0.6)
	arrow.Font = Enum.Font.LuckiestGuy
	arrow.TextScaled = true
	arrow.Parent = billboard

	local arrowStroke = Instance.new("UIStroke")
	arrowStroke.Color = Color3.fromRGB(0, 0, 0)
	arrowStroke.Thickness = 3
	arrowStroke.Parent = arrow
end

Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
	myBaseName = baseName
	createYourBaseIndicator(baseName)
end)

task.delay(2, function()
	if myBaseName then
		return
	end

	local bases = game.Workspace.Map.Bases
	for _, base in bases:GetChildren() do
		local sign = base:FindFirstChild("Sign")
		if sign and sign:FindFirstChild("BaseSign") then
			local bg = sign.BaseSign:FindFirstChild("Background")
			if bg then
				local info = bg:FindFirstChild("Info")
				if info then
					local nameLabel = info:FindFirstChild("PlayerName")
					if nameLabel and nameLabel.Text == player.Name then
						myBaseName = base.Name
						createYourBaseIndicator(base.Name)
						break
					end
				end
			end
		end
	end
end)

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.ActionText ~= "Pick Up" and prompt.ActionText ~= "Sell" then
		return
	end

	local current = prompt.Parent
	while current and current ~= game.Workspace do
		if current.Parent and current.Parent.Name == "Bases" then
			if not myBaseName or current.Name ~= myBaseName then
				prompt.Enabled = false
			end
			return
		end
		current = current.Parent
	end
end)

Remotes.CollectSlot.OnClientEvent:Connect(function()
	local audio = game.Workspace.Map:FindFirstChild("Audio")
	if not audio then
		return
	end
	local cashSound = audio:FindFirstChild("cashEffect")
	if not cashSound then
		return
	end

	local sfx = cashSound:Clone()
	sfx.Parent = player.PlayerGui
	sfx:Play()
	sfx.Ended:Once(function()
		sfx:Destroy()
	end)
end)

local dropButton = nil

local function showDropButton()
	if dropButton then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "DropButtonGui"
	screen.ResetOnSpawn = false
	screen.Parent = player.PlayerGui

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(0.15, 0.08)
	btn.Position = UDim2.fromScale(0.5, 0.72)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	btn.Text = "Drop"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.DenkOne
	btn.TextScaled = true
	btn.AutoButtonColor = true -- Provides built-in click feedback
	btn.Parent = screen

	-- Texture Overlay
	local texture = Instance.new("ImageLabel")
	texture.Name = "ButtonTexture"
	texture.BackgroundTransparency = 1
	texture.Image = "rbxassetid://6927295847"
	texture.Size = UDim2.fromScale(1, 1)
	texture.ScaleType = Enum.ScaleType.Stretch -- Ensures it fills the whole button
	texture.ImageTransparency = 0.4 -- Lower this if you want the texture stronger
	texture.ZIndex = 1 -- Sits above the background but below the text
	texture.Parent = btn

	-- Important: Sync the corner with the button
	Instance.new("UICorner", texture).CornerRadius = UDim.new(0, 10)

	-- Constraints
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.66
	aspect.Parent = btn

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

	-- White button border (Placed on a high ZIndex to stay visible)
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(255, 255, 255)
	buttonStroke.Thickness = 2
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = btn

	-- Black text outline
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if Remotes and Remotes.DropBrainrot then
			Remotes.DropBrainrot:FireServer()
		end
	end)

	dropButton = screen
end

local function hideDropButton()
	if dropButton then
		dropButton:Destroy()
		dropButton = nil
	end
end

Remotes.GrabStateChanged.OnClientEvent:Connect(function(isCarrying)
	if isCarrying then
		showDropButton()
	else
		hideDropButton()
	end
end)

Remotes.UpgradeSound.OnClientEvent:Connect(function()
	local sfx = Instance.new("Sound")
	sfx.SoundId = Config.UpgradeSoundId
	sfx.Volume = 1
	sfx.Parent = player.PlayerGui
	sfx:Play()
	sfx.Ended:Once(function()
		sfx:Destroy()
	end)
end)
Remotes.MaxLevelGlow.OnClientEvent:Connect(function(model)
	if not model or not model.Parent then
		return
	end

	local existing = model:FindFirstChild("MaxGlow")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "MaxGlow"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 215, 0)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	task.spawn(function()
		while model.Parent do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local primaryPart = model.PrimaryPart or model:FindFirstChildOfClass("BasePart")
			if hrp and primaryPart then
				local dist = (hrp.Position - primaryPart.Position).Magnitude
				if dist < 80 then
					highlight.Parent = model
				else
					highlight.Parent = nil
				end
			end
			task.wait(0.5)
		end
		highlight:Destroy()
	end)
end)
CannonShopClient.start()
SellShopClient.start()
