local PhysicsService = game:GetService("PhysicsService")
local smoothBlock = script.Parent
local seat = smoothBlock:FindFirstChild("CannonSeat")
local prompt = smoothBlock:FindFirstChild("ProximityPrompt")
local blastSound = smoothBlock:FindFirstChild("BlastSound")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Remotes = require(ReplicatedStorage.Remotes)
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

local DEBUG_CANNON = true
local DEBUG_SAMPLE_INTERVAL = 0.25
local nextFlightDebugId = 0

local LANDING_FOLDER = "MiddleLandingParts" -- CHANGE PER CANNON

local CONFIG = {
	-- Trajectory tuning (preserved from original - DO NOT change without retesting flight feel)
	SPEED_DIVISOR = 40,
	MIN_TIME = 1.2,
	MAX_TIME = 3.4,
	MIN_VERTICAL = 70,
	MAX_POWER = 130,
	PRE_LAUNCH_DELAY = 0.8,
	ARRIVAL_RADIUS = 10,
	FLIGHT_TIMEOUT = 10,
	DESCEND_VELOCITY = Vector3.new(0, -120, 0),
	DESCEND_TIMEOUT = 5,
	RAYCAST_DISTANCE = Vector3.new(0, -10, 0),
	LANDING_Y_TOLERANCE = 3.5,
	LANDING_SETTLE_DELAY = 0.15,
}

local ZONE_FOLDERS = {
	"SpawnZones",
	"SpawnZonesRare",
	"SpawnZonesEpic",
	"SpawnZonesLegendary",
	"SpawnZonesMythic",
	"SpawnZonesSecret",
	"SpawnZonesDivine",
}

local PLAYER_FLIGHT_GROUP = "CannonFlightPlayers"
local CANNON_GROUP = "CannonFlightCannons"

local configuredCannons = setmetatable({}, { __mode = "k" })
local activeFlights = setmetatable({}, { __mode = "k" })
local collisionSetupReady = false

local function formatVector3(value)
	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function getFlightDebugId(player)
	nextFlightDebugId += 1
	return string.format("%s-%d", player.Name, nextFlightDebugId)
end

local function getNetworkOwnerLabel(part)
	if not part or not part.Parent then
		return "missing"
	end

	local ok, owner = pcall(function()
		return part:GetNetworkOwner()
	end)

	if not ok then
		return "error:" .. tostring(owner)
	end

	return owner and owner.Name or "server"
end

local function getInstanceLabel(instance)
	if not instance then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)

	if ok then
		return fullName
	end

	return instance.Name
end

local function debugLog(debugId, ...)
	if not DEBUG_CANNON then
		return
	end

	print(string.format("[ForwardCannon][%s]", tostring(debugId)), ...)
end

local function debugWarn(debugId, ...)
	warn(string.format("[ForwardCannon][%s]", tostring(debugId)), ...)
end

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

local function setupCannonCollision(model)
	if configuredCannons[model] then
		return 0, true
	end

	ensureCollisionSetup()
	configuredCannons[model] = true
	local assignedCount = 0

	local function assignCollisionGroup(descendant)
		if descendant:IsA("BasePart") then
			assignedCount += 1
			setPartCollisionGroup(descendant, CANNON_GROUP)
		end
	end

	assignCollisionGroup(model)

	for _, descendant in model:GetDescendants() do
		assignCollisionGroup(descendant)
	end

	model.DescendantAdded:Connect(assignCollisionGroup)
	return assignedCount, false
end

local function exitCannonFlight(character)
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

