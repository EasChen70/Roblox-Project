local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Util = require(ReplicatedStorage.Util)

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

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = bg

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

-- Clear placed brainrots, upgrade signs, and reset slot state when a base is released
local function clearBaseSlots(base)
	local slotsFolder = base:FindFirstChild("Slots")
	if not slotsFolder then return end

	for _, slot in slotsFolder:GetChildren() do
		-- Destroy placed brainrot models (anything with the Placed attribute)
		for _, child in slot:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("Placed") then
				child:Destroy()
			end
		end

		-- Destroy upgrade sign (named "UpgradeBillboard", sits alongside the brainrot model)
		local upgradeBillboard = slot:FindFirstChild("UpgradeBillboard")
		if upgradeBillboard then
			upgradeBillboard:Destroy()
		end

		-- Reset accumulated cash attribute
		slot:SetAttribute("AccumulatedCash", 0)

		-- Reset CollectButton cash display
		local collectButton = slot:FindFirstChild("CollectButton")
		if collectButton then
			local billboard = collectButton:FindFirstChild("CashDisplay")
			if billboard then
				local label = billboard:FindFirstChild("Amount")
				if label then
					label.Text = Util.formatMoney(0)
				end
			end
		end
	end
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
		local base = claimedBases[player]
		print(player.Name, "released", base.Name)
		clearBaseSign(base)
		clearBaseSlots(base)  -- destroy placed brainrots, upgrade signs, reset slot visuals
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

-- NOTE: PlayerRemoving is wired in Main.server.luau to control ordering
-- (PlayerData.clearSession must save slot state BEFORE Base.releaseBase clears it)

for _, player in Players:GetPlayers() do
	if not claimedBases[player] then
		Base.claimBase(player)
	end
end

return Base