local guard = script.Parent
local humanoid = guard:WaitForChild("Humanoid")
local rootPart = guard:WaitForChild("HumanoidRootPart")
local model = guard.Parent
local zonePart = model:WaitForChild("CommonSpawnZonePart")
local PhysicsService = game:GetService("PhysicsService")

local ServerScriptService = game:GetService("ServerScriptService")
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

-- [[ 1. SETTINGS & VARIABLES ]] --
local RING_RADIUS = 11        
local KNOCKBACK_POWER = 45
local VERTICAL_LAUNCH = 45  
local VERTICAL_OFFSET = -16

local originPos = rootPart.Position
local currentGoal = rootPart.Position
local state = "Moving" 
local pauseEndTime = 0
local hasAlerted = false
local hitCooldowns = {} 

local zonePos = zonePart.Position
local zoneSize = zonePart.Size
local ZONE_BOUNDS = {
	minX = zonePos.X - (zoneSize.X/2), maxX = zonePos.X + (zoneSize.X/2),
	minZ = zonePos.Z - (zoneSize.Z/2), maxZ = zonePos.Z + (zoneSize.Z/2)
}

local alertSound = guard:FindFirstChild("AlertSound", true) 

-- [[ 2. PHYSICS & COLLISION SETUP ]] --
humanoid.MaxHealth = 1e9
humanoid.Health = humanoid.MaxHealth

humanoid.HealthChanged:Connect(function()
	if humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
end)
rootPart:SetNetworkOwner(nil)

pcall(function() PhysicsService:RegisterCollisionGroup("Guards") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)
PhysicsService:CollisionGroupSetCollidable("Guards", "Players", false)

for _, part in pairs(guard:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CollisionGroup = "Guards"

		-- Keep root part physical for stability
		if part ~= rootPart then
			part.Massless = true
		end
	end
end

-- [[ 3. VISUAL RING SETUP (OPTIMIZED FOR CONSOLE MEMORY) ]] --
local visualRing = nil

local function createVisualRing()
	local ringFolder = workspace:FindFirstChild("GuardRings")
	if not ringFolder then
		ringFolder = Instance.new("Folder")
		ringFolder.Name = "GuardRings"
		ringFolder.Parent = workspace
	end

	local ring = Instance.new("Part")
	ring.Name = "GuardVisualRing_" .. guard.Name
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, RING_RADIUS * 2, RING_RADIUS * 2)
	ring.Color = Color3.fromRGB(255, 0, 0)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.CastShadow = false
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Parent = ringFolder

	-- [[ OPTIMIZED: Weld the ring instead of using Heartbeat to move it ]] --
	ring.Massless = true
	ring.Anchored = false -- Must be unanchored to weld to a moving guard
	ring.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, VERTICAL_OFFSET, 0)) * CFrame.Angles(0, 0, math.rad(90))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = ring
	weld.Parent = ring

	visualRing = ring

	guard.Destroying:Connect(function()
		ring:Destroy()
		visualRing = nil
	end)
end
createVisualRing()

-- [[ OPTIMIZED: Removed RunService.Heartbeat entirely. The Weld handles it with 0 network lag. ]] --


-- [[ 4. ANIMATION SETUP ]] --
local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = "rbxassetid://507767714" 
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
local walkTrack = animator:LoadAnimation(walkAnim)
walkTrack.Priority = Enum.AnimationPriority.Movement

-- [[ 5. LOGIC FUNCTIONS ]] --
local MAX_DETECTION_HEIGHT = 20 

local function isInsideZone(pos)
	local b = ZONE_BOUNDS
	local withinXZ = pos.X >= b.minX and pos.X <= b.maxX and pos.Z >= b.minZ and pos.Z <= b.maxZ
	local heightDiff = math.abs(pos.Y - rootPart.Position.Y)
	local withinHeight = heightDiff <= MAX_DETECTION_HEIGHT
	return withinXZ and withinHeight
end

local function clampToZone(targetPos)
	local b = ZONE_BOUNDS
	local buffer = 4
	return Vector3.new(
		math.clamp(targetPos.X, b.minX + buffer, b.maxX - buffer),
		rootPart.Position.Y,
		math.clamp(targetPos.Z, b.minZ + buffer, b.maxZ - buffer)
	)
end

local function getClosestPlayer()
	local closestChar = nil
	local shortestDist = math.huge
	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") and not hitCooldowns[player.Name] then
			local hum = char:FindFirstChild("Humanoid")
			if hum and hum.Health > 0 and char ~= guard then
				local pPos = char.HumanoidRootPart.Position
				if isInsideZone(pPos) then
					local dist = (rootPart.Position - pPos).Magnitude
					if dist < shortestDist then
						shortestDist = dist
						closestChar = char
					end
				end
			end
		end
	end
	return closestChar