local function enterCannonFlight(character, humanoid, rootPart, debugId, flightMeta)
	if not (character and humanoid and rootPart) then
		return 0
	end

	ensureCollisionSetup()
	exitCannonFlight(character)

	local flightState = {
		originalGroups = {},
		connections = {},
	}
	local assignedCount = 0

	local function assignFlightGroup(descendant)
		if not descendant:IsA("BasePart") then
			return
		end

		if flightState.originalGroups[descendant] == nil then
			flightState.originalGroups[descendant] = getPartCollisionGroup(descendant)
		end

		assignedCount += 1
		setPartCollisionGroup(descendant, PLAYER_FLIGHT_GROUP)
	end

	for _, descendant in character:GetDescendants() do
		assignFlightGroup(descendant)
	end

	table.insert(flightState.connections, character.DescendantAdded:Connect(assignFlightGroup))
	table.insert(flightState.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if flightMeta and not flightMeta.releaseReason then
				flightMeta.releaseReason = "character_removed"
			end
			debugWarn(debugId, "character removed during forward cannon flight")
			exitCannonFlight(character)
		end
	end))
	table.insert(flightState.connections, humanoid.Died:Connect(function()
		if flightMeta and not flightMeta.releaseReason then
			flightMeta.releaseReason = "death"
		end
		debugWarn(debugId, "humanoid died during forward cannon flight")
		exitCannonFlight(character)
	end))

	activeFlights[character] = flightState
	return assignedCount
end

local function getLaunchClearance(rootPart)
	return math.max(1, rootPart.Size.Y * 0.5) + 0.1
end

local function getLandingClearance(humanoid, rootPart)
	return math.max(rootPart.Size.Y * 0.5 + humanoid.HipHeight, 2) + 0.35
end

local function findLandingTarget(power)
	local partName = "LandingPart" .. power
	for _, folderName in ZONE_FOLDERS do
		local zone = workspace:FindFirstChild(folderName)
		if zone then
			local landingFolder = zone:FindFirstChild(LANDING_FOLDER)
			if landingFolder then
				local part = landingFolder:FindFirstChild(partName)
				if part and part:IsA("BasePart") then
					return part
				end
			end
		end
	end

	warn("[Cannon] No LandingPart found for power", power, "in", LANDING_FOLDER)
	return nil
end

if not (seat and prompt) then
	debugWarn("setup", "missing seat or prompt", "model=" .. getInstanceLabel(smoothBlock))
	return
end

local setupCollisionCount, setupAlreadyConfigured = setupCannonCollision(smoothBlock)
debugLog(
	"setup",
	"cannon collision setup applied",
	"model=" .. getInstanceLabel(smoothBlock),
	"parts=" .. tostring(setupCollisionCount),
	"alreadyConfigured=" .. tostring(setupAlreadyConfigured)
)

if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
	seat.Disabled = true
	debugLog("setup", "seat auto-sit disabled", "seat=" .. getInstanceLabel(seat))
end

