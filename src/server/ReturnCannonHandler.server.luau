local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CannonDropEvent = ReplicatedStorage:WaitForChild("CannonDropEvent")

local function setupReturnCannon(model)
	local seat = model:FindFirstChild("CannonSeat", true)
	local prompt = model:FindFirstChild("ProximityPrompt", true)
	local blastSound = model:FindFirstChild("BlastSound", true)

	if not (seat and prompt) then
		warn("[ReturnCannon] Missing seat or prompt in", model:GetFullName())
		return
	end

	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		local playerBase = nil
		local success, result = pcall(function()
			return require(ServerScriptService.Base).getPlayerBase(player)
		end)
		if success then playerBase = result end

		if not (hrp and hum and playerBase) then
			prompt.Enabled = true
			return
		end

		prompt.Enabled = false

		CannonDropEvent:FireClient(player, "Reset")
		hrp.Anchored = true
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hrp.CFrame = seat.CFrame * CFrame.Angles(math.rad(-45), 0, 0) * CFrame.new(0, 1, 0)
		task.wait(1)

		if blastSound then blastSound:Play() end
		hrp.Anchored = false
		pcall(function() hrp:SetNetworkOwner(player) end)
		hum.PlatformStand = true

		local targetPos = playerBase:GetPivot().Position
		local g = workspace.Gravity
		local delta = targetPos - hrp.Position
		local totalDistance = delta.Magnitude
		local T = math.clamp(totalDistance / 40, 1.2, 3.0)

		local horizontalVel = Vector3.new(delta.X / T, 0, delta.Z / T)
		local verticalVel = math.max(delta.Y / T + 0.5 * g * T, 80)

		hrp.AssemblyLinearVelocity = horizontalVel + Vector3.new(0, verticalVel, 0)

		CannonDropEvent:FireClient(player, "Launch")

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

					if horizontalDist < 15 or flightTime >= T then
						arrived = true
						CannonDropEvent:FireClient(player, "Reset")

						hrp.AssemblyLinearVelocity = Vector3.new(0, -120, 0)

						local landed = false
						while not landed and hrp.Parent do
							local rayParams = RaycastParams.new()
							rayParams.FilterDescendantsInstances = {char}
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ray = workspace:Raycast(hrp.Position, Vector3.new(0, -7, 0), rayParams)
							if ray or hrp.Position.Y <= (targetPos.Y + 3.5) then
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
					end
				else
					break
				end
				task.wait()
			end

			prompt.Enabled = true
		end)

		task.wait(1.5)
		prompt.Enabled = true
	end)
end

-- Wire up all existing ReturnCannonModels
for _, obj in workspace:GetDescendants() do
	if obj.Name == "ReturnCannonModel" and obj:IsA("Model") then
		setupReturnCannon(obj)
	end
end

-- Handle any added later
workspace.DescendantAdded:Connect(function(obj)
	if obj.Name == "ReturnCannonModel" and obj:IsA("Model") then
		task.wait() -- let it fully load
		setupReturnCannon(obj)
	end
end)