end

local function isPlayerInZone()
	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character

		if char and char:FindFirstChild("HumanoidRootPart") then
			local hum = char:FindFirstChild("Humanoid")

			if hum and hum.Health > 0 then
				if isInsideZone(char.HumanoidRootPart.Position) then
					return true
				end
			end
		end
	end

	return false
end

-- [[ 6. MAIN BEHAVIOR LOOP ]] --
-- [[ OPTIMIZED: Changed from 0.03 to 0.1 to save massive amounts of Server Compute Efficiency ]] --
while true do
	local active = isPlayerInZone()

	if active then
		task.wait(0.1)
	else
		task.wait(1)
	end

	-- Anti-Fling
	if rootPart.AssemblyLinearVelocity.Magnitude > 40 then
		rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end

	-- KNOCKBACK & FALL OVER
	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") and char ~= guard then
			local pRoot = char.HumanoidRootPart
			local pHum = char:FindFirstChild("Humanoid")

			local distXZ = (Vector2.new(pRoot.Position.X, pRoot.Position.Z) - Vector2.new(rootPart.Position.X, rootPart.Position.Z)).Magnitude
			local distY = math.abs(pRoot.Position.Y - rootPart.Position.Y)
			local HITBOX_HEIGHT = 16 
			local HIT_RADIUS_BUFFER = 2

			if distXZ <= (RING_RADIUS + HIT_RADIUS_BUFFER) and distY < HITBOX_HEIGHT and not hitCooldowns[player.Name] then
				if pHum and pHum.Health > 0 and not pHum.PlatformStand then
					hitCooldowns[player.Name] = true 

					Pickup.drop(player)

					pHum.PlatformStand = true 
					pHum.AutoRotate = false
					pHum:ChangeState(Enum.HumanoidStateType.FallingDown)

					pRoot.CFrame = pRoot.CFrame * CFrame.new(0, 2, 0) 
					local pushDir = (pRoot.Position - rootPart.Position).Unit
					pRoot.AssemblyLinearVelocity = (pushDir * KNOCKBACK_POWER) + Vector3.new(0, VERTICAL_LAUNCH, 0)
					pRoot.AssemblyAngularVelocity = Vector3.zero

					task.delay(3.0, function() 
						if char and pHum then 
							pHum.AutoRotate = true
							pHum.PlatformStand = false 
							pHum:ChangeState(Enum.HumanoidStateType.GettingUp)
							pRoot.AssemblyLinearVelocity = Vector3.new(0, 5, 0)
						end 
						task.wait(1.5) 
						hitCooldowns[player.Name] = nil 
					end)
				end
			end
		end
	end

	local target = getClosestPlayer()

	-- CHASE / ALERT LOGIC
	if target then
		state = "Moving"
		if not hasAlerted then
			if alertSound then
				alertSound:Stop()
				alertSound:Play()
			end
			hasAlerted = true
		end
		humanoid.WalkSpeed = 15
		humanoid:MoveTo(clampToZone(target.HumanoidRootPart.Position))
	else
		hasAlerted = false
		humanoid.WalkSpeed = 8
		if state == "Moving" then
			humanoid:MoveTo(currentGoal)
			if (rootPart.Position - currentGoal).Magnitude < 4 then
				state = "Resting"
				pauseEndTime = tick() + math.random(2, 5)
			end
		elseif state == "Resting" then
			humanoid:MoveTo(rootPart.Position)

			if tick() >= pauseEndTime then
				local b = ZONE_BOUNDS

				local randomX =
					b.minX + math.random() * (b.maxX - b.minX)

				local randomZ =
					b.minZ + math.random() * (b.maxZ - b.minZ)

				currentGoal = clampToZone(Vector3.new(
					randomX,
					rootPart.Position.Y,
					randomZ
					))

				state = "Moving"
			end
		end
	end

	-- Animation
	local moveVelocity = (rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	if moveVelocity > 0.5 then
		if not walkTrack.IsPlaying then walkTrack:Play() end
		walkTrack:AdjustSpeed(humanoid.WalkSpeed / 10)
	else
		if walkTrack.IsPlaying then walkTrack:Stop(0.3) end
	end

	-- Safety Boundary
	local b = ZONE_BOUNDS
	local p = rootPart.Position
	if p.X < b.minX-15 or p.X > b.maxX+15 or p.Z < b.minZ-15 or p.Z > b.maxZ+15 then
		rootPart.CFrame = CFrame.new(originPos + Vector3.new(0, 2, 0))
		rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
	end
end