local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Config)
local Remotes = require(game.ReplicatedStorage.Remotes)

local Base = {}

local bases = game.Workspace.Map.Bases
local claimedBases = {}

function Base.getPlayerBase(player)
	return claimedBases[player]
end

local function createBaseSign(base, player)
	local sign = base:FindFirstChild("Sign")
	if not sign then return end

	local existing = sign:FindFirstChild("BaseSign")
	if existing then existing:Destroy() end

	local surface = Instance.new("SurfaceGui")
	surface.Name = "BaseSign"
	surface.Face = Enum.NormalId.Left
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.LightInfluence = 0
	surface.Parent = sign

	-- White background panel
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(0.9, 0, 0.85, 0)
	bg.Position = UDim2.new(0.05, 0, 0.075, 0)
	bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bg.BackgroundTransparency = 0.1
	bg.Parent = surface

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 12)
	bgCorner.Parent = bg

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(50, 50, 50)
	bgStroke.Thickness = 3
	bgStroke.Parent = bg

	-- Horizontal layout inside bg
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = bg

	-- Player thumbnail (left side)
	local thumbFrame = Instance.new("Frame")
	thumbFrame.Name = "ThumbFrame"
	thumbFrame.Size = UDim2.new(0.3, 0, 0.7, 0)
	thumbFrame.BackgroundTransparency = 1
	thumbFrame.LayoutOrder = 1
	thumbFrame.Parent = bg

	local thumb = Instance.new("ImageLabel")
	thumb.Name = "Thumbnail"
	thumb.Size = UDim2.new(1, 0, 1, 0)
	thumb.SizeConstraint = Enum.SizeConstraint.RelativeYY
	thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
	thumb.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
	thumb.Parent = thumbFrame

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	local thumbStroke = Instance.new("UIStroke")
	thumbStroke.Color = Color3.fromRGB(50, 50, 50)
	thumbStroke.Thickness = 3
	thumbStroke.Parent = thumb

	-- Info section (right side)
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Size = UDim2.new(0.55, 0, 0.8, 0)
	info.BackgroundTransparency = 1
	info.LayoutOrder = 2
	info.Parent = bg

	local infoLayout = Instance.new("UIListLayout")
	infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	infoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	infoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	infoLayout.Padding = UDim.new(0.05, 0)
	infoLayout.Parent = info

	-- Player name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Text = player.Name
	nameLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
	nameLabel.Font = Enum.Font.LuckiestGuy
	nameLabel.TextScaled = true
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = info

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(255, 255, 255)
	nameStroke.Thickness = 1.5
	nameStroke.Parent = nameLabel

	-- Income display
	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeDisplay"
	incomeLabel.Text = "$0/s"
	incomeLabel.TextColor3 = Color3.fromRGB(40, 180, 40)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Size = UDim2.new(1, 0, 0.3, 0)
	incomeLabel.Font = Enum.Font.LuckiestGuy
	incomeLabel.TextScaled = true
	incomeLabel.LayoutOrder = 2
	incomeLabel.Parent = info

	local incomeStroke = Instance.new("UIStroke")
	incomeStroke.Color = Color3.fromRGB(255, 255, 255)
	incomeStroke.Thickness = 1.5
	incomeStroke.Parent = incomeLabel
end

local function clearBaseSign(base)
	local sign = base:FindFirstChild("Sign")
	if not sign then return end
	local existing = sign:FindFirstChild("BaseSign")
	if existing then existing:Destroy() end
end

function Base.updateSignIncome(base, incomeText)
	local sign = base:FindFirstChild("Sign")
	if not sign then return end
	local gui = sign:FindFirstChild("BaseSign")
	if not gui then return end
	local bg = gui:FindFirstChild("Background")
	if not bg then return end
	local info = bg:FindFirstChild("Info")
	if not info then return end
	local label = info:FindFirstChild("IncomeDisplay")
	if label then
		label.Text = incomeText
	end
end

function Base.claimBase(player)
	if claimedBases[player] then return claimedBases[player] end

	for _, base in bases:GetChildren() do
		local taken = false
		for _, claimedBase in claimedBases do
			if claimedBase == base then
				taken = true
				break
			end
		end

		if not taken then
			claimedBases[player] = base
			print(player.Name, "claimed", base.Name)
			createBaseSign(base, player)
			Remotes.BaseAssigned:FireClient(player, base.Name)
			return base
		end
	end

	warn("No bases available for", player.Name)
	return nil
end

function Base.releaseBase(player)
	if claimedBases[player] then
		print(player.Name, "released", claimedBases[player].Name)
		clearBaseSign(claimedBases[player])
		claimedBases[player] = nil
	end
end

function Base.getOwner(baseModel)
	for player, base in claimedBases do
		if base == baseModel then
			return player
		end
	end
	return nil
end

Players.PlayerAdded:Connect(function(player)
	Base.claimBase(player)
end)

Players.PlayerRemoving:Connect(function(player)
	Base.releaseBase(player)
end)

for _, player in Players:GetPlayers() do
	if not claimedBases[player] then
		Base.claimBase(player)
	end
end

return Base