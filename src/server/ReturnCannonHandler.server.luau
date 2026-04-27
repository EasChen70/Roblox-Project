local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Remotes = require(ReplicatedStorage.Remotes)

local DEBUG_CANNON = true
local DEBUG_SAMPLE_INTERVAL = 0.25
local nextFlightDebugId = 0

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

local function debugLog(debugId, ...)
	if not DEBUG_CANNON then
		return
	end

	print(string.format("[ReturnCannon][%s]", debugId), ...)
end

local function debugWarn(debugId, ...)
	warn(string.format("[ReturnCannon][%s]", debugId), ...)
end

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
	-- characters onto Seat instances is now off - important because flights
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

		local debugId = getFlightDebugId(player)
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

			-- Re-check after the yield - character may have died or left
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

			debugLog(
				debugId,
				"launch setup",
				"player=" .. player.Name,
				"targetPos=" .. formatVector3(targetPos),
				"T=" .. string.format("%.2f", T),
				"launchVelocity=" .. formatVector3(launchVelocity),
				"ownerAfterSet=" .. getNetworkOwnerLabel(hrp)
			)

			Remotes.CannonDropEvent:FireClient(player, "Launch", launchVelocity)

			local launchTime = tick()

			task.spawn(function()
				local taskOk, taskErr = pcall(function()
					local arrived = false
					local timeout = tick() + 10
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
									"flightTime=" .. string.format("%.2f", flightTime)
								)
							end

							local reachedRadius = horizontalDist < CONFIG.ARRIVAL_RADIUS
							local reachedTime = flightTime >= T

							if reachedRadius or reachedTime then
								arrived = true

								local descendReason = "time"
								if reachedRadius and reachedTime then
									descendReason = "radius+time"
								elseif reachedRadius then
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
								local landingReason = "timeout"
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
										landingReason = "raycast"
										debugLog(
											debugId,
											"landing detected",
											"reason=raycast",
											"hit=" .. ray.Instance:GetFullName(),
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
									debugLog(
										debugId,
										"landing finalizing after timeout",
										"pos=" .. formatVector3(hrp.Position),
										"vel=" .. formatVector3(hrp.AssemblyLinearVelocity)
									)
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

									debugLog(
										debugId,
										"landing complete",
										"landingReason=" .. landingReason,
										"finalPos=" .. formatVector3(hrp.Position),
										"finalVel=" .. formatVector3(hrp.AssemblyLinearVelocity)
									)
								end
							end
						else
							debugLog(debugId, "flight loop ended because character/root is missing")
							break
						end

						task.wait()
					end
				end)

				if not taskOk then
					debugWarn(debugId, "flight task error for", player.Name, "-", taskErr)
				end

				-- Always re-enable the prompt, even if the flight task errored
				prompt.Enabled = true
			end)
		end)

		if not handlerOk then
			debugWarn(debugId, "setup error for", player.Name, "-", handlerErr)
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
