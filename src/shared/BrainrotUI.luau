local BrainrotUI = {}

local RarityColors = {
	Common = Color3.fromRGB(255, 255, 255),
	Rare = Color3.fromRGB(0, 170, 255),
	Epic = Color3.fromRGB(170, 0, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
	["Brainrot God"] = Color3.fromRGB(255, 0, 100),
	Secret = Color3.fromRGB(0, 0, 0),
}

local function formatMoney(amount)
	if amount < 1000 then
		return "$" .. math.floor(amount)
	elseif amount < 1000000 then
		return "$" .. string.format("%.1f", amount / 1000) .. "k"
	elseif amount < 1000000000 then
		return "$" .. string.format("%.1f", amount / 1000000) .. "m"
	elseif amount < 1000000000000 then
		return "$" .. string.format("%.1f", amount / 1000000000) .. "b"
	else
		return "$" .. string.format("%.1f", amount / 1000000000000) .. "t"
	end
end

local function makeLabel(name, text, color, order, size)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextColor3 = color
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.2, 0)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.LayoutOrder = order

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

local function createBillboardGui(model, studsOffset)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BrainrotBillboard"
	billboard.Size = UDim2.new(8, 0, 5, 0)

	if not studsOffset then
		local extents = model:GetExtentsSize()
		studsOffset = Vector3.new(0, extents.Y / 2 + 10, 0)
	end

	billboard.StudsOffset = studsOffset
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = model.PrimaryPart

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	return billboard, frame
end

function BrainrotUI.createBillboard(model, data)
	local rarity = data.rarity or "Common"
	local rarityColor = RarityColors[rarity] or RarityColors.Common

	local billboard, frame = createBillboardGui(model)

	local incomeLabel = makeLabel("Income", formatMoney(data.incomePerSec) .. "/s", Color3.fromRGB(85, 255, 85), 1, 22)
	incomeLabel.Parent = frame

	local nameLabel = makeLabel("Name", data.name, Color3.fromRGB(255, 255, 255), 2, 20)
	nameLabel.Parent = frame

	local rarityLabel = makeLabel("Rarity", rarity, rarityColor, 3, 28)
	rarityLabel.Parent = frame

	return billboard
end

function BrainrotUI.createWorldBillboard(model, data)
	local rarity = data.rarity or "Common"
	local rarityColor = RarityColors[rarity] or RarityColors.Common

	local billboard, frame = createBillboardGui(model, Vector3.new(0, 12, 0))
	billboard.Size = UDim2.new(8, 0, 6, 0)

	local timerLabel = makeLabel("Timer", "", Color3.fromRGB(255, 255, 255), 0, 24)

	local despawnTime = model:GetAttribute("DespawnRemaining")
	if despawnTime then
		timerLabel.Text = math.ceil(despawnTime) .. "s"
		timerLabel.Parent = frame
	end

	local incomeLabel = makeLabel("Income", formatMoney(data.incomePerSec) .. "/s", Color3.fromRGB(85, 255, 85), 1, 22)
	incomeLabel.Parent = frame

	local nameLabel = makeLabel("Name", data.name, Color3.fromRGB(255, 255, 255), 2, 20)
	nameLabel.Parent = frame

	local rarityLabel = makeLabel("Rarity", rarity, rarityColor, 3, 28)
	rarityLabel.Parent = frame

	if despawnTime then
		task.spawn(function()
			while model.Parent and billboard.Parent do
				local remaining = model:GetAttribute("DespawnRemaining")
				if not remaining then break end
				timerLabel.Text = math.ceil(remaining) .. "s"
				task.wait(1)
			end
		end)
	end

	return billboard
end

return BrainrotUI