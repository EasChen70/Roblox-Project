local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Remotes = require(ReplicatedStorage.Remotes) -- CHANGED: use Remotes module

local CONFIG = {
	SPEED_DIVISOR = 40,
	MIN_TIME = 1.2,
	MAX_TIME = 3.0,
	MIN_VERTICAL = 80,
	ARRIVAL_RADIUS = 15,
	DESCEND_VELOCITY = Vector3.new(0, -120, 0),
	RAYCAST_DISTANCE = Vector3.new(0, -7, 0),
	LANDING_Y_TOLERANCE = 3.5,
}

local function setupReturnCannon(model)
	local seat = model:FindFirstChild("CannonSeat", true)
	local prompt = model:FindFirstChild("ProximityPrompt", true)
	local blastSound = model:FindFirstChild("BlastSound", true)

	if not (seat and prompt) then
		warn("[ReturnCannon] Missing seat or prompt in", model:GetFullName())
		return
	end

	local phase = "IDLE" -- CHANGED: IDLE | LAUNCH | FLIGHT | DESCEND

	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		local playerBase = nil
		local success, result = pcall(function()
			return require(ServerScriptService.Base).getPlayerBase(player)
		end)
		if success then 
			playerBase = result 
		end

		if not (hrp and hum and playerBase) then
			prompt.Enabled = true
			return
		end

		prompt.Enabled = false

		phase = "IDLE" -- CHANGED

		if phase == "IDLE" then -- CHANGED
			Remotes.CannonDropEvent:FireClient(player, "Reset")
		end

		phase = "LAUNCH" -- CHANGED

		hrp.Anchored = true
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hrp.CFrame = seat.CFrame * CFrame.Angles(math.rad(-45), 0, 0) * CFrame.new(0, 1, 0)

		task.wait(1)

		if blastSound then
			blastSound:Play()
		end

		local targetPos = playerBase:GetPivot().Position
		local g = workspace.Gravity
		local delta = targetPos - hrp.Position
		local totalDistance = delta.Magnitude

		local T = math.clamp(
			totalDistance / CONFIG.SPEED_DIVISOR,
			CONFIG.MIN_TIME,
			CONFIG.MAX_TIME
		)

		local horizontalVel = Vector3.new(delta.X / T, 0, delta.Z / T)

		local verticalVel = math.max(
			delta.Y / T + 0.5 * g * T,
			CONFIG.MIN_VERTICAL
		)

		local launchVelocity = horizontalVel + Vector3.new(0, verticalVel, 0)

		hrp.Anchored = false
		hum.PlatformStand = true

		Remotes.CannonDropEvent:FireClient(player, "Launch", launchVelocity)

		local launchTime = tick()

		task.spawn(function()
			local arrived = false
			local timeout = tick() + 10

			while not arrived and tick() < timeout do
				if hrp and hrp.Parent then
					local currentPos = hrp.Position

					local horizontalDist = (
						Vector3.new(targetPos.X, 0, targetPos.Z) -
						Vector3.new(currentPos.X, 0, currentPos.Z)
					).Magnitude

					local flightTime = tick() - launchTime

					if horizontalDist < CONFIG.ARRIVAL_RADIUS or flightTime >= T then
						arrived = true

						-- CHANGED: removed Reset here completely
						phase = "DESCEND" -- CHANGED

						Remotes.CannonDropEvent:FireClient(
							player,
							"Descend",
							CONFIG.DESCEND_VELOCITY
						)

						local landed = false
						while not landed and hrp.Parent do
							local rayParams = RaycastParams.new()
							rayParams.FilterDescendantsInstances = {char}
							rayParams.FilterType = Enum.RaycastFilterType.Exclude

							local ray = workspace:Raycast(
								hrp.Position,
								CONFIG.RAYCAST_DISTANCE,
								rayParams
							)

							if ray or hrp.Position.Y <= (targetPos.Y + CONFIG.LANDING_Y_TOLERANCE) then
								landed = true
							end

							task.wait()
						end

						hrp.Anchored = true
						hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						hum.PlatformStand = false
						hum:ChangeState(Enum.HumanoidStateType.Landed)

						task.wait(0.15)

						hrp.Anchored = false

						print("[ReturnCannon] Landing complete, player unanchored")
					end
				else
					break
				end

				task.wait()
			end

			prompt.Enabled = true
		end)
	end)
end

for _, obj in workspace:GetDescendants() do
	if obj.Name == "ReturnCannonModel" and obj:IsA("Model") then
		setupReturnCannon(obj)
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj.Name == "ReturnCannonModel" and obj:IsA("Model") then
		task.wait()
		setupReturnCannon(obj)
	end
end)