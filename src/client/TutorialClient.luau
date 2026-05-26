local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BaseIdentity = require(ReplicatedStorage.BaseIdentity)
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
local PATH_RENDER_WINDOW = 72
local PATH_TAIL_FADE_DISTANCE = 12
local PATH_MAX_CHEVRONS = math.ceil(PATH_RENDER_WINDOW / PATH_CHEVRON_SPACING) + 1
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
local CHEVRON_HEIGHT = 0.9
local CHEVRON_SIZE = Vector3.new(3.5, 0.12, 3.5)
local CHEVRON_IMAGE = "rbxassetid://6669861035"
local CHEVRON_IMAGE_ROTATION = 90
local CHEVRON_CANVAS_SIZE = Vector2.new(256, 256)
local CHEVRON_IMAGE_SCALE = 0.92
local CHEVRON_SHADOW_OFFSET = 10
local CHEVRON_ARROW_BASE_TRANSPARENCY = 0.08
local CHEVRON_SHADOW_BASE_TRANSPARENCY = 0.45
local CHEVRON_SCROLL_SPEED = 5
local PATH_MAX_RISE_ABOVE_SAMPLE = 4
local PATH_MIN_GROUND_NORMAL_Y = 0.6
local ZONE_FLOOR_HEIGHT_TOLERANCE = 6
local ZONE_FLOOR_FOOTPRINT_PADDING = 1
local BASE_BANNER_WIDTH = 430
local BASE_BANNER_HEIGHT = 30
local BANNER_TOP_MARGIN = 4
local BANNER_VIEWPORT_WIDTH_RATIO = 0.88
local TUTORIAL_BANNER_SCALE_MULTIPLIER = 1.2
local FLIGHT_PRELAUNCH_TIMEOUT = 2.5
local FLIGHT_SUPPRESSION_TIMEOUT = 10

