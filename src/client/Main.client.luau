--Main.client.luau
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local myBaseName = nil

local function createYourBaseIndicator(baseName)
	local bases = game.Workspace.Map.Bases
	local myBase = bases:FindFirstChild(baseName)
	if not myBase then return end

	local sign = myBase:WaitForChild("Sign", 5)
	if not sign then return end

	if sign:FindFirstChild("YourBaseIndicator") then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "YourBaseIndicator"
	billboard.Size = UDim2.new(10, 0, 3, 0)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Text = "YOUR BASE"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.6, 0)
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
	arrow.Size = UDim2.new(1, 0, 0.4, 0)
	arrow.Position = UDim2.new(0, 0, 0.6, 0)
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
	if myBaseName then return end

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
	if prompt.ActionText ~= "Pick Up" and prompt.ActionText ~= "Sell" then return end

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
	if not audio then return end
	local cashSound = audio:FindFirstChild("cashEffect")
	if not cashSound then return end

	local sfx = cashSound:Clone()
	sfx.Parent = player.PlayerGui
	sfx:Play()
	sfx.Ended:Once(function()
		sfx:Destroy()
	end)
end)