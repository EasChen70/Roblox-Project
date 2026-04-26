local guard = script.Parent
local humanoid = guard:WaitForChild("Humanoid")
local rootPart = guard:WaitForChild("HumanoidRootPart")
local model = guard.Parent
local zonePart = model:WaitForChild("CommonSpawnZonePart")
local PhysicsService = game:GetService("PhysicsService")

-- [[ 1. RIGID IMMUNITY & COLLISION SETUP ]] --
humanoid.MaxHealth = math.huge
humanoid.Health = math.huge
rootPart:SetNetworkOwner(nil)
guard:SetAttribute("IsInvincible", true)

-- Setup Collision Groups (Prevents the "Launch/Kick" bug)
pcall(function() PhysicsService:RegisterCollisionGroup("Guards") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)
PhysicsService:CollisionGroupSetCollidable("Guards", "Players", false)

for _, part in pairs(guard:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Massless = true 
		part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5) 
		part.CollisionGroup = "Guards"
	end
end

local function setupPlayerCollision(character)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
end

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(setupPlayerCollision)
end)

humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

-- [[ 2. VARIABLES ]] --
local originPos = rootPart.Position
local alertSound = guard:FindFirstChild("AlertSound", true) 
local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = "http://www.roblox.com/asset/?id=507767714" 
local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:AddComponent("Animator")
local walkTrack = animator:LoadAnimation(walkAnim)
walkTrack.Priority = Enum.AnimationPriority.Action
walkTrack.Looped = true

local currentGoal = rootPart.Position
local state = "Moving" 
local pauseEndTime = 0
local hasAlerted = false

-- [[ 3. LOGIC FUNCTIONS ]] --

local function getZoneBounds()
	local pos = zonePart.Position
	local size = zonePart.Size
	return {
		minX = pos.X - (size.X/2),
		maxX = pos.X + (size.X/2),
		minZ = pos.Z - (size.Z/2),
		maxZ = pos.Z + (size.Z/2)
	}
end

local function isInsideZone(pos)
	local b = getZoneBounds()
	-- Checks if a position is within the X and Z boundaries of the ZonePart
	return pos.X >= b.minX and pos.X <= b.maxX and pos.Z >= b.minZ and pos.Z <= b.maxZ
end

local function clampToZone(targetPos)
	local b = getZoneBounds()
	local buffer = 4
	return Vector3.new(
		math.clamp(targetPos.X, b.minX + buffer, b.maxX - buffer),
		rootPart.Position.Y,
		math.clamp(targetPos.Z, b.minZ + buffer, b.maxZ - buffer)
	)
end

-- Scans all players and returns the absolute closest one in the zone
local function getClosestPlayer()
	local closestChar = nil
	local shortestDist = math.huge

	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
			if char.Humanoid.Health > 0 and char ~= guard then
				local pPos = char.HumanoidRootPart.Position

				-- Step 1: Are they in the zone?
				if isInsideZone(pPos) then
					-- Step 2: How far are they?
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

-- [[ 4. MAIN BEHAVIOR LOOP ]] --
-- This runs 10 times a second to ensure targets switch instantly
while task.wait(0.1) do
	humanoid.Health = math.huge

	-- Stop slaps from moving him
	if rootPart.AssemblyLinearVelocity.Magnitude > 20 then
		rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end

	-- RE-EVALUATE TARGET EVERY 0.1 SECONDS
	local target = getClosestPlayer()

	-- Animation Control
	if rootPart.AssemblyLinearVelocity.Magnitude > 0.5 then
		if not walkTrack.IsPlaying then walkTrack:Play() end
		walkTrack:AdjustSpeed(target and 1.2 or 0.6)
	else
		walkTrack:Stop()
	end

	if target then
		-- CHASE LOGIC
		state = "Moving"
		if not hasAlerted then
			if alertSound then alertSound:Play() end
			hasAlerted = true
		end

		humanoid.WalkSpeed = 18
		-- Move toward the current closest player
		humanoid:MoveTo(clampToZone(target.HumanoidRootPart.Position))
	else
		-- WANDER/IDLE LOGIC
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
				local b = getZoneBounds()
				currentGoal = clampToZone(Vector3.new(
					math.random(b.minX, b.maxX),
					rootPart.Position.Y,
					math.random(b.minZ, b.maxZ)
					))
				state = "Moving"
			end
		end
	end

	-- Safety boundary snap
	local b = getZoneBounds()
	local p = rootPart.Position
	if p.X < b.minX-5 or p.X > b.maxX+5 or p.Z < b.minZ-5 or p.Z > b.maxZ+5 then
		rootPart.CFrame = CFrame.new(originPos + Vector3.new(0, 2, 0))
	end
end