prompt.Triggered:Connect(function(player)
	local debugId = getFlightDebugId(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hum) then
		debugWarn(
			debugId,
			"missing character, humanoid, or root",
			"player=" .. player.Name,
			"hasCharacter=" .. tostring(char ~= nil),
			"hasHumanoid=" .. tostring(hum ~= nil),
			"hasRoot=" .. tostring(hrp ~= nil)
		)
		return
	end

	local cannonPower = player:GetAttribute("CannonPower")
	local launchPower = math.clamp((cannonPower or 1), 1, CONFIG.MAX_POWER)
	debugLog(
		debugId,
		"prompt triggered",
		"player=" .. player.Name,
		"cannonPower=" .. tostring(cannonPower or 1),
		"launchPower=" .. tostring(launchPower),
		"landingFolder=" .. LANDING_FOLDER
	)

	local targetPart = findLandingTarget(launchPower)
	if not targetPart then
		debugWarn(
			debugId,
			"missing landing target",
			"launchPower=" .. tostring(launchPower),
			"landingFolder=" .. LANDING_FOLDER
		)
		return
	end

	local targetPos = targetPart.Position
	prompt.Enabled = false
	local flightCollisionActive = false
	local flightMeta = {
		releaseReason = nil,
	}

	debugLog(
		debugId,
		"landing target resolved",
		"targetPart=" .. getInstanceLabel(targetPart),
		"targetPos=" .. formatVector3(targetPos)
	)

	local function releaseFlightCollision(reason)
		if flightCollisionActive then
			local resolvedReason = reason or flightMeta.releaseReason or "unspecified"
			debugLog(debugId, "player collision isolation released", "reason=" .. resolvedReason)
			exitCannonFlight(char)
			flightCollisionActive = false
		end
	end

	local handlerOk, handlerErr = pcall(function()
		Remotes.CannonDropEvent:FireClient(player, "Reset")
		debugLog(debugId, "reset fired to client")

		local isolatedPartCount = enterCannonFlight(char, hum, hrp, debugId, flightMeta)
		flightCollisionActive = true
		debugLog(
			debugId,
			"player collision isolation entered",
			"parts=" .. tostring(isolatedPartCount),
			"rootGroup=" .. getPartCollisionGroup(hrp)
		)

		hrp.Anchored = true
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)

		local launchClearance = getLaunchClearance(hrp)
		hrp.CFrame = CFrame.lookAt(seat.Position, Vector3.new(targetPos.X, seat.Position.Y, targetPos.Z))
			* CFrame.Angles(math.rad(-45), 0, 0)
			* CFrame.new(0, launchClearance, 0)
		debugLog(
			debugId,
			"pre-launch pose aligned",
			"seatPos=" .. formatVector3(seat.Position),
			"hrpPos=" .. formatVector3(hrp.Position),
			"launchClearance=" .. string.format("%.2f", launchClearance)
		)

		task.wait(CONFIG.PRE_LAUNCH_DELAY)

		if not (hrp.Parent and hum.Parent) then
			debugWarn(debugId, "character lost during pre-launch wait")
			error("character lost during pre-launch wait")
		end

		local g = workspace.Gravity
		local delta = targetPos - hrp.Position
		local totalDistance = delta.Magnitude
		local T = math.clamp(totalDistance / CONFIG.SPEED_DIVISOR, CONFIG.MIN_TIME, CONFIG.MAX_TIME)
		local horizontalVel = Vector3.new(delta.X / T, 0, delta.Z / T)
		local verticalVel = math.max(delta.Y / T + 0.5 * g * T, CONFIG.MIN_VERTICAL)
		local launchVelocity = horizontalVel + Vector3.new(0, verticalVel, 0)

		if blastSound then
			blastSound:Play()
		end

		hrp.Anchored = false

		pcall(function()
			hrp:SetNetworkOwner(player)
		end)

		hum.PlatformStand = true
		debugLog(
			debugId,
			"launch setup",
			"delta=" .. formatVector3(delta),
			"T=" .. string.format("%.2f", T),
			"launchVelocity=" .. formatVector3(launchVelocity),
			"ownerAfterSet=" .. getNetworkOwnerLabel(hrp),
			"platformStand=" .. tostring(hum.PlatformStand)
		)
		Remotes.CannonDropEvent:FireClient(player, "Launch", launchVelocity)
		debugLog(debugId, "launch fired to client")

		local launchTime = tick()

		task.spawn(function()
			local taskReleaseReason = nil
			local taskOk, taskErr = pcall(function()
				local arrived = false
				local timeout = tick() + CONFIG.FLIGHT_TIMEOUT
				local lastDebugSample = launchTime
				local lastOwnerLabel = getNetworkOwnerLabel(hrp)

				while not arrived and tick() < timeout do
					if hrp and hrp.Parent then
						local currentPos = hrp.Position
						local currentVelocity = hrp.AssemblyLinearVelocity
						local horizontalDist = (
							Vector3.new(targetPos.X, 0, targetPos.Z) -
							Vector3.new(currentPos.X, 0, currentPos.Z)
						).Magnitude
						local flightTime = tick() - launchTime
						local ownerLabel = getNetworkOwnerLabel(hrp)

						if ownerLabel ~= lastOwnerLabel then
							debugLog(
								debugId,
								"network owner changed",
								"owner=" .. ownerLabel,
								"flightTime=" .. string.format("%.2f", flightTime)
							)
							lastOwnerLabel = ownerLabel
						end

						if DEBUG_CANNON and tick() - lastDebugSample >= DEBUG_SAMPLE_INTERVAL then
							lastDebugSample = tick()
							debugLog(
								debugId,
								"flight sample",
								"pos=" .. formatVector3(currentPos),
								"vel=" .. formatVector3(currentVelocity),
								"horizontalDist=" .. string.format("%.2f", horizontalDist),
								"flightTime=" .. string.format("%.2f", flightTime),
								"owner=" .. ownerLabel
							)
						end

						if horizontalDist < CONFIG.ARRIVAL_RADIUS or flightTime >= T then
							arrived = true
							local descendReason = "time"
							if horizontalDist < CONFIG.ARRIVAL_RADIUS and flightTime >= T then
								descendReason = "radius+time"
							elseif horizontalDist < CONFIG.ARRIVAL_RADIUS then
								descendReason = "radius"
							end
							debugLog(
								debugId,
								"descend fired",
								"reason=" .. descendReason,
								"pos=" .. formatVector3(currentPos),
								"vel=" .. formatVector3(currentVelocity),
								"horizontalDist=" .. string.format("%.2f", horizontalDist),
								"flightTime=" .. string.format("%.2f", flightTime)
							)

							Remotes.CannonDropEvent:FireClient(
								player,
								"Descend",
								CONFIG.DESCEND_VELOCITY
							)

							local landed = false
							local landingGroundY = nil
							local descendStart = tick()
							local landingReason = "timeout"

							while not landed and hrp.Parent and tick() - descendStart < CONFIG.DESCEND_TIMEOUT do
								local rayParams = RaycastParams.new()
								rayParams.FilterDescendantsInstances = { char }
								rayParams.FilterType = Enum.RaycastFilterType.Exclude

								local ray = workspace:Raycast(
									hrp.Position,
									CONFIG.RAYCAST_DISTANCE,
									rayParams
								)

								if ray then
									landed = true
									landingGroundY = ray.Position.Y
									landingReason = "raycast"
									debugLog(
										debugId,
										"landing detected",
										"reason=raycast",
										"hit=" .. getInstanceLabel(ray.Instance),
										"groundY=" .. string.format("%.2f", landingGroundY),
										"pos=" .. formatVector3(hrp.Position)
									)
								elseif hrp.Position.Y <= (targetPos.Y + CONFIG.LANDING_Y_TOLERANCE) then
									landed = true
									landingReason = "y_threshold"
									debugLog(
										debugId,
										"landing detected",
										"reason=y_threshold",
										"targetY=" .. string.format("%.2f", targetPos.Y),
										"pos=" .. formatVector3(hrp.Position)
									)
								end

								task.wait()
							end

							if not landed and hrp.Parent then
								taskReleaseReason = "timeout"
								debugLog(
									debugId,
									"landing finalizing after timeout",
									"pos=" .. formatVector3(hrp.Position),
									"vel=" .. formatVector3(hrp.AssemblyLinearVelocity)
								)
							end

							if hrp.Parent then
								hrp.Anchored = true

								if landingGroundY then
									hrp.CFrame = CFrame.new(
										hrp.Position.X,
										landingGroundY + getLandingClearance(hum, hrp),
										hrp.Position.Z
									)
								end

								hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
								hum.PlatformStand = false
								hum:ChangeState(Enum.HumanoidStateType.Landed)

								task.wait(CONFIG.LANDING_SETTLE_DELAY)

								if hrp.Parent then
									hrp.Anchored = false
								end

								if taskReleaseReason == nil then
									taskReleaseReason = "normal_landing"
								end

								debugLog(
									debugId,
									"landing complete",
									"landingReason=" .. landingReason,
									"finalPos=" .. formatVector3(hrp.Position),
									"finalVel=" .. formatVector3(hrp.AssemblyLinearVelocity)
								)
							else
								taskReleaseReason = taskReleaseReason or flightMeta.releaseReason or "character_lost"
							end
						end
					else
						taskReleaseReason = taskReleaseReason or flightMeta.releaseReason or "character_lost"
						debugWarn(debugId, "flight loop ended because character/root is missing")
						break
					end

					task.wait()
				end

				if not arrived and taskReleaseReason == nil and tick() >= timeout then
					taskReleaseReason = "timeout"
					debugWarn(debugId, "flight timed out before descend")
				end
			end)

			if not taskOk then
				taskReleaseReason = "flight_error"
				debugWarn(debugId, "flight task error for", player.Name, "-", taskErr)
			end

			releaseFlightCollision(taskReleaseReason)
			prompt.Enabled = true
		end)
	end)

	if not handlerOk then
		debugWarn(debugId, "setup error for", player.Name, "-", handlerErr)
		releaseFlightCollision("setup_error")
		prompt.Enabled = true
	end
end)
