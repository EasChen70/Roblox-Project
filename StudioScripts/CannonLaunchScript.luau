local smoothBlock = script.Parent
local seat = smoothBlock:FindFirstChild("CannonSeat")
local prompt = smoothBlock:FindFirstChild("ProximityPrompt")
local blastSound = smoothBlock:FindFirstChild("BlastSound")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Remotes = require(ReplicatedStorage.Remotes)
local Pickup = require(ServerScriptService:WaitForChild("Pickup"))

local LANDING_FOLDER = "XXXXXXXLandingParts" -- CHANGE PER CANNON

local CONFIG = {
	-- Trajectory tuning (preserved from original — DO NOT change without retesting flight feel)
	SPEED_DIVISOR = 40,            -- distance / SPEED_DIVISOR drives flight time
	MIN_TIME = 1.2,                -- minimum flight duration in seconds
	MAX_TIME = 3.4,                -- maximum flight duration in seconds
	MIN_VERTICAL = 70,             -- minimum upward velocity at launch
	MAX_POWER = 130,               -- max CannonPower attribute clamp
	PRE_LAUNCH_DELAY = 0.8,        -- pose hold time before blast
	-- Arrival detection
	ARRIVAL_RADIUS = 10,           -- horizontal distance to target that counts as "arrived"
	FLIGHT_TIMEOUT = 10,           -- abort flight loop after this many seconds
	-- Descent + landing
	DESCEND_VELOCITY = Vector3.new(0, -120, 0),
	DESCEND_TIMEOUT = 5,           -- abort descent loop after this many seconds
	RAYCAST_DISTANCE = Vector3.new(0, -10, 0),
	LANDING_Y_TOLERANCE = 3.5,
	LANDING_SETTLE_DELAY = 0.15,
}

local ZONE_FOLDERS = {
	"SpawnZones", "SpawnZonesRare", "SpawnZonesEpic",
	"SpawnZonesLegendary", "SpawnZonesMythic", "SpawnZonesSecret", "SpawnZonesDivine"
}

local function findLandingTarget(power)
	local partName = "LandingPart" .. power
	for _, folderName in ZONE_FOLDERS do
		local zone = workspace:FindFirstChild(folderName)
		if zone then
			local landingFolder = zone:FindFirstChild(LANDING_FOLDER)
			if landingFolder then
				local part = landingFolder:FindFirstChild(partName)
				if part and part:IsA("BasePart") then return part end
			end
		end
	end
	warn("[Cannon] No LandingPart found for power", power, "in", LANDING_FOLDER)
	return nil
end

prompt.Triggered:Connect(function(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hum) then return end

	local _cp = player:GetAttribute("CannonPower")
	local launchPower = math.clamp((_cp or 1), 1, CONFIG.MAX_POWER)
	local targetPart = findLandingTarget(launchPower)
	if not targetPart then
		warn("[Cannon] No LandingPart found for power", launchPower)
		return
	end

	local targetPos = targetPart.Position
	prompt.Enabled = false

	-- Guard the synchronous pre-launch + launch portion. If any hrp/hum
	-- write throws (character destroyed mid-handler), prompt would
	-- otherwise stay disabled forever.
	local handlerOk, handlerErr = pcall(function()
		-- RESET & ALIGN
		Remotes.CannonDropEvent:FireClient(player, "Reset")
		hrp.Anchored = true
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hrp.CFrame = CFrame.lookAt(seat.Position, Vector3.new(targetPos.X, seat.Position.Y, targetPos.Z))
			* CFrame.Angles(math.rad(-45), 0, 0)
			* CFrame.new(0, 1, 0)

		task.wait(CONFIG.PRE_LAUNCH_DELAY)

		-- Re-check after the yield — character may have died or left
		if not (hrp.Parent and hum.Parent) then
			error("character lost during pre-launch wait")
		end

		-- Calculate velocity while anchored (preserved physics)
		local g = workspace.Gravity
		local delta = targetPos - hrp.Position
		local totalDistance = delta.Magnitude
		local T = math.clamp(totalDistance / CONFIG.SPEED_DIVISOR, CONFIG.MIN_TIME, CONFIG.MAX_TIME)
		local horizontalVel = Vector3.new(delta.X / T, 0, delta.Z / T)
		local verticalVel = math.max(delta.Y / T + 0.5 * g * T, CONFIG.MIN_VERTICAL)
		local launchVelocity = horizontalVel + Vector3.new(0, verticalVel, 0)

		-- Unanchor then fire velocity to client
		if blastSound then blastSound:Play() end
		hrp.Anchored = false

		-- Restore explicit network ownership to the launching player.
		-- Without this, Roblox's automatic ownership assignment can flip
		-- HRP ownership to the server mid-flight, exposing the character
		-- to server-side seat handlers and other physics interactions.
		pcall(function()
			hrp:SetNetworkOwner(player)
		end)

		hum.PlatformStand = true
		Remotes.CannonDropEvent:FireClient(player, "Launch", launchVelocity)

		local launchTime = tick()

		task.spawn(function()
			local taskOk, taskErr = pcall(function()
				local arrived = false
				local timeout = tick() + CONFIG.FLIGHT_TIMEOUT

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

							-- Fire Descend event to client (matches return cannon protocol).
							-- Client applies descent velocity locally on its own HRP, which
							-- is more reliable than writing velocity from the server.
							Remotes.CannonDropEvent:FireClient(
								player,
								"Descend",
								CONFIG.DESCEND_VELOCITY
							)

							local landed = false
							local landingGroundY = nil
							local descendStart = tick()

							while not landed and hrp.Parent and tick() - descendStart < CONFIG.DESCEND_TIMEOUT do
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

								task.wait(CONFIG.LANDING_SETTLE_DELAY)

								if hrp.Parent then
									hrp.Anchored = false
								end
							end
						end
					else
						break
					end

					task.wait()
				end
			end)

			if not taskOk then
				warn("[Cannon] flight task error for", player.Name, "—", taskErr)
			end

			-- Always re-enable the prompt, even if the flight task errored
			prompt.Enabled = true
		end)
	end)

	if not handlerOk then
		warn("[Cannon] setup error for", player.Name, "—", handlerErr)
		-- Setup errored before task.spawn ran; restore prompt manually
		prompt.Enabled = true
	end
end)