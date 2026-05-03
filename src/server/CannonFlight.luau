local PhysicsService = game:GetService("PhysicsService")

local CannonFlight = {}

local PLAYER_FLIGHT_GROUP = "CannonFlightPlayers"
local CANNON_GROUP = "CannonFlightCannons"
local LAUNCH_TILT_RADIANS = math.rad(-45)
local MIN_BODY_CLEARANCE = 2
local CLEARANCE_PADDING = 0.35

local configuredCannons = setmetatable({}, { __mode = "k" })
local activeFlights = setmetatable({}, { __mode = "k" })
local collisionSetupReady = false

local function registerCollisionGroup(groupName)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)

	if ok then
		return
	end

	pcall(function()
		PhysicsService:CreateCollisionGroup(groupName)
	end)
end

local function ensureCollisionSetup()
	if collisionSetupReady then
		return
	end

	registerCollisionGroup(PLAYER_FLIGHT_GROUP)
	registerCollisionGroup(CANNON_GROUP)

	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PLAYER_FLIGHT_GROUP, CANNON_GROUP, false)
	end)

	collisionSetupReady = true
end

local function getPartCollisionGroup(part)
	local ok, groupName = pcall(function()
		return part.CollisionGroup
	end)

	if ok and groupName ~= "" then
		return groupName
	end

	local legacyOk, legacyName = pcall(function()
		return PhysicsService:GetCollisionGroupName(part.CollisionGroupId)
	end)

	if legacyOk then
		return legacyName
	end

	return "Default"
end

local function setPartCollisionGroup(part, groupName)
	local ok = pcall(function()
		part.CollisionGroup = groupName
	end)

	if ok then
		return
	end

	pcall(function()
		PhysicsService:SetPartCollisionGroup(part, groupName)
	end)
end

local function getBodyClearance(humanoid, rootPart)
	local hipHeight = humanoid.HipHeight or 0
	local rootHalfHeight = rootPart.Size.Y * 0.5

	return math.max(rootHalfHeight + hipHeight, MIN_BODY_CLEARANCE) + CLEARANCE_PADDING
end

local function getForwardStyleLaunchClearance(rootPart)
	return math.max(0.65, rootPart.Size.Y * 0.5) + 0.1
end

local function resolveLaunchMode(options)
	if type(options) == "string" then
		return options
	end

	if type(options) == "table" and type(options.mode) == "string" then
		return options.mode
	end

	return "target_aligned"
end

function CannonFlight.setupCannonCollision(model)
	if configuredCannons[model] then
		return
	end

	ensureCollisionSetup()
	configuredCannons[model] = true

	local function assignCollisionGroup(descendant)
		if descendant:IsA("BasePart") then
			setPartCollisionGroup(descendant, CANNON_GROUP)
		end
	end

	assignCollisionGroup(model)

	for _, descendant in model:GetDescendants() do
		assignCollisionGroup(descendant)
	end

	model.DescendantAdded:Connect(assignCollisionGroup)
end

function CannonFlight.enterCannonFlight(character, humanoid, rootPart)
	if not (character and humanoid and rootPart) then
		return
	end

	ensureCollisionSetup()
	CannonFlight.exitCannonFlight(character)

	local flightState = {
		originalGroups = {},
		connections = {},
	}

	local function assignFlightGroup(descendant)
		if not descendant:IsA("BasePart") then
			return
		end

		if flightState.originalGroups[descendant] == nil then
			flightState.originalGroups[descendant] = getPartCollisionGroup(descendant)
		end

		setPartCollisionGroup(descendant, PLAYER_FLIGHT_GROUP)
	end

	for _, descendant in character:GetDescendants() do
		assignFlightGroup(descendant)
	end

	table.insert(flightState.connections, character.DescendantAdded:Connect(assignFlightGroup))
	table.insert(flightState.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			CannonFlight.exitCannonFlight(character)
		end
	end))

	activeFlights[character] = flightState
end

function CannonFlight.exitCannonFlight(character)
	local flightState = activeFlights[character]
	if not flightState then
		return
	end

	activeFlights[character] = nil

	for _, connection in ipairs(flightState.connections) do
		connection:Disconnect()
	end

	for part, originalGroup in pairs(flightState.originalGroups) do
		if part and part.Parent then
			setPartCollisionGroup(part, originalGroup)
		end
	end
end

function CannonFlight.getLaunchAnchor(seat, humanoid, rootPart, targetPosition, options)
	local bodyClearance = getBodyClearance(humanoid, rootPart)
	local launchOffset = seat.CFrame.UpVector * (seat.Size.Y * 0.5 + bodyClearance)
	local launchPosition = seat.Position + launchOffset
	local launchMode = resolveLaunchMode(options)

	if launchMode == "seat_aligned" then
		return CFrame.new(launchPosition) * seat.CFrame.Rotation * CFrame.Angles(LAUNCH_TILT_RADIANS, 0, 0)
	end

	if launchMode == "forward_style" then
		local launchClearance = getForwardStyleLaunchClearance(rootPart)

		return CFrame.lookAt(seat.Position, Vector3.new(targetPosition.X, seat.Position.Y, targetPosition.Z))
			* CFrame.Angles(LAUNCH_TILT_RADIANS, 0, 0)
			* CFrame.new(0, launchClearance, 0)
	end

	local lookTarget = Vector3.new(targetPosition.X, launchPosition.Y, targetPosition.Z)

	if (lookTarget - launchPosition).Magnitude < 0.01 then
		lookTarget = launchPosition + Vector3.new(seat.CFrame.LookVector.X, 0, seat.CFrame.LookVector.Z)
	end

	return CFrame.lookAt(launchPosition, lookTarget) * CFrame.Angles(LAUNCH_TILT_RADIANS, 0, 0)
end

function CannonFlight.getLandingSnapHeight(humanoid, rootPart, groundY)
	return groundY + getBodyClearance(humanoid, rootPart)
end

return CannonFlight
