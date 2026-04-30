local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local TutorialSteps = require(ReplicatedStorage.TutorialSteps)

local TutorialClient = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STEP_ORDER = TutorialSteps.ORDER

local STEP_INDEX = {}
for index, stepId in ipairs(STEP_ORDER) do
	STEP_INDEX[stepId] = index
end

local STEP_VIEW = TutorialSteps.STEPS
local TUTORIAL_COMPLETE_MESSAGE = TutorialSteps.COMPLETE_MESSAGE
local TUTORIAL_COMPLETE_DISPLAY_TIME = TutorialSteps.COMPLETE_DISPLAY_TIME
local RETARGET_INTERVAL = 0.2
local PATH_CHEVRON_SPACING = 2.75
local PATH_MAX_CHEVRONS = 22
local PATH_END_OFFSET = 2
local CANNON_PATH_END_OFFSET = 3
local CANNON_RENDER_FOOTPRINT_PADDING = 1
local PATH_MIN_PLAYER_CLEAR_RADIUS = 1.6
local PATH_FIRST_CHEVRON_OFFSET = 0.05
local PATH_MIN_RENDER_DISTANCE = 0.95
local PATH_TOUCH_BUFFER = 0.35
local PATH_GROUNDED_STABILITY_TIME = 0.15
local PATH_RAY_HEIGHT = 40
local PATH_RAY_DISTANCE = 120
local GRAB_TARGET_HEIGHT_WINDOW = 6
local CHEVRON_HEIGHT = 0.9
local CHEVRON_SIZE = Vector3.new(3.5, 0.12, 3.5)
local CHEVRON_IMAGE = "rbxassetid://6669861035"
local CHEVRON_IMAGE_ROTATION = 90
local CHEVRON_CANVAS_SIZE = Vector2.new(256, 256)
local CHEVRON_IMAGE_SCALE = 0.92
local CHEVRON_SHADOW_OFFSET = 10
local CHEVRON_SCROLL_SPEED = 5
local PATH_NODE_MERGE_DISTANCE = 4
local PATH_NODE_LINK_DISTANCE = 18
local PATH_NODE_MAX_HEIGHT_DELTA = 16
local PATH_TARGET_POINT_HEIGHT_WEIGHT = 8
local ZONE_FLOOR_HEIGHT_TOLERANCE = 6
local ZONE_FLOOR_FOOTPRINT_PADDING = 1

local BaseContext = {
	baseName = nil,
}
local InventoryState = {}
local Targeting = {}
local PathRenderer = {}
local TutorialGui = {}

local currentStepId = nil
local tutorialCompleted = false
local tutorialCompletionDismissed = false
local tutorialCompletionDismissToken = 0
local screenGui = nil
local promptPill = nil
local promptLabel = nil
local progressChip = nil
local skipButton = nil
local confirmFrame = nil
local pathFolder = nil

local activePathTarget = nil
local activePathLogicalStepId = nil
local activePathChevrons = {}
local pathAnimationPhase = 0
local isFlightSuppressed = false
local flightRecoveryToken = 0
local started = false
local refreshDisplay

function InventoryState.isBrainrotTool(instance)
	return instance and instance:IsA("Tool") and instance:GetAttribute("BrainrotTool") == true
end

function InventoryState.watchToolContainer(container)
	if not container then
		return
	end

	container.ChildAdded:Connect(function(child)
		if InventoryState.isBrainrotTool(child) and refreshDisplay then
			refreshDisplay()
		end
	end)

	container.ChildRemoved:Connect(function(child)
		if InventoryState.isBrainrotTool(child) and refreshDisplay then
			refreshDisplay()
		end
	end)
end

function InventoryState.getAnyBrainrotTool()
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if InventoryState.isBrainrotTool(child) then
				return child
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if InventoryState.isBrainrotTool(child) then
				return child
			end
		end
	end

	return nil
end

function InventoryState.hasBackpackBrainrot()
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return false
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if InventoryState.isBrainrotTool(child) then
			return true
		end
	end

	return false
end

function InventoryState.hasEquippedBrainrot()
	local character = player.Character
	if not character then
		return false
	end

	for _, child in ipairs(character:GetChildren()) do
		if InventoryState.isBrainrotTool(child) then
			return true
		end
	end

	return false
end

function BaseContext.setBaseName(baseName)
	BaseContext.baseName = baseName
end

function BaseContext.resolveFromSigns()
	local map = Workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	if not bases then
		return
	end

	for _, base in ipairs(bases:GetChildren()) do
		local sign = base:FindFirstChild("Sign")
		local baseSign = sign and sign:FindFirstChild("BaseSign")
		local background = baseSign and baseSign:FindFirstChild("Background")
		local info = background and background:FindFirstChild("Info")
		local nameLabel = info and info:FindFirstChild("PlayerName")
		if nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text == player.Name then
			BaseContext.baseName = base.Name
			return
		end
	end
end

function BaseContext.findOwningBase(instance)
	local current = instance
	while current and current ~= Workspace do
		if current.Parent and current.Parent.Name == "Bases" then
			return current
		end
		current = current.Parent
	end

	return nil
end

function BaseContext.belongsToMyBase(instance)
	if not BaseContext.baseName then
		BaseContext.resolveFromSigns()
		if not BaseContext.baseName then
			return false
		end
	end

	local base = BaseContext.findOwningBase(instance)
	return base ~= nil and base.Name == BaseContext.baseName
end

