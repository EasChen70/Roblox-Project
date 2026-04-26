local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Remotes = require(ReplicatedStorage.Remotes)

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

	-- Disable seat auto-sit. The seat's CFrame is still used as the launch
	-- pose anchor, but Roblox's built-in Touched-handler that snaps passing
	-- characters onto Seat instances is now off — important because flights
	-- can pass near other cannons' seats and get hijacked mid-air.
	if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
		seat.Disabled = true
	end

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
			return
		end

		prompt.Enabled = false

		-- Guard the synchronous pre-launch + launch portion. If any hrp/hum
		-- write throws (character destroyed mid-handler), prompt would
		-- otherwise stay disabled forever.
		local handlerOk, handlerErr = pcall(function()
			Remotes.CannonDropEvent:FireClient(player, "Reset")

			hrp.Anchored = true
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			hrp.CFrame = seat.CFrame * CFrame.Angles(math.rad(-45), 0, 0) * CFrame.new(0, 1, 0)

			task.wait(1)

			-- Re-check after the yield — character may have died or left
			if not (hrp.Parent and hum.Parent) then
				error("character lost during pre-launch wait")
			end

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

			-- Restore explicit network ownership to the launching player.
			-- Without this, Roblox's automatic ownership assignment can flip
			-- HRP ownership to the server mid-flight (e.g. when the player
			-- moves out of the closest-player range), which lets server-side
			-- seat Touched-handlers grab the character. Matches the old
			-- working implementation.
			pcall(function()
				hrp:SetNetworkOwner(player)
			end)

			hum.PlatformStand = true

			Remotes.CannonDropEvent:FireClient(player, "Launch", launchVelocity)

			local launchTime = tick()

			task.spawn(function()
				local taskOk, taskErr = pcall(function()
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

								Remotes.CannonDropEvent:FireClient(
									player,
									"Descend",
									CONFIG.DESCEND_VELOCITY
								)

								local landed = false
								local landingGroundY = nil
								local descendStart = tick()

								while not landed and hrp.Parent and tick() - descendStart < 5 do
									local rayParams = RaycastParams.new()
									rayParams.FilterDescendantsInstances = {char}
									rayParams.FilterType = Enum.RaycastFilterType.Exclude

									local ray = workspace:Raycast(
										hrp.Position,
										CONFIG.RAYCAST_DISTANCE,
										rayParams
									)

									if ray then
										landed = true
										landingGroundY = ray.Position.Y
									elseif hrp.Position.Y <= (targetPos.Y + CONFIG.LANDING_Y_TOLERANCE) then
										landed = true
										-- no ground data; skip snap, fall through to existing finalization
									end

									task.wait()
								end

								-- Only finalize landing if hrp survived the descent
								if hrp.Parent then
									hrp.Anchored = true

									if landingGroundY then
										hrp.CFrame = CFrame.new(hrp.Position.X, landingGroundY + 2, hrp.Position.Z)
									end

									hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
									hum.PlatformStand = false
									hum:ChangeState(Enum.HumanoidStateType.Landed)

									task.wait(0.15)

									if hrp.Parent then
										hrp.Anchored = false
									end

									print("[ReturnCannon] Landing complete, player unanchored")
								end
							end
						else
							break
						end

						task.wait()
					end
				end)

				if not taskOk then
					warn("[ReturnCannon] flight task error for", player.Name, "—", taskErr)
				end

				-- Always re-enable the prompt, even if the flight task errored
				prompt.Enabled = true
			end)
		end)

		if not handlerOk then
			warn("[ReturnCannon] setup error for", player.Name, "—", handlerErr)
			-- Setup errored before task.spawn ran; restore prompt manually
			prompt.Enabled = true
		end
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