local BaseContext = {
	baseId = nil,
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
local topRow = nil
local topRowScale = nil
local promptPill = nil
local promptLabel = nil
local progressChip = nil
local skipButton = nil
local confirmFrame = nil
local pathFolder = nil
local cameraViewportConnection = nil
local currentCameraConnection = nil

local activePathTarget = nil
local activePathLogicalStepId = nil
local activePathChevrons = {}
local activeChevronCapacity = 0
local pathAnimationPhase = 0
local isFlightSuppressed = false
local flightRecoveryToken = 0
local sampleRouteAtDistance
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

function BaseContext.setAssignedBase(baseId, baseName)
	BaseContext.baseId = BaseIdentity.normalizeBaseId(baseId)
	BaseContext.baseName = type(baseName) == "string" and baseName or nil
end

function BaseContext.syncFromPlayerAttributes()
	BaseContext.setAssignedBase(player:GetAttribute("AssignedBaseId"), player:GetAttribute("AssignedBaseName"))
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
			BaseContext.setAssignedBase(BaseIdentity.getResolvedBaseId(base), base.Name)
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
	if BaseContext.baseId == nil and not BaseContext.baseName then
		BaseContext.syncFromPlayerAttributes()
	end

	if BaseContext.baseId == nil and not BaseContext.baseName then
		BaseContext.resolveFromSigns()
		if BaseContext.baseId == nil and not BaseContext.baseName then
			return false
		end
	end

	local base = BaseContext.findOwningBase(instance)
	if not base then
		return false
	end

	local baseId = BaseIdentity.getResolvedBaseId(base)
	if BaseContext.baseId ~= nil and baseId ~= nil then
		return baseId == BaseContext.baseId
	end

	return BaseContext.baseName ~= nil and base.Name == BaseContext.baseName
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

local function isWorldGrabTarget(instance)
	if not instance or not instance:IsA("Model") then
		return false
	end

	if not instance:IsDescendantOf(Workspace) then
		return false
	end

	if instance:GetAttribute("Rarity") ~= "Common" then
		return false
	end

	if instance:GetAttribute("DespawnRemaining") == nil then
		return false
	end

	if instance:GetAttribute("DespawnPaused") ~= false then
		return false
	end

	if instance:GetAttribute("IsWorldItem") == true then
		return false
	end

	if not instance.PrimaryPart then
		return false
	end

	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return false
	end

	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return false
		end
		current = current.Parent
	end

	return true
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

local function chooseBestGrabTarget(tag, hrp)
	local bestTarget = nil
	local bestDistance = math.huge
	local bestVerticalDelta = math.huge

	for _, candidate in ipairs(CollectionService:GetTagged(tag)) do
		if isValidCandidate(candidate, "grabBrainrot") then
			local pathPosition = resolveGrabPathPosition(candidate)
			if pathPosition then
				local horizontalDistance = getHorizontalDistance(hrp.Position, pathPosition)
				local verticalDelta = math.abs(pathPosition.Y - hrp.Position.Y)
				if
					horizontalDistance < bestDistance - 0.05
					or (
						math.abs(horizontalDistance - bestDistance) <= 0.05
						and verticalDelta < bestVerticalDelta - 0.05
					)
				then
					bestTarget = candidate
					bestDistance = horizontalDistance
					bestVerticalDelta = verticalDelta
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
	activeChevronCapacity = 0
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

	return humanoid.PlatformStand == false and humanoid.SeatPart == nil and humanoid.FloorMaterial ~= Enum.Material.Air
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
	if string.find(lowerName, "conveyor", 1, true) then
		return true, "name_conveyor"
	end
	if string.find(lowerName, "belt", 1, true) then
		return true, "name_belt"
	end
	if string.find(lowerName, "guard", 1, true) then
		return true, "name_guard"
	end
	if string.find(lowerName, "path", 1, true) then
		return true, "name_path"
	end
	if string.find(lowerName, "tutorial", 1, true) then
		return true, "name_tutorial"
	end

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

		local ignored, ignoreReason = checkIgnoredGroundHit(result.Instance, surfaceRoot)
		local deltaY = result.Position.Y - worldPosition.Y
		local normalY = result.Normal.Y

		if ignored or deltaY > PATH_MAX_RISE_ABOVE_SAMPLE or normalY < PATH_MIN_GROUND_NORMAL_Y then
			table.insert(excluded, result.Instance)
		else
			return Vector3.new(worldPosition.X, result.Position.Y + CHEVRON_HEIGHT, worldPosition.Z)
		end
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
	shadow.Position = UDim2.new(
		(1 - CHEVRON_IMAGE_SCALE) * 0.5,
		CHEVRON_SHADOW_OFFSET,
		(1 - CHEVRON_IMAGE_SCALE) * 0.5,
		CHEVRON_SHADOW_OFFSET
	)
	shadow.BackgroundTransparency = 1
	shadow.Image = CHEVRON_IMAGE
	shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	shadow.ImageTransparency = CHEVRON_SHADOW_BASE_TRANSPARENCY
	shadow.Rotation = CHEVRON_IMAGE_ROTATION
	shadow.Parent = surface

	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromScale(CHEVRON_IMAGE_SCALE, CHEVRON_IMAGE_SCALE)
	arrow.Position = UDim2.fromScale((1 - CHEVRON_IMAGE_SCALE) * 0.5, (1 - CHEVRON_IMAGE_SCALE) * 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Image = CHEVRON_IMAGE
	arrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
	arrow.ImageTransparency = CHEVRON_ARROW_BASE_TRANSPARENCY
	arrow.Rotation = CHEVRON_IMAGE_ROTATION
	arrow.Parent = surface

	return {
		part = chevronPart,
		surface = surface,
		shadow = shadow,
		arrow = arrow,
	}
end

local function setChevronVisible(chevron, isVisible)
	if chevron and chevron.surface then
		chevron.surface.Enabled = isVisible
	end
end

local function syncChevronPool(count)
	local folder = ensurePathFolder()
	activeChevronCapacity = math.max(activeChevronCapacity, count)

	while #activePathChevrons < activeChevronCapacity do
		table.insert(activePathChevrons, createPathChevron(folder))
	end
end

local function setChevronFade(chevron, fadeAlpha)
	if not chevron then
		return
	end

	local alpha = math.clamp(fadeAlpha or 0, 0, 1)
	if chevron.arrow then
		chevron.arrow.ImageTransparency = CHEVRON_ARROW_BASE_TRANSPARENCY
			+ ((1 - CHEVRON_ARROW_BASE_TRANSPARENCY) * alpha)
	end
	if chevron.shadow then
		chevron.shadow.ImageTransparency = CHEVRON_SHADOW_BASE_TRANSPARENCY
			+ ((1 - CHEVRON_SHADOW_BASE_TRANSPARENCY) * alpha)
	end
end

local function getChevronFadeAlpha(relativeDistance, renderSpan)
	if renderSpan <= 0 then
		return 0
	end

	local fadeDistance = math.min(PATH_TAIL_FADE_DISTANCE, renderSpan)
	if fadeDistance <= 0 then
		return 0
	end

	local fadeStart = math.max(renderSpan - fadeDistance, 0)
	if relativeDistance <= fadeStart then
		return 0
	end

	return math.clamp((relativeDistance - fadeStart) / fadeDistance, 0, 1)
end

local function hideChevronsFromIndex(startIndex)
	for index = startIndex, #activePathChevrons do
		local chevron = activePathChevrons[index]
		if chevron then
			setChevronVisible(chevron, false)
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

local function buildGrabRoute(startPos, target)
	local targetPathPos = resolveGrabPathPosition(target)
	if not targetPathPos then
		return nil
	end

	local zone = getCommonSpawnZone()
	local floorPart = zone and getSpawnZoneFloorPart(zone) or nil
	if zone and floorPart and isOnCommonSpawnFloor(targetPathPos, floorPart) then
		return buildDirectRoute(startPos, targetPathPos, {
			floorPart = floorPart,
			surfaceRoot = zone,
		})
	end

	return buildDirectRoute(startPos, targetPathPos)
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

sampleRouteAtDistance = function(route, distanceAlongRoute)
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

local function clearFlightSuppression(reason)
	flightRecoveryToken += 1
	if not isFlightSuppressed then
		return
	end

	isFlightSuppressed = false
	if refreshDisplay then
		refreshDisplay()
	end
end

-- Flight suppression hides the path during launch and landing so the chevrons do
-- not fight the cannon motion or project onto temporary airborne positions.
function PathRenderer.beginFlightSuppression(reason)
	flightRecoveryToken += 1
	isFlightSuppressed = true
	PathRenderer.destroy()

	local token = flightRecoveryToken
	local startedAt = os.clock()
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
						clearFlightSuppression("grounded")
						return
					end
				elseif not seenFlightState and os.clock() - startedAt >= FLIGHT_PRELAUNCH_TIMEOUT then
					clearFlightSuppression("prelaunch_timeout")
					return
				else
					groundedSince = nil
				end
			else
				groundedSince = nil
			end

			if os.clock() - startedAt >= FLIGHT_SUPPRESSION_TIMEOUT then
				clearFlightSuppression(seenFlightState and "timeout" or "timeout_no_state")
				return
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
		if activePathTarget or activePathLogicalStepId then
			PathRenderer.destroy()
		end
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
		setChevronFade(chevron, 0)
		hideChevronsFromIndex(2)
		pathAnimationPhase = 0
		return
	end

	-- Keep the animated phase in world-distance units and render only the near
	-- window so player movement does not rescale the chevron conveyor.
	local renderSpan = math.min(layout.visibleSpan, PATH_RENDER_WINDOW)
	local chevronCount = math.clamp(math.ceil(renderSpan / PATH_CHEVRON_SPACING) + 1, 1, PATH_MAX_CHEVRONS)
	syncChevronPool(chevronCount)

	pathAnimationPhase = (pathAnimationPhase + (CHEVRON_SCROLL_SPEED * deltaTime)) % PATH_CHEVRON_SPACING

	for index, chevron in ipairs(activePathChevrons) do
		local relativeDistance = pathAnimationPhase + ((index - 1) * PATH_CHEVRON_SPACING)
		if relativeDistance > renderSpan then
			setChevronVisible(chevron, false)
		else
			local worldPosition, flatDirection =
				sampleRouteAtDistance(layout.route, layout.startDistance + relativeDistance)
			if worldPosition and flatDirection then
				positionChevron(chevron, worldPosition, flatDirection)
				setChevronFade(chevron, getChevronFadeAlpha(relativeDistance, renderSpan))
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

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end

	return nil
end

-- Keep the banner pixel-authored and scale the whole unit down on smaller screens.
function TutorialGui.updateBannerScale()
	if not topRowScale then
		return
	end

	local camera = Workspace.CurrentCamera
	local viewportWidth = camera and camera.ViewportSize.X or 0
	if viewportWidth <= 0 then
		topRowScale.Scale = TUTORIAL_BANNER_SCALE_MULTIPLIER
		return
	end

	local effectiveBannerWidth = BASE_BANNER_WIDTH * TUTORIAL_BANNER_SCALE_MULTIPLIER
	local viewportScale = math.min(1, (viewportWidth * BANNER_VIEWPORT_WIDTH_RATIO) / effectiveBannerWidth)
	topRowScale.Scale = viewportScale * TUTORIAL_BANNER_SCALE_MULTIPLIER
end

function TutorialGui.bindBannerScale()
	if currentCameraConnection then
		TutorialGui.updateBannerScale()
		return
	end

	local function attachCamera(camera)
		cameraViewportConnection = disconnectConnection(cameraViewportConnection)
		if camera then
			cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				TutorialGui.updateBannerScale()
			end)
		end

		TutorialGui.updateBannerScale()
	end

	currentCameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		attachCamera(Workspace.CurrentCamera)
	end)

	attachCamera(Workspace.CurrentCamera)
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

	topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.fromOffset(BASE_BANNER_WIDTH, BASE_BANNER_HEIGHT)
	topRow.Position = UDim2.new(0.5, 0, 0, BANNER_TOP_MARGIN)
	topRow.AnchorPoint = Vector2.new(0.5, 0)
	topRow.BackgroundTransparency = 1
	topRow.Parent = screenGui

	topRowScale = Instance.new("UIScale")
	topRowScale.Parent = topRow
	TutorialGui.bindBannerScale()

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
	bannerGradient.Color = ColorSequence.new(Color3.fromRGB(46, 46, 46), Color3.fromRGB(26, 26, 26))
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
	rightMeta.Size = UDim2.fromOffset(64, 18)
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
	skipButton.Size = UDim2.fromOffset(36, 18)
	skipButton.Position = UDim2.fromScale(1, 0.5)
	skipButton.AnchorPoint = Vector2.new(1, 0.5)
	skipButton.BackgroundTransparency = 1
	skipButton.Text = "Skip"
	skipButton.TextColor3 = Color3.fromRGB(255, 110, 110)
	skipButton.Font = Enum.Font.DenkOne
	skipButton.TextScaled = true
	skipButton.Visible = false
	skipButton.Parent = rightMeta
	addTextSizeConstraint(skipButton, 15, 20)

	local skipTextStroke = Instance.new("UIStroke")
	skipTextStroke.Color = Color3.fromRGB(0, 0, 0)
	skipTextStroke.Thickness = 2
	skipTextStroke.Parent = skipButton

	confirmFrame = Instance.new("Frame")
	confirmFrame.Name = "ConfirmFrame"
	confirmFrame.Size = UDim2.fromOffset(138, 18)
	confirmFrame.Position = UDim2.new(1, -8, 1, 1)
	confirmFrame.AnchorPoint = Vector2.new(1, 0)
	confirmFrame.BackgroundTransparency = 1
	confirmFrame.BorderSizePixel = 0
	confirmFrame.Visible = false
	confirmFrame.Parent = promptPill

	local confirmLabel =
		createOutlinedLabel(confirmFrame, "Skip tutorial?", Enum.Font.DenkOne, Color3.fromRGB(255, 255, 255))
	confirmLabel.Name = "ConfirmLabel"
	confirmLabel.Size = UDim2.fromOffset(82, 18)
	confirmLabel.Position = UDim2.new(0, 0, 0, 0)
	confirmLabel.AnchorPoint = Vector2.new(0, 0)
	confirmLabel.TextXAlignment = Enum.TextXAlignment.Right
	addTextSizeConstraint(confirmLabel, 10, 13)

	local confirmYes = Instance.new("TextButton")
	confirmYes.Name = "ConfirmYes"
	confirmYes.Size = UDim2.fromOffset(24, 18)
	confirmYes.Position = UDim2.fromOffset(92, 0)
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
	confirmNo.Size = UDim2.fromOffset(18, 18)
	confirmNo.Position = UDim2.fromOffset(120, 0)
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
	BaseContext.syncFromPlayerAttributes()

	InventoryState.watchToolContainer(player:FindFirstChild("Backpack"))
	InventoryState.watchToolContainer(player.Character)

	player.ChildAdded:Connect(function(child)
		if child.Name == "Backpack" then
			InventoryState.watchToolContainer(child)
			refreshDisplay()
		end
	end)

	Remotes.BaseAssigned.OnClientEvent:Connect(function(baseName)
		BaseContext.syncFromPlayerAttributes()
		if BaseContext.baseName == nil and type(baseName) == "string" then
			BaseContext.baseName = baseName
		end
		refreshDisplay()
	end)

	player:GetAttributeChangedSignal("AssignedBaseId"):Connect(function()
		BaseContext.syncFromPlayerAttributes()
		refreshDisplay()
	end)

	player:GetAttributeChangedSignal("AssignedBaseName"):Connect(function()
		BaseContext.syncFromPlayerAttributes()
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
		if phase == "Prepare" or phase == "Launch" or phase == "Descend" then
			PathRenderer.beginFlightSuppression(phase)
		elseif phase == "Reset" then
			if refreshDisplay then
				task.defer(refreshDisplay)
			end
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		PathRenderer.animate(deltaTime)
	end)

	task.delay(2, function()
		if BaseContext.baseId == nil and not BaseContext.baseName then
			BaseContext.syncFromPlayerAttributes()
		end
		if BaseContext.baseId == nil and not BaseContext.baseName then
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
