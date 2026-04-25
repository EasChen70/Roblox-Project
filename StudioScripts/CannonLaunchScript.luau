local smoothBlock = script.Parent
local seat = smoothBlock:FindFirstChild("CannonSeat")
local prompt = smoothBlock:FindFirstChild("ProximityPrompt")
local blastSound = smoothBlock:FindFirstChild("BlastSound")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CannonDropEvent = ReplicatedStorage:WaitForChild("CannonDropEvent")

local function findLandingTarget(power)
	local ZONE_FOLDERS = {"SpawnZones","SpawnZonesRare","SpawnZonesEpic","SpawnZonesLegendary","SpawnZonesMythic","SpawnZonesSecret","SpawnZonesDivine"}
	local partName = "LandingPart" .. power
	for _, folderName in ZONE_FOLDERS do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			local part = folder:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") then return part end
		end
	end
	return nil
end

prompt.Triggered:Connect(function(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hum) then return end

	local _cp = player:GetAttribute("CannonPower")
	local launchPower = math.clamp((_cp or 1), 1, 130)

	local targetPart = findLandingTarget(launchPower)
	if not targetPart then return end
	local targetPos = targetPart.Position

	prompt.Enabled = false

	-- --- RESET & ALIGN ---
	CannonDropEvent:FireClient(player, "Reset")
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)

	hrp.CFrame = CFrame.lookAt(seat.Position, Vector3.new(targetPos.X, seat.Position.Y, targetPos.Z))
		* CFrame.Angles(math.rad(-45), 0, 0)
		* CFrame.new(0, 1, 0)

	task.wait(0.8)

	-- --- LAUNCH ---
	if blastSound then blastSound:Play() end
	hrp.Anchored = false
	pcall(function() hrp:SetNetworkOwner(player) end)
	hum.PlatformStand = true

	local g = workspace.Gravity
	local delta = targetPos - hrp.Position
	local totalDistance = delta.Magnitude
	local T = math.clamp(totalDistance / 40, 1.2, 3.0)

	local horizontalVel = Vector3.new(delta.X / T, 0, delta.Z / T)
	local verticalVel = delta.Y / T + 0.5 * g * T

	hrp.AssemblyLinearVelocity = horizontalVel + Vector3.new(0, verticalVel, 0)

	CannonDropEvent:FireClient(player, "Launch")

	local launchTime = tick()

	-- --- LANDING CONTROLLER ---
	task.spawn(function()
		local arrived = false
		local timeout = tick() + 10

		while not arrived and tick() < timeout do
			if hrp and hrp.Parent then
				local horizontalDist = (
					Vector3.new(targetPos.X, 0, targetPos.Z) -
						Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
				).Magnitude
				local flightTime = tick() - launchTime

				if horizontalDist < 8 or flightTime >= T then
					arrived = true
					CannonDropEvent:FireClient(player, "Reset")

					local fallWait = math.clamp(0.3 - (totalDistance / 800), 0.05, 0.3)
					task.wait(fallWait)
					if launchPower == 1 then
						task.wait(0.5)
					end

					local landed = false
					while not landed and hrp.Parent do
						local ray = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0))
						if ray then
							local vel = hrp.AssemblyLinearVelocity
							hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 0.1, vel.Y, vel.Z * 0.1)
							landed = true
						end
						task.wait()
					end

					hrp.Anchored = true
					hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					hum.PlatformStand = false
					hum:ChangeState(Enum.HumanoidStateType.Landed)
					task.wait(0.2)
					hrp.Anchored = false
				end
			else break end
			task.wait()
		end
	end)

	task.wait(1.5)
	prompt.Enabled = true
end)
