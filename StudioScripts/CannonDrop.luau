local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local player = game.Players.LocalPlayer
local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")
local cannonGui = playerGui:WaitForChild("CannonGui")
local dropHint = cannonGui:WaitForChild("DropHint")

local DEBUG_CANNON = true
local DEBUG_SAMPLE_INTERVAL = 0.25
local DEBUG_SAMPLE_DURATION = 3

local canDrop = false
local currentLaunchId = 0
local isDescending = false

local function seatPartLabel(seatPart)
	if not seatPart then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return seatPart:GetFullName()
	end)

	if ok then
		return fullName
	end

	return seatPart.Name
end

local function logCannon(debugId, ...)
	if not DEBUG_CANNON then
		return
	end

	print(string.format("[CannonDrop][%s]", tostring(debugId)), ...)
end

local function isFlightActive()
	return canDrop or isDescending or hum.PlatformStand
end

local function setCharacterCanCollide(state)
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = state
		end
	end
end

local function forceUpright()
	canDrop = false
	dropHint.Visible = false
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

local function freezeMomentum()
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	hum:ChangeState(Enum.HumanoidStateType.Landed)
end

Remotes.CannonDropEvent.OnClientEvent:Connect(function(mode, velocity)
	if mode == "Reset" then
		logCannon(currentLaunchId, "Reset received", "isDescending=" .. tostring(isDescending), "canDrop=" .. tostring(canDrop))
		isDescending = false
		forceUpright()
		logCannon(currentLaunchId, "Reset complete", "isDescending=" .. tostring(isDescending))
	elseif mode == "Launch" then
		logCannon(currentLaunchId, "Launch received", "velocity=" .. tostring(velocity), "isDescending=" .. tostring(isDescending))
		isDescending = false
		setCharacterCanCollide(false)
		hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		hrp.AssemblyLinearVelocity = velocity
		canDrop = true
		currentLaunchId += 1
		local thisLaunch = currentLaunchId
		logCannon(thisLaunch, "Launch applied", "isDescending=" .. tostring(isDescending))
		dropHint.Visible = true
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

		task.spawn(function()
			local launchStart = tick()
			while tick() - launchStart <= DEBUG_SAMPLE_DURATION do
				task.wait(DEBUG_SAMPLE_INTERVAL)
				if currentLaunchId ~= thisLaunch then
					logCannon(thisLaunch, "Flight sampler stopped", "reason=launchId_changed")
					break
				end

				logCannon(
					thisLaunch,
					"Flight sample",
					"t=" .. string.format("%.2f", tick() - launchStart),
					"pos=" .. tostring(hrp.Position),
					"vel=" .. tostring(hrp.AssemblyLinearVelocity),
					"platformStand=" .. tostring(hum.PlatformStand),
					"sit=" .. tostring(hum.Sit),
					"seatPart=" .. seatPartLabel(hum.SeatPart)
				)
			end
		end)

		task.delay(1.5, function()
			if canDrop and currentLaunchId == thisLaunch then
				dropHint.Visible = false
				logCannon(thisLaunch, "DropHint auto-hidden")
			end
		end)
	elseif mode == "Descend" then
		logCannon(currentLaunchId, "Descend received", "velocity=" .. tostring(velocity), "isDescending=" .. tostring(isDescending))
		hrp.AssemblyLinearVelocity = velocity
	else
		logCannon(currentLaunchId, "Unknown mode received", tostring(mode))
	end
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Space and canDrop then
		logCannon(currentLaunchId, "Space drop triggered")

		canDrop = false
		isDescending = true
		dropHint.Visible = false

		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		setCharacterCanCollide(true)

		local dropForce = -150
		hrp.AssemblyLinearVelocity = Vector3.new(0, dropForce, 0)
		hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

		logCannon(currentLaunchId, "Space drop applied", "dropForce=" .. tostring(dropForce))
	end
end)

hum.Seated:Connect(function(active, seatPart)
	if isFlightActive() or active then
		logCannon(
			currentLaunchId,
			"Seated changed",
			"active=" .. tostring(active),
			"seatPart=" .. seatPartLabel(seatPart)
		)
	end
end)

hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
	if isFlightActive() then
		logCannon(currentLaunchId, "SeatPart changed", "seatPart=" .. seatPartLabel(hum.SeatPart))
	end
end)

hum.StateChanged:Connect(function(_, newState)
	if newState == Enum.HumanoidStateType.Landed then
		if isDescending then
			logCannon(currentLaunchId, "Landed during descent", "isDescending=" .. tostring(isDescending))
			isDescending = false
			setCharacterCanCollide(true)
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			return
		end

		if canDrop and not isDescending then
			logCannon(currentLaunchId, "Landed fired during active flight before client freeze")
		end

		logCannon(
			currentLaunchId,
			"Landed normally - freezing",
			"canDrop=" .. tostring(canDrop),
			"isDescending=" .. tostring(isDescending)
		)
		setCharacterCanCollide(true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		forceUpright()
		freezeMomentum()
		dropHint.Visible = false
	else
		logCannon(
			currentLaunchId,
			"State changed",
			"state=" .. tostring(newState),
			"canDrop=" .. tostring(canDrop),
			"isDescending=" .. tostring(isDescending),
			"sit=" .. tostring(hum.Sit),
			"seatPart=" .. seatPartLabel(hum.SeatPart)
		)
	end
end)