local function getSlotFromInstance(instance)
	local current = instance
	while current and current ~= Workspace do
		if current.Name:match("^Slot%d+$") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function slotHasPlacedBrainrot(slot)
	if not slot then
		return false
	end

	for _, child in ipairs(slot:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Placed") then
			return true
		end
	end

	return false
end

local function resolveAdornee(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Attachment") or instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("ProximityPrompt") then
		local parent = instance.Parent
		if parent and (parent:IsA("Attachment") or parent:IsA("BasePart")) then
			return parent
		end
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function resolveWorldPosition(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("ProximityPrompt") then
		local adornee = resolveAdornee(instance)
		return adornee and resolveWorldPosition(adornee) or nil
	end

	if instance:IsA("Model") then
		if instance.Name == "CannonShop" then
			local ok, pivot = pcall(function()
				return instance:GetPivot()
			end)
			if ok then
				return (pivot * CFrame.new(0, -Config.ShopRingYDrop, Config.ShopRingForwardOffset)).Position
			end
		end

		local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			local promptPos = resolveWorldPosition(prompt)
			if promptPos then
				return promptPos
			end
		end

		local primaryPart = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		if primaryPart then
			return primaryPart.Position
		end

		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end

	return nil
end

local function resolveGrabPathPosition(instance)
	return resolveWorldPosition(instance)
end

local function isCannonPathStep(logicalStepId)
	return logicalStepId == "useLaunchCannon" or logicalStepId == "returnToBase"
end

local function resolveCannonRenderRoot(instance)
	if not instance then
		return nil
	end

	local current = resolveAdornee(instance) or instance
	local fallbackModel = nil

	while current and current ~= Workspace do
		if current:IsA("Model") then
			fallbackModel = fallbackModel or current
			if string.find(string.lower(current.Name), "cannon", 1, true) then
				return current
			end
		end
		current = current.Parent
	end

	return fallbackModel
end

local function resolvePathTargetPosition(startPos, target, logicalStepId)
	if logicalStepId == "grabBrainrot" then
		return resolveGrabPathPosition(target)
	end

	local actualTargetPos = resolveWorldPosition(target)
	if not actualTargetPos then
		return nil
	end

	if not isCannonPathStep(logicalStepId) or not startPos then
		return actualTargetPos
	end

	-- Cannon prompts render better when the path stops at the cannon footprint edge
	-- instead of aiming through the center of the model.
	local cannonRoot = resolveCannonRenderRoot(target)
	if not cannonRoot then
		return actualTargetPos
	end

	local ok, boxCFrame, boxSize = pcall(function()
		local modelCFrame, modelSize = cannonRoot:GetBoundingBox()
		return modelCFrame, modelSize
	end)
	if not ok or not boxCFrame or not boxSize then
		return actualTargetPos
	end

	local center = boxCFrame.Position
	local approachDelta = Vector3.new(startPos.X - center.X, 0, startPos.Z - center.Z)
	if approachDelta.Magnitude <= 0.05 then
		approachDelta = Vector3.new(actualTargetPos.X - center.X, 0, actualTargetPos.Z - center.Z)
	end
	if approachDelta.Magnitude <= 0.05 then
		return actualTargetPos
	end

	local approachDirection = approachDelta.Unit
	local horizontalRadius = math.max(boxSize.X, boxSize.Z) * 0.5
	local renderDistance = horizontalRadius + CANNON_RENDER_FOOTPRINT_PADDING
	local renderPosXZ = Vector3.new(center.X, 0, center.Z) + (approachDirection * renderDistance)

	return Vector3.new(renderPosXZ.X, actualTargetPos.Y, renderPosXZ.Z)
end

local function resolveGrabVisibilityPosition(instance)
	if not instance or not instance:IsA("Model") then
		return resolveGrabPathPosition(instance)
	end

	local pathPosition = resolveGrabPathPosition(instance)
	local ok, cframe, size = pcall(function()
		local boxCFrame, boxSize = instance:GetBoundingBox()
		return boxCFrame, boxSize
	end)
	if ok and cframe and size then
		local center = cframe.Position
		local lift = math.max(size.Y * 0.18, 1.4)
		local x = pathPosition and pathPosition.X or center.X
		local z = pathPosition and pathPosition.Z or center.Z
		local y = math.max(center.Y + lift, (pathPosition and pathPosition.Y or center.Y) + 1.2)
		return Vector3.new(x, y, z)
	end

	return pathPosition
end

local function getCommonSpawnZone()
	local folder = Workspace:FindFirstChild("SpawnZones")
	if not folder then
		return nil
	end

	return folder:FindFirstChild("CommonSpawnZone")
end

local function getCommonSpawnZoneGuard()
	local zone = getCommonSpawnZone()
	if not zone then
		return nil
	end

	local guard = zone:FindFirstChild("Guard")
	if guard and guard:IsA("Model") then
		return guard
	end

	return nil
end

local function getCommonSpawnPoints()
	local zone = getCommonSpawnZone()
	if not zone then
		return nil, nil
	end

	local points = {}
	for _, child in ipairs(zone:GetChildren()) do
		if child:IsA("BasePart") and child.Name:sub(1, 2) == "SP" then
			table.insert(points, child)
		end
	end

	if #points == 0 then
		return zone, nil
	end

	return zone, points
end

local function getSpawnZoneFloorPart(zone)
	if not zone then
		return nil
	end

	local directFloor = zone:FindFirstChild("Floor")
	if directFloor and directFloor:IsA("BasePart") then
		return directFloor
	end

	local nestedFloor = zone:FindFirstChild("Floor", true)
	if nestedFloor and nestedFloor:IsA("BasePart") then
		return nestedFloor
	end

	local fallbackFloor = zone:FindFirstChild("CommonSpawnZonePart")
	if fallbackFloor and fallbackFloor:IsA("BasePart") then
		return fallbackFloor
	end

	return nil
end

local function getClosestSpawnPoint(points, worldPosition, heightWeight)
	if not points or not worldPosition then
		return nil
	end

	local bestPoint = nil
	local bestScore = math.huge
	heightWeight = heightWeight or 0
	for _, point in ipairs(points) do
		local dx = point.Position.X - worldPosition.X
		local dz = point.Position.Z - worldPosition.Z
		local horizontalDistance = math.sqrt((dx * dx) + (dz * dz))
		local heightDistance = math.abs(point.Position.Y - worldPosition.Y)
		local score = horizontalDistance + (heightDistance * heightWeight)
		if score < bestScore then
			bestScore = score
			bestPoint = point
		end
	end

	return bestPoint
end

local function isWorldGrabTarget(instance)
	if not instance or not instance:IsA("Model") then
		return false
	end

	local parentModel = instance.Parent
	if parentModel and parentModel:IsA("Model") and parentModel:FindFirstChildOfClass("Humanoid") then
		return false
	end

	return instance:GetAttribute("Rarity") == "Common"
end

local function isValidCandidate(instance, logicalStepId)
	if not instance or not instance.Parent or not resolveAdornee(instance) then
		return false
	end

	if logicalStepId == "freeCannonUpgrade" or logicalStepId == "useLaunchCannon" then
		return true
	end

	if logicalStepId == "grabBrainrot" then
		return isWorldGrabTarget(instance)
	end

	if logicalStepId == "placeBrainrot" then
		local slot = getSlotFromInstance(instance)
		return BaseContext.belongsToMyBase(instance) and slot and not slotHasPlacedBrainrot(slot)
	end

	if logicalStepId == "collectCash" then
		local slot = getSlotFromInstance(instance)
		return BaseContext.belongsToMyBase(instance) and slot and (slot:GetAttribute("AccumulatedCash") or 0) > 0
	end

	if logicalStepId == "upgradeBrainrot" then
		return BaseContext.belongsToMyBase(instance)
	end

	return true
end

local function prefersMyBase(instance, logicalStepId)
	if logicalStepId == "freeCannonUpgrade" or logicalStepId == "useLaunchCannon" then
		return BaseContext.belongsToMyBase(instance)
	end

	return false
end

local function getHorizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt((dx * dx) + (dz * dz))
end

local function buildSpawnPointNeighbors(points)
	local neighbors = {}
	for _, point in ipairs(points) do
		neighbors[point] = {}
	end

	for i = 1, #points do
		local pointA = points[i]
		for j = i + 1, #points do
			local pointB = points[j]
			local horizontalDistance = getHorizontalDistance(pointA.Position, pointB.Position)
			local heightDelta = math.abs(pointA.Position.Y - pointB.Position.Y)
			if horizontalDistance <= PATH_NODE_LINK_DISTANCE
				and heightDelta <= PATH_NODE_MAX_HEIGHT_DELTA then
				local cost = (pointA.Position - pointB.Position).Magnitude
				table.insert(neighbors[pointA], { point = pointB, cost = cost })
				table.insert(neighbors[pointB], { point = pointA, cost = cost })
			end
		end
	end

	return neighbors
end

local function findSpawnPointPath(points, neighbors, startPoint, targetPoint)
	if not startPoint or not targetPoint then
		return nil
	end

	if startPoint == targetPoint then
		return { startPoint }
	end

	local distances = {}
	local previous = {}
	local unvisited = {}

	for _, point in ipairs(points) do
		distances[point] = math.huge
		table.insert(unvisited, point)
	end
	distances[startPoint] = 0

	while #unvisited > 0 do
		local currentIndex = 1
		local currentPoint = unvisited[1]
		for index = 2, #unvisited do
			local candidate = unvisited[index]
			if distances[candidate] < distances[currentPoint] then
				currentIndex = index
				currentPoint = candidate
			end
		end

		table.remove(unvisited, currentIndex)
		if currentPoint == targetPoint then
			break
		end

		local currentDistance = distances[currentPoint]
		if currentDistance == math.huge then
			break
		end

		for _, edge in ipairs(neighbors[currentPoint] or {}) do
			local tentativeDistance = currentDistance + edge.cost
			if tentativeDistance < (distances[edge.point] or math.huge) then
				distances[edge.point] = tentativeDistance
				previous[edge.point] = currentPoint
			end
		end
	end

	if not previous[targetPoint] then
		return { startPoint, targetPoint }
	end

	local path = { targetPoint }
	local cursor = targetPoint
	while previous[cursor] do
		cursor = previous[cursor]
		table.insert(path, 1, cursor)
	end

	return path
end

local function isGrabTargetUnobstructed(hrpPosition, candidate, visibilityPosition)
	local raycastParams = RaycastParams.new()
	local filterList = {}

	if player.Character then
		table.insert(filterList, player.Character)
	end
	if pathFolder then
		table.insert(filterList, pathFolder)
	end

	for _, tagged in ipairs(CollectionService:GetTagged(STEP_VIEW.grabBrainrot.targetTag)) do
		if tagged ~= candidate and tagged.Parent then
			table.insert(filterList, tagged)
		end
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterList

	local origin = hrpPosition + Vector3.new(0, 1.5, 0)
	local targetPoint = visibilityPosition
	local direction = targetPoint - origin
	local result = Workspace:Raycast(origin, direction, raycastParams)
	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(candidate)
end

local function chooseBestGrabTarget(tag, hrp)
	local bestTarget = nil
	local bestTier = math.huge
	local bestDistance = math.huge
	local bestHeight = math.huge

	for _, candidate in ipairs(CollectionService:GetTagged(tag)) do
		if isValidCandidate(candidate, "grabBrainrot") then
			local pathPosition = resolveGrabPathPosition(candidate)
			local visibilityPosition = resolveGrabVisibilityPosition(candidate)
			if pathPosition and visibilityPosition then
				local horizontalDistance = getHorizontalDistance(hrp.Position, pathPosition)
				local verticalDelta = math.abs(visibilityPosition.Y - hrp.Position.Y)
				local nearPlayerHeight = verticalDelta <= GRAB_TARGET_HEIGHT_WINDOW
				local unobstructed = isGrabTargetUnobstructed(hrp.Position, candidate, visibilityPosition)

				local tier = 4
				if unobstructed and nearPlayerHeight then
					tier = 1
				elseif unobstructed then
					tier = 2
				elseif nearPlayerHeight then
					tier = 3
				end

				local isBetter = false
				if tier < bestTier
					or (
						tier == bestTier
						and (
							pathPosition.Y < bestHeight - 1
							or (math.abs(pathPosition.Y - bestHeight) <= 1 and horizontalDistance < bestDistance - 0.05)
						)
					) then
					isBetter = true
				end

				if isBetter then
					bestTarget = candidate
					bestTier = tier
					bestDistance = horizontalDistance
					bestHeight = pathPosition.Y
				end
			end
		end
	end

	return bestTarget
end

function Targeting.findBestTarget(tag, logicalStepId)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if logicalStepId == "grabBrainrot" and hrp then
		return chooseBestGrabTarget(tag, hrp)
	end

	local bestTarget = nil
	local bestDistance = math.huge
	local bestPreferredTarget = nil
	local bestPreferredDistance = math.huge

	for _, candidate in ipairs(CollectionService:GetTagged(tag)) do
		if isValidCandidate(candidate, logicalStepId) then
			local pos = resolveWorldPosition(candidate)
			if pos then
				local distance = hrp and (hrp.Position - pos).Magnitude or 0
				if prefersMyBase(candidate, logicalStepId) then
					if distance < bestPreferredDistance then
						bestPreferredDistance = distance
						bestPreferredTarget = candidate
					end
				elseif distance < bestDistance then
					bestDistance = distance
					bestTarget = candidate
				end
			end
		end
	end

	return bestPreferredTarget or bestTarget
end

function Targeting.getPlacePrompt()
	if InventoryState.hasBackpackBrainrot() and not InventoryState.hasEquippedBrainrot() then
		return "Equip it, then place it!"
	end

	return STEP_VIEW.placeBrainrot.prompt
end

function PathRenderer.destroy()
	if pathFolder then
		pathFolder:Destroy()
		pathFolder = nil
	end

	activePathTarget = nil
	activePathLogicalStepId = nil
	activePathChevrons = {}
	pathAnimationPhase = 0
end

local function ensurePathFolder()
	if pathFolder then
		return pathFolder
	end

	pathFolder = Instance.new("Folder")
	pathFolder.Name = "TutorialPath"
	pathFolder.Parent = Workspace
	return pathFolder
end

local function getPathRaycastParams()
	local raycastParams = RaycastParams.new()
	local filterList = {}

	if player.Character then
		table.insert(filterList, player.Character)
	end
	if pathFolder then
		table.insert(filterList, pathFolder)
	end

	local guard = getCommonSpawnZoneGuard()
	if guard then
		table.insert(filterList, guard)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterList
	return raycastParams
end

local function getPathPlayerClearRadius()
	local characterRadius = 2
	local character = player.Character

	if character then
		local ok, extents = pcall(function()
			return character:GetExtentsSize()
		end)
		if ok and extents then
			characterRadius = math.max(extents.X, extents.Z) * 0.5
		end
	end

	return math.max((characterRadius * 0.55) + 0.2, PATH_MIN_PLAYER_CLEAR_RADIUS)
end

local function isHumanoidGroundedStable(humanoid)
	if not humanoid then
		return false
	end

	return humanoid.PlatformStand == false
		and humanoid.SeatPart == nil
		and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Returns whether a raycast hit should be ignored so projection stays on walkable
-- surfaces instead of snapping to tutorial props, guards, or spawned brainrots.
local function checkIgnoredGroundHit(instance, surfaceRoot)
	if not instance or not instance:IsA("BasePart") then
		return true, "not_basepart"
	end

	if pathFolder and instance:IsDescendantOf(pathFolder) then
		return true, "in_path_folder"
	end

	if surfaceRoot and not instance:IsDescendantOf(surfaceRoot) then
		return true, "outside_surface_root"
	end

	if instance.Name:sub(1, 2) == "SP" then
		return true, "sp_prefix"
	end

	local lowerName = string.lower(instance.Name)
	if string.find(lowerName, "conveyor", 1, true) then return true, "name_conveyor" end
	if string.find(lowerName, "belt", 1, true) then return true, "name_belt" end
	if string.find(lowerName, "guard", 1, true) then return true, "name_guard" end
	if string.find(lowerName, "path", 1, true) then return true, "name_path" end
	if string.find(lowerName, "tutorial", 1, true) then return true, "name_tutorial" end

	local ancestorModel = instance:FindFirstAncestorOfClass("Model")
	if ancestorModel and ancestorModel:GetAttribute("Rarity") then
		return true, "rarity_ancestor"
	end

	return false, nil
end

local function getPartTopY(part)
	return part.Position.Y + (part.Size.Y * 0.5)
end

local function isWithinFloorFootprint(worldPosition, floorPart)
	if not worldPosition or not floorPart or not floorPart:IsA("BasePart") then
		return false
	end

	local localPosition = floorPart.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = floorPart.Size * 0.5

	return math.abs(localPosition.X) <= halfSize.X + ZONE_FLOOR_FOOTPRINT_PADDING
		and math.abs(localPosition.Z) <= halfSize.Z + ZONE_FLOOR_FOOTPRINT_PADDING
end

local function isOnCommonSpawnFloor(worldPosition, floorPart)
	if not worldPosition or not floorPart then
		return false
	end

	if math.abs(worldPosition.Y - getPartTopY(floorPart)) > ZONE_FLOOR_HEIGHT_TOLERANCE then
		return false
	end

	return isWithinFloorFootprint(worldPosition, floorPart)
end

local function projectPointToFloorPart(worldPosition, floorPart)
	if not floorPart or not floorPart:IsA("BasePart") then
		return nil
	end

	local topY = getPartTopY(floorPart) + CHEVRON_HEIGHT
	return Vector3.new(worldPosition.X, topY, worldPosition.Z)
end

local function projectPointToGround(worldPosition, preferredFloorPart, surfaceRoot)
	if preferredFloorPart and preferredFloorPart.Parent then
		local projected = projectPointToFloorPart(worldPosition, preferredFloorPart)
		if projected then
			return projected
		end
	end

	local raycastParams = getPathRaycastParams()
	local origin = worldPosition + Vector3.new(0, PATH_RAY_HEIGHT, 0)
	local excluded = table.clone(raycastParams.FilterDescendantsInstances or {})
	local direction = Vector3.new(0, -PATH_RAY_DISTANCE, 0)


	for _ = 1, 8 do
		raycastParams.FilterDescendantsInstances = excluded
		local result = Workspace:Raycast(origin, direction, raycastParams)
		if not result then
			break
		end

		local ignored = checkIgnoredGroundHit(result.Instance, surfaceRoot)

		if not ignored then
			return Vector3.new(worldPosition.X, result.Position.Y + CHEVRON_HEIGHT, worldPosition.Z)
		end

		table.insert(excluded, result.Instance)
	end

	return Vector3.new(worldPosition.X, worldPosition.Y + CHEVRON_HEIGHT, worldPosition.Z)
end

local function createPathChevron(parent)
	local chevronPart = Instance.new("Part")
	chevronPart.Name = "PathChevron"
	chevronPart.Anchored = true
	chevronPart.CanCollide = false
	chevronPart.CanTouch = false
	chevronPart.CanQuery = false
	chevronPart.CastShadow = false
	chevronPart.Transparency = 1
	chevronPart.Size = CHEVRON_SIZE
	chevronPart.Parent = parent

	local surface = Instance.new("SurfaceGui")
	surface.Name = "ArrowGui"
	surface.Face = Enum.NormalId.Top
	surface.AlwaysOnTop = false
	surface.LightInfluence = 0
	surface.CanvasSize = CHEVRON_CANVAS_SIZE
	surface.Enabled = false
	surface.Parent = chevronPart

	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(CHEVRON_IMAGE_SCALE, CHEVRON_IMAGE_SCALE)
	shadow.Position = UDim2.new((1 - CHEVRON_IMAGE_SCALE) * 0.5, CHEVRON_SHADOW_OFFSET, (1 - CHEVRON_IMAGE_SCALE) * 0.5, CHEVRON_SHADOW_OFFSET)
	shadow.BackgroundTransparency = 1
	shadow.Image = CHEVRON_IMAGE
	shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	shadow.ImageTransparency = 0.45
	shadow.Rotation = CHEVRON_IMAGE_ROTATION
	shadow.Parent = surface

	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromScale(CHEVRON_IMAGE_SCALE, CHEVRON_IMAGE_SCALE)
	arrow.Position = UDim2.fromScale((1 - CHEVRON_IMAGE_SCALE) * 0.5, (1 - CHEVRON_IMAGE_SCALE) * 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Image = CHEVRON_IMAGE
	arrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
	arrow.ImageTransparency = 0.08
	arrow.Rotation = CHEVRON_IMAGE_ROTATION
	arrow.Parent = surface

	return {
		part = chevronPart,
		surface = surface,
	}
end

local function setChevronVisible(chevron, isVisible)
	if chevron and chevron.surface then
		chevron.surface.Enabled = isVisible
	end
end

local function syncChevronPool(count)
	local folder = ensurePathFolder()

	while #activePathChevrons < count do
		table.insert(activePathChevrons, createPathChevron(folder))
	end

	while #activePathChevrons > count do
		local chevron = table.remove(activePathChevrons)
		if chevron and chevron.part then
			chevron.part:Destroy()
		end
	end
end

local function positionChevron(chevron, worldPosition, flatDirection)
	local lookTarget = worldPosition + flatDirection
	chevron.part.CFrame = CFrame.lookAt(worldPosition, Vector3.new(lookTarget.X, worldPosition.Y, lookTarget.Z))
	setChevronVisible(chevron, true)
end

local function addRouteSegment(segments, fromPosition, toPosition, mode, metadata)
	local flatDelta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
	local length = flatDelta.Magnitude
	if length <= 0.05 then
		return
	end

	table.insert(segments, {
		from = fromPosition,
		to = toPosition,
		mode = mode,
		length = length,
		flatDirection = flatDelta.Unit,
		floorPart = metadata and metadata.floorPart or nil,
		surfaceRoot = metadata and metadata.surfaceRoot or nil,
	})
end

local function buildDirectRoute(startPos, targetPos, metadata)
	local segments = {}
	addRouteSegment(segments, startPos, targetPos, "raycast", metadata)

	return {
		segments = segments,
		totalLength = #segments > 0 and segments[1].length or 0,
		targetPos = targetPos,
	}
end

local function buildRouteFromSegments(startPos, targetPos, segments)
	if #segments == 0 then
		return buildDirectRoute(startPos, targetPos)
	end

	local totalLength = 0
	for _, segment in ipairs(segments) do
		totalLength += segment.length
	end

	return {
		segments = segments,
		totalLength = totalLength,
		targetPos = targetPos,
	}
end

local function buildCommonSpawnRoute(startPos, targetPathPos, targetIsOnCommonSpawnFloor, finalOutsideMode)
	local zone, points = getCommonSpawnPoints()
	if not zone or not points or #points == 0 then
		return buildDirectRoute(startPos, targetPathPos)
	end
	local floorPart = getSpawnZoneFloorPart(zone)
	local targetOnFloor = targetIsOnCommonSpawnFloor
	if targetOnFloor == nil then
		targetOnFloor = isOnCommonSpawnFloor(targetPathPos, floorPart)
	end

	local entrySP = getClosestSpawnPoint(points, startPos, 0.5)
	local exitSP = getClosestSpawnPoint(points, targetPathPos, PATH_TARGET_POINT_HEIGHT_WEIGHT)
	if not entrySP or not exitSP then
		return buildDirectRoute(startPos, targetPathPos)
	end

	local neighbors = buildSpawnPointNeighbors(points)
	local spawnPath = findSpawnPointPath(points, neighbors, entrySP, exitSP)
	if not spawnPath or #spawnPath == 0 then
		return buildDirectRoute(startPos, targetPathPos)
	end

	if #spawnPath == 1 and targetOnFloor then
		local segments = {}
		addRouteSegment(segments, startPos, targetPathPos, "zone", {
			floorPart = floorPart,
			surfaceRoot = zone,
		})

		return buildRouteFromSegments(startPos, targetPathPos, segments)
	end

	local segments = {}
	local currentPos = startPos
	local entryPos = entrySP.Position

	-- For the remaining no-intermediate-node cases, emit the player-to-entrySP
	-- raycast leg so the later final stretch starts from a floor-anchored
	-- point. The merge-distance gate is only safe when the route will continue
	-- through additional spawn points.
	local hasIntermediateNodes = #spawnPath >= 2
	local farFromEntry = getHorizontalDistance(currentPos, entryPos) > PATH_NODE_MERGE_DISTANCE
	local shouldUseZoneFromStart = finalOutsideMode == "raycast" and isOnCommonSpawnFloor(startPos, floorPart)
	if shouldUseZoneFromStart then
		addRouteSegment(segments, currentPos, entryPos, "zone", {
			floorPart = floorPart,
			surfaceRoot = zone,
		})
	elseif farFromEntry or not hasIntermediateNodes then
		addRouteSegment(segments, currentPos, entryPos, "raycast")
	end
	currentPos = entryPos

	for index = 2, #spawnPath do
		local nextPos = spawnPath[index].Position
		if getHorizontalDistance(currentPos, nextPos) > 0.25 then
			addRouteSegment(segments, currentPos, nextPos, "zone", {
				floorPart = floorPart,
				surfaceRoot = zone,
			})
			currentPos = nextPos
		end
	end

	if (currentPos - targetPathPos).Magnitude > 1 then
		local floorTopY = nil
		if floorPart then
			floorTopY = getPartTopY(floorPart)
		end

		if targetOnFloor then
			addRouteSegment(segments, currentPos, targetPathPos, "zone", {
				floorPart = floorPart,
				surfaceRoot = zone,
			})
		elseif finalOutsideMode == "elevated" then
			local elevatedStartPos = currentPos
			if floorTopY then
				elevatedStartPos = Vector3.new(currentPos.X, floorTopY, currentPos.Z)
			end

			addRouteSegment(segments, elevatedStartPos, targetPathPos, "elevated", {
				surfaceRoot = zone,
			})
		else
			addRouteSegment(segments, currentPos, targetPathPos, finalOutsideMode or "raycast")
		end
	end

	return buildRouteFromSegments(startPos, targetPathPos, segments)
end

local function buildGrabRoute(startPos, target)
	local targetPathPos = resolveGrabPathPosition(target)
	if not targetPathPos then
		return nil
	end

	return buildCommonSpawnRoute(startPos, targetPathPos, nil, "elevated")
end

local function buildPathRoute(startPos, target, logicalStepId)
	if logicalStepId == "grabBrainrot" then
		return buildGrabRoute(startPos, target)
	end

	local targetPos = resolvePathTargetPosition(startPos, target, logicalStepId)
	if not targetPos then
		return nil
	end

	if logicalStepId == "returnToBase" then
		local zone = getCommonSpawnZone()
		local floorPart = zone and getSpawnZoneFloorPart(zone) or nil
		if isOnCommonSpawnFloor(startPos, floorPart) then
			return buildDirectRoute(startPos, targetPos, {
				floorPart = floorPart,
				surfaceRoot = zone,
			})
		end
	end

	return buildDirectRoute(startPos, targetPos)
end

local function sampleRouteAtDistance(route, distanceAlongRoute)
	if not route or not route.segments or #route.segments == 0 then
		return nil, nil
	end

	local traversed = 0
	for index, segment in ipairs(route.segments) do
		local segmentEnd = traversed + segment.length
		if distanceAlongRoute <= segmentEnd or index == #route.segments then
			local t = segment.length > 0 and math.clamp((distanceAlongRoute - traversed) / segment.length, 0, 1) or 0
			local sample = segment.from:Lerp(segment.to, t)
			if segment.mode == "zone" then
				return projectPointToGround(sample, segment.floorPart, segment.surfaceRoot), segment.flatDirection
			end
			if segment.mode == "elevated" then
				return Vector3.new(sample.X, sample.Y + CHEVRON_HEIGHT, sample.Z), segment.flatDirection
			end
			if segment.mode == "raycast" then
				if segment.floorPart and segment.surfaceRoot and isWithinFloorFootprint(sample, segment.floorPart) then
					local projected = projectPointToFloorPart(sample, segment.floorPart)
					if projected then
						return projected, segment.flatDirection
					end
				end
				return projectPointToGround(sample, nil, nil), segment.flatDirection
			end
			return projectPointToGround(sample, nil, nil), segment.flatDirection
		end
		traversed = segmentEnd
	end

	return nil, nil
end

local function getPathEndOffset(logicalStepId)
	if isCannonPathStep(logicalStepId) then
		return CANNON_PATH_END_OFFSET
	end

	return PATH_END_OFFSET
end

local function getPathLayout(target, logicalStepId)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if isFlightSuppressed or not hrp or not target.Parent then
		return nil
	end

	local startPos = hrp.Position
	local targetPos = resolvePathTargetPosition(startPos, target, logicalStepId)
	if not targetPos then
		return nil
	end

	local route = buildPathRoute(startPos, target, logicalStepId)
	if not route or route.totalLength <= 0 then
		return nil
	end

	local playerClearRadius = getPathPlayerClearRadius()
	local startDistance = playerClearRadius + PATH_FIRST_CHEVRON_OFFSET
	local maxRenderableDistance = route.totalLength - PATH_TOUCH_BUFFER
	if maxRenderableDistance < PATH_MIN_RENDER_DISTANCE then
		return nil
	end

	startDistance = math.min(startDistance, maxRenderableDistance)
	local endOffset = getPathEndOffset(logicalStepId)
	local endDistance = math.min(route.totalLength - endOffset, maxRenderableDistance)
	local visibleSpan = endDistance - startDistance

	local fallbackDistance = nil
	if visibleSpan <= 0 then
		local fallbackMin = math.max(PATH_MIN_RENDER_DISTANCE, math.min(startDistance, route.totalLength * 0.55))
		fallbackDistance = math.clamp(fallbackMin, PATH_MIN_RENDER_DISTANCE, maxRenderableDistance)
		if fallbackDistance < PATH_MIN_RENDER_DISTANCE then
			return nil
		end
		startDistance = fallbackDistance
		endDistance = fallbackDistance
		visibleSpan = 0
	end

	return {
		startPos = startPos,
		targetPos = route.targetPos,
		route = route,
		startDistance = startDistance,
		endDistance = endDistance,
		visibleSpan = math.max(visibleSpan, 0),
		fallbackDistance = fallbackDistance,
	}
end

-- Flight suppression hides the path during launch and landing so the chevrons do
-- not fight the cannon motion or project onto temporary airborne positions.
function PathRenderer.beginFlightSuppression()
	flightRecoveryToken += 1
	isFlightSuppressed = true
	PathRenderer.destroy()

	local token = flightRecoveryToken
	task.spawn(function()
		local groundedSince = nil
		local seenFlightState = false

		while token == flightRecoveryToken do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if humanoid then
				local inFlightState = humanoid.PlatformStand
					or humanoid.SeatPart ~= nil
					or humanoid.FloorMaterial == Enum.Material.Air

				if inFlightState then
					seenFlightState = true
					groundedSince = nil
				elseif seenFlightState and isHumanoidGroundedStable(humanoid) then
					groundedSince = groundedSince or os.clock()
					if os.clock() - groundedSince >= PATH_GROUNDED_STABILITY_TIME then
						isFlightSuppressed = false
						if refreshDisplay then
							refreshDisplay()
						end
						return
					end
				else
					groundedSince = nil
				end
			else
				groundedSince = nil
			end

			task.wait(0.05)
		end
	end)
end

function PathRenderer.update(target, logicalStepId)
	if isFlightSuppressed or not target then
		PathRenderer.destroy()
		return
	end

	if activePathTarget ~= target or activePathLogicalStepId ~= logicalStepId then
		pathAnimationPhase = 0
		activePathTarget = target
		activePathLogicalStepId = logicalStepId
	end
end

function PathRenderer.animate(deltaTime)
	if isFlightSuppressed or not activePathTarget then
		PathRenderer.destroy()
		return
	end

	local layout = getPathLayout(activePathTarget, activePathLogicalStepId)
	if not layout then
		PathRenderer.destroy()
		return
	end

	if layout.fallbackDistance then
		syncChevronPool(1)
		local chevron = activePathChevrons[1]
		local worldPosition, flatDirection = sampleRouteAtDistance(layout.route, layout.fallbackDistance)
		if not worldPosition or not flatDirection then
			PathRenderer.destroy()
			return
		end

		positionChevron(chevron, worldPosition, flatDirection)
		pathAnimationPhase = 0
		return
	end

	local chevronCount = math.clamp(math.ceil(layout.visibleSpan / PATH_CHEVRON_SPACING) + 1, 1, PATH_MAX_CHEVRONS)
	syncChevronPool(chevronCount)

	local cycleLength = layout.visibleSpan + PATH_CHEVRON_SPACING
	pathAnimationPhase = (pathAnimationPhase + (CHEVRON_SCROLL_SPEED * deltaTime)) % cycleLength

	for index, chevron in ipairs(activePathChevrons) do
		local relativeDistance = (((index - 1) * PATH_CHEVRON_SPACING) + pathAnimationPhase) % cycleLength
		if relativeDistance > layout.visibleSpan then
			setChevronVisible(chevron, false)
		else
			local worldPosition, flatDirection = sampleRouteAtDistance(layout.route, layout.startDistance + relativeDistance)
			if worldPosition and flatDirection then
				positionChevron(chevron, worldPosition, flatDirection)
			else
				setChevronVisible(chevron, false)
			end
		end
	end
end

function Targeting.getProgressText(stepId)
	local stepIndex = STEP_INDEX[stepId] or 1
	return string.format("%d/%d", stepIndex, #STEP_ORDER)
end

function Targeting.resolveInstruction()
	if tutorialCompleted then
		if tutorialCompletionDismissed then
			return nil
		end

		return {
			prompt = TUTORIAL_COMPLETE_MESSAGE,
			target = nil,
			logicalStepId = nil,
			progress = nil,
			isComplete = true,
		}
	end

	if not currentStepId then
		return nil
	end

	local step = STEP_VIEW[currentStepId]
	if not step then
		return nil
	end

	local prompt = step.prompt
	local logicalStepId = currentStepId
	local target = Targeting.findBestTarget(step.targetTag, logicalStepId)

	-- The saved step does not change here; only the active guidance retargets to the
	-- next useful action based on the player's current inventory state.
	if logicalStepId == "grabBrainrot" and InventoryState.getAnyBrainrotTool() then
		local returnStep = STEP_VIEW.returnToBase
		local returnTarget = returnStep and Targeting.findBestTarget(returnStep.targetTag, "returnToBase")
		if returnStep and returnTarget then
			logicalStepId = "returnToBase"
			prompt = returnStep.prompt
			target = returnTarget
		end
	elseif logicalStepId == "placeBrainrot" then
		prompt = Targeting.getPlacePrompt()
	elseif logicalStepId == "upgradeBrainrot" and not target then
		if InventoryState.getAnyBrainrotTool() then
			logicalStepId = "placeBrainrot"
			prompt = "Place it, then upgrade!"
			target = Targeting.findBestTarget(STEP_VIEW.placeBrainrot.targetTag, logicalStepId)
		else
			logicalStepId = "grabBrainrot"
			prompt = "Get one back, then upgrade!"
			target = Targeting.findBestTarget(STEP_VIEW.grabBrainrot.targetTag, logicalStepId)
		end
	end

	return {
		prompt = prompt,
		target = target,
		logicalStepId = logicalStepId,
		progress = Targeting.getProgressText(currentStepId),
	}
end

function TutorialGui.setConfirmVisible(isVisible)
	if confirmFrame then
		confirmFrame.Visible = isVisible
	end
end

TutorialGui.refreshDisplay = function()
	if not screenGui then
		return
	end

	local instruction = Targeting.resolveInstruction()
	local isVisible = instruction ~= nil

	promptPill.Visible = isVisible
	skipButton.Visible = isVisible and not instruction.isComplete
	progressChip.Visible = isVisible and instruction.progress ~= nil

	if not isVisible then
		TutorialGui.setConfirmVisible(false)
		PathRenderer.destroy()
		return
	end

	promptLabel.Text = instruction.prompt
	if instruction.progress then
		progressChip.Text = instruction.progress
	end
	if instruction.isComplete or isFlightSuppressed then
		TutorialGui.setConfirmVisible(false)
		PathRenderer.destroy()
	else
		PathRenderer.update(instruction.target, instruction.logicalStepId)
	end
end
refreshDisplay = TutorialGui.refreshDisplay

local function createOutlinedLabel(parent, text, font, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.Font = font
	label.TextScaled = true
	label.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label

	return label
end

local function addTextSizeConstraint(instance, minSize, maxSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = instance
end

function TutorialGui.ensureGui()
	if screenGui then
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TutorialGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 5
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(0.5, 0, 0, 30)
	topRow.Position = UDim2.new(0.5, 0, 0, 4)
	topRow.AnchorPoint = Vector2.new(0.5, 0)
	topRow.BackgroundTransparency = 1
	topRow.Parent = screenGui

	local topRowMax = Instance.new("UISizeConstraint")
	topRowMax.MaxSize = Vector2.new(430, 30)
	topRowMax.MinSize = Vector2.new(300, 30)
	topRowMax.Parent = topRow

	promptPill = Instance.new("Frame")
	promptPill.Name = "PromptPill"
	promptPill.Size = UDim2.fromScale(1, 1)
	promptPill.Position = UDim2.fromScale(0.5, 0.5)
	promptPill.AnchorPoint = Vector2.new(0.5, 0.5)
	promptPill.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	promptPill.BackgroundTransparency = 0.28
	promptPill.BorderSizePixel = 0
	promptPill.Visible = false
	promptPill.Parent = topRow

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 11)
	pillCorner.Parent = promptPill

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(255, 255, 255)
	bannerStroke.Thickness = 1.25
	bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bannerStroke.Parent = promptPill

	local bannerGradient = Instance.new("UIGradient")
	bannerGradient.Color = ColorSequence.new(
		Color3.fromRGB(46, 46, 46),
		Color3.fromRGB(26, 26, 26)
	)
	bannerGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.34),
	})
	bannerGradient.Rotation = 90
	bannerGradient.Parent = promptPill

	local tutorialBadge = createOutlinedLabel(promptPill, "TUTORIAL", Enum.Font.DenkOne, Color3.fromRGB(80, 220, 120))
	tutorialBadge.Name = "Badge"
	tutorialBadge.Size = UDim2.fromOffset(82, 20)
	tutorialBadge.Position = UDim2.new(0, 8, 0.5, 0)
	tutorialBadge.AnchorPoint = Vector2.new(0, 0.5)
	tutorialBadge.TextXAlignment = Enum.TextXAlignment.Left
	addTextSizeConstraint(tutorialBadge, 13, 19)

	promptLabel = createOutlinedLabel(promptPill, "", Enum.Font.DenkOne, Color3.fromRGB(255, 255, 255))
	promptLabel.Name = "Prompt"
	promptLabel.Size = UDim2.new(1, -160, 1, -2)
	promptLabel.Position = UDim2.new(0.5, -2, 0.5, 0)
	promptLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	promptLabel.TextWrapped = false
	promptLabel.TextTruncate = Enum.TextTruncate.AtEnd
	promptLabel.TextXAlignment = Enum.TextXAlignment.Center
	addTextSizeConstraint(promptLabel, 16, 26)

	local rightMeta = Instance.new("Frame")
	rightMeta.Name = "RightMeta"
	rightMeta.Size = UDim2.fromOffset(58, 18)
	rightMeta.Position = UDim2.new(1, -8, 0.5, 0)
	rightMeta.AnchorPoint = Vector2.new(1, 0.5)
	rightMeta.BackgroundTransparency = 1
	rightMeta.Parent = promptPill

	progressChip = createOutlinedLabel(rightMeta, "1/7", Enum.Font.DenkOne, Color3.fromRGB(220, 220, 220))
	progressChip.Name = "Progress"
	progressChip.Size = UDim2.fromOffset(24, 16)
	progressChip.Position = UDim2.fromScale(0, 0.5)
	progressChip.AnchorPoint = Vector2.new(0, 0.5)
	addTextSizeConstraint(progressChip, 14, 18)

	skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.Size = UDim2.fromOffset(30, 16)
	skipButton.Position = UDim2.fromScale(1, 0.5)
	skipButton.AnchorPoint = Vector2.new(1, 0.5)
	skipButton.BackgroundTransparency = 1
	skipButton.Text = "Skip"
	skipButton.TextColor3 = Color3.fromRGB(255, 110, 110)
	skipButton.Font = Enum.Font.DenkOne
	skipButton.TextScaled = true
	skipButton.Visible = false
	skipButton.Parent = rightMeta
	addTextSizeConstraint(skipButton, 14, 18)

	local skipTextStroke = Instance.new("UIStroke")
	skipTextStroke.Color = Color3.fromRGB(0, 0, 0)
	skipTextStroke.Thickness = 2
	skipTextStroke.Parent = skipButton

	confirmFrame = Instance.new("Frame")
	confirmFrame.Name = "ConfirmFrame"
	confirmFrame.Size = UDim2.fromOffset(132, 16)
	confirmFrame.Position = UDim2.new(1, -8, 1, 1)
	confirmFrame.AnchorPoint = Vector2.new(1, 0)
	confirmFrame.BackgroundTransparency = 1
	confirmFrame.BorderSizePixel = 0
	confirmFrame.Visible = false
	confirmFrame.Parent = promptPill

	local confirmLabel = createOutlinedLabel(confirmFrame, "Skip tutorial?", Enum.Font.DenkOne, Color3.fromRGB(255, 255, 255))
	confirmLabel.Name = "ConfirmLabel"
	confirmLabel.Size = UDim2.fromOffset(74, 16)
	confirmLabel.Position = UDim2.new(0, 0, 0, 0)
	confirmLabel.AnchorPoint = Vector2.new(0, 0)
	confirmLabel.TextXAlignment = Enum.TextXAlignment.Right
	addTextSizeConstraint(confirmLabel, 9, 12)

	local confirmYes = Instance.new("TextButton")
	confirmYes.Name = "ConfirmYes"
	confirmYes.Size = UDim2.fromOffset(24, 16)
	confirmYes.Position = UDim2.fromOffset(84, 0)
	confirmYes.AnchorPoint = Vector2.new(0, 0)
	confirmYes.BackgroundTransparency = 1
	confirmYes.Text = "Yes"
	confirmYes.TextColor3 = Color3.fromRGB(80, 220, 120)
	confirmYes.Font = Enum.Font.DenkOne
	confirmYes.TextScaled = true
	confirmYes.Parent = confirmFrame
	addTextSizeConstraint(confirmYes, 9, 12)

	local confirmYesTextStroke = Instance.new("UIStroke")
	confirmYesTextStroke.Color = Color3.fromRGB(0, 0, 0)
	confirmYesTextStroke.Thickness = 2
	confirmYesTextStroke.Parent = confirmYes

	local confirmNo = Instance.new("TextButton")
	confirmNo.Name = "ConfirmNo"
	confirmNo.Size = UDim2.fromOffset(18, 16)
	confirmNo.Position = UDim2.fromOffset(112, 0)
	confirmNo.AnchorPoint = Vector2.new(0, 0)
	confirmNo.BackgroundTransparency = 1
	confirmNo.Text = "No"
	confirmNo.TextColor3 = Color3.fromRGB(255, 110, 110)
	confirmNo.Font = Enum.Font.DenkOne
	confirmNo.TextScaled = true
	confirmNo.Parent = confirmFrame
	addTextSizeConstraint(confirmNo, 9, 12)

	local confirmNoTextStroke = Instance.new("UIStroke")
	confirmNoTextStroke.Color = Color3.fromRGB(0, 0, 0)
	confirmNoTextStroke.Thickness = 2
	confirmNoTextStroke.Parent = confirmNo

	skipButton.MouseButton1Click:Connect(function()
		TutorialGui.setConfirmVisible(true)
	end)

	confirmYes.MouseButton1Click:Connect(function()
		TutorialGui.setConfirmVisible(false)
		Remotes.TutorialSkipRequested:FireServer()
	end)

	confirmNo.MouseButton1Click:Connect(function()
		TutorialGui.setConfirmVisible(false)
	end)
end

function TutorialClient.start()
	if started then
		return
	end
	started = true

	TutorialGui.ensureGui()

	InventoryState.watchToolContainer(player:FindFirstChild("Backpack"))
	InventoryState.watchToolContainer(player.Character)

	player.ChildAdded:Connect(function(child)
		if child.Name == "Backpack" then
			InventoryState.watchToolContainer(child)
			refreshDisplay()
		end
	end)

	Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
		BaseContext.setBaseName(baseName)
		refreshDisplay()
	end)

	Remotes.TutorialStepChanged.OnClientEvent:Connect(function(payload)
		local wasCompleted = tutorialCompleted
		currentStepId = payload and payload.currentStepId or nil
		tutorialCompleted = payload and payload.completed == true or false
		if tutorialCompleted then
			TutorialGui.setConfirmVisible(false)
			if not wasCompleted then
				tutorialCompletionDismissed = false
				tutorialCompletionDismissToken += 1
				local dismissToken = tutorialCompletionDismissToken
				task.delay(TUTORIAL_COMPLETE_DISPLAY_TIME, function()
					if tutorialCompletionDismissToken ~= dismissToken or not tutorialCompleted then
						return
					end

					tutorialCompletionDismissed = true
					if refreshDisplay then
						refreshDisplay()
					end
				end)
			end
		else
			tutorialCompletionDismissed = false
			tutorialCompletionDismissToken += 1
		end
		refreshDisplay()
	end)

	Remotes.CannonDropEvent.OnClientEvent:Connect(function(phase)
		if phase == "Reset" or phase == "Launch" or phase == "Descend" then
			PathRenderer.beginFlightSuppression()
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		PathRenderer.animate(deltaTime)
	end)

	task.delay(2, function()
		if not BaseContext.baseName then
			BaseContext.resolveFromSigns()
			refreshDisplay()
		end
	end)

	player.CharacterAdded:Connect(function(character)
		flightRecoveryToken += 1
		isFlightSuppressed = false
		PathRenderer.destroy()
		InventoryState.watchToolContainer(character)
		task.delay(1, refreshDisplay)
	end)

	task.spawn(function()
		while true do
			refreshDisplay()
			task.wait(RETARGET_INTERVAL)
		end
	end)
end

return TutorialClient
