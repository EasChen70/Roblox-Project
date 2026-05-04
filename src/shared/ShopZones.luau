local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local ShopZones = {}

function ShopZones.getShops(shopName)
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return {}
	end

	local results = {}
	for _, obj in map:GetDescendants() do
		if obj:IsA("Model") and obj.Name == shopName then
			table.insert(results, obj)
		end
	end

	return results
end

function ShopZones.getRingPosition(shop)
	return (shop:GetPivot() * CFrame.new(0, -Config.ShopRingYDrop, Config.ShopRingForwardOffset)).Position
end

function ShopZones.getClosestHorizontalDistance(worldPosition, shopName, verticalPadding)
	local verticalLimit = Config.ShopRingMaxVerticalDistance + (verticalPadding or 0)
	local closestDistance = math.huge

	for _, shop in ShopZones.getShops(shopName) do
		local ok, ringPosition = pcall(ShopZones.getRingPosition, shop)
		if ok then
			local verticalDistance = math.abs(worldPosition.Y - ringPosition.Y)
			if verticalDistance <= verticalLimit then
				local horizontalDistance = (
					Vector2.new(worldPosition.X, worldPosition.Z) -
					Vector2.new(ringPosition.X, ringPosition.Z)
				).Magnitude
				if horizontalDistance < closestDistance then
					closestDistance = horizontalDistance
				end
			end
		end
	end

	return closestDistance
end

function ShopZones.isPositionWithinRange(worldPosition, shopName, horizontalPadding, verticalPadding)
	local horizontalLimit = Config.ShopRingRadius + (horizontalPadding or 0)
	return ShopZones.getClosestHorizontalDistance(worldPosition, shopName, verticalPadding) <= horizontalLimit
end

function ShopZones.isPlayerWithinRange(player, shopName, horizontalPadding, verticalPadding)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	return ShopZones.isPositionWithinRange(hrp.Position, shopName, horizontalPadding, verticalPadding)
end

return ShopZones
