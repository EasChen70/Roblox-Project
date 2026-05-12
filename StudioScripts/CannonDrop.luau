local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local player = game.Players.LocalPlayer
local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")
local cannonGui = playerGui:WaitForChild("CannonGui")
local landButton = cannonGui:WaitForChild("LandButton")

local DEBUG_CANNON = false
local DEBUG_SAMPLE_INTERVAL = 0.25
local DEBUG_SAMPLE_DURATION = 3

local canDrop = false
local currentLaunchId = 0
local isDescending = false
local isPreparing = false
local isFlightSessionActive = false
local sessionToken = 0
local controlsDisabled = false
local flightSampleToken = 0
local cachedLocomotion = nil
local prepLocomotionLocked = false
local sessionEndedByDeath = false
local zeroVector = Vector3.new(0, 0, 0)
local DROP_FORCE = -150

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

local function styleButton()
	landButton.Size = UDim2.fromScale(0.15, 0.08)
	landButton.Position = UDim2.fromScale(0.5, 0.72)
	landButton.AnchorPoint = Vector2.new(0.5, 0.5)
	landButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	landButton.Text = "Land"
	landButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	landButton.Font = Enum.Font.DenkOne
	landButton.TextScaled = true
	landButton.ZIndex = 10
	landButton.Active = true
	landButton.Selectable = true
	landButton.Visible = false

	local texture = landButton:FindFirstChild("ButtonTexture") or Instance.new("ImageLabel")
	texture.Name = "ButtonTexture"
	texture.BackgroundTransparency = 1
	texture.Image = "rbxassetid://6927295847"
	texture.Size = UDim2.fromScale(1, 1)
	texture.ScaleType = Enum.ScaleType.Tile
	texture.TileSize = UDim2.new(0, 128, 0, 128)
	texture.ImageTransparency = 0.4
	texture.ZIndex = 1
	texture.Active = false
	texture.Parent = landButton

	local corner = landButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = landButton

	local aspect = landButton:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.66
	aspect.Parent = landButton

	local buttonStroke = landButton:FindFirstChild("ButtonStroke") or Instance.new("UIStroke")
	buttonStroke.Name = "ButtonStroke"
	buttonStroke.Color = Color3.fromRGB(255, 255, 255)
	buttonStroke.Thickness = 2
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = landButton

	local textStroke = landButton:FindFirstChild("TextStroke") or Instance.new("UIStroke")
	textStroke.Name = "TextStroke"
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.Parent = landButton
end

local function setLandButtonVisible(visible)
	landButton.Visible = visible
end

local function isCannonSessionActive()
	return isPreparing or isFlightSessionActive or canDrop or isDescending or hum.PlatformStand
end

local function setCharacterCanCollide(state)
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = state
		end
	end
end

local function getLocalControls()
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end

	local ok, moduleOrErr = pcall(require, playerModule)
	if not ok or type(moduleOrErr) ~= "table" or type(moduleOrErr.GetControls) ~= "function" then
		return nil
	end

	local controlsOk, controls = pcall(function()
		return moduleOrErr:GetControls()
	end)
	if not controlsOk then
		return nil
	end

	return controls
end

local function isHumanoidAlive()
	return hum.Parent ~= nil and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead
end

local function disableLocalControls()
	if controlsDisabled then
		return
	end

	local controls = getLocalControls()
	if controls and type(controls.Disable) == "function" then
		pcall(function()
			controls:Disable()
		end)
		controlsDisabled = true
	end
end

local function enableLocalControls(forceEnable)
	if not forceEnable and not controlsDisabled then
		return
	end

	local controls = getLocalControls()
	if controls and type(controls.Enable) == "function" then
		pcall(function()
			controls:Enable()
		end)
	end

	controlsDisabled = false
end

local function clearLocalMovementIntent()
	if not isHumanoidAlive() then
		return
	end

	hum.Jump = false
	pcall(function()
		hum:Move(zeroVector, true)
	end)
end

local function applyPrepLocomotionLock()
	if not isHumanoidAlive() then
		return
	end

	if not prepLocomotionLocked then
		cachedLocomotion = {
			walkSpeed = hum.WalkSpeed,
			jumpPower = hum.JumpPower,
			jumpHeight = hum.JumpHeight,
		}
		prepLocomotionLocked = true
	end

	hum.WalkSpeed = 0
	if hum.UseJumpPower then
		hum.JumpPower = 0
	else
		hum.JumpHeight = 0
	end
end

local function clearPrepLocomotionState()
	cachedLocomotion = nil
	prepLocomotionLocked = false
end

local function restorePrepLocomotion()
	if not prepLocomotionLocked then
		return
	end

	if not isHumanoidAlive() then
		clearPrepLocomotionState()
		return
	end

	if cachedLocomotion then
		hum.WalkSpeed = cachedLocomotion.walkSpeed
		hum.JumpPower = cachedLocomotion.jumpPower
		hum.JumpHeight = cachedLocomotion.jumpHeight
	end

	clearPrepLocomotionState()
end

local function startPrepareLockLoop(activeSessionToken)
	task.spawn(function()
		while isPreparing and sessionToken == activeSessionToken do
			applyPrepLocomotionLock()
			clearLocalMovementIntent()
			if hrp.Parent then
				hrp.AssemblyAngularVelocity = zeroVector
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function forceUpright()
	if not isHumanoidAlive() then
		return
	end

	hum.PlatformStand = false
	hum.Jump = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	if hrp.Parent then
		hrp.AssemblyAngularVelocity = zeroVector
	end
end

local function freezeMomentum()
	if not isHumanoidAlive() then
		return
	end

	if hrp.Parent then
		hrp.Anchored = false
		hrp.AssemblyLinearVelocity = zeroVector
		hrp.AssemblyAngularVelocity = zeroVector
	end

	if hum.Parent then
		hum:ChangeState(Enum.HumanoidStateType.Landed)
	end
end

local function beginCannonSession()
	sessionToken += 1
	flightSampleToken += 1
	isPreparing = true
	isFlightSessionActive = true
	canDrop = false
	isDescending = false
	sessionEndedByDeath = false
	return sessionToken
end

local function clearCannonSessionState()
	sessionToken += 1
	flightSampleToken += 1
	isPreparing = false
	isFlightSessionActive = false
	canDrop = false
	isDescending = false
end

local function restoreCharacterMovement(shouldFreezeMomentum)
	enableLocalControls(true)
	setLandButtonVisible(false)

	if char.Parent then
		setCharacterCanCollide(true)
	end

	if not isHumanoidAlive() then
		return
	end

	if hum.Parent then
		hum.AutoRotate = true
		hum.PlatformStand = false
		hum.Jump = false
		hum.Sit = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		pcall(function()
			hum:Move(zeroVector, true)
		end)
	end

	if hrp.Parent then
		hrp.Anchored = false
		hrp.AssemblyLinearVelocity = zeroVector
		hrp.AssemblyAngularVelocity = zeroVector
	end

	if shouldFreezeMomentum then
		freezeMomentum()
	elseif hum.Parent then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function cleanupCannonSession(context, shouldFreezeMomentum)
	clearCannonSessionState()
	restorePrepLocomotion()
	restoreCharacterMovement(shouldFreezeMomentum)
end

local function cleanupDeadCannonSession(context)
	sessionEndedByDeath = true
	clearCannonSessionState()
	clearPrepLocomotionState()
	enableLocalControls(true)
	setLandButtonVisible(false)

	if char.Parent then
		setCharacterCanCollide(true)
	end
end

local function triggerLanding(reason)
	if not canDrop or not isHumanoidAlive() then
		return
	end

	logCannon(currentLaunchId, "Landing triggered", "reason=" .. tostring(reason))

	canDrop = false
	isDescending = true
	setLandButtonVisible(false)

	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	setCharacterCanCollide(true)

	hrp.AssemblyLinearVelocity = Vector3.new(0, DROP_FORCE, 0)
	hrp.AssemblyAngularVelocity = zeroVector

	logCannon(currentLaunchId, "Landing applied", "dropForce=" .. tostring(DROP_FORCE))
end

styleButton()
restoreCharacterMovement(false)

landButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		triggerLanding("button_input")
	end
end)

local function shouldForceCleanup()
	return controlsDisabled or prepLocomotionLocked or isCannonSessionActive()
end

hum.Died:Connect(function()
	if shouldForceCleanup() then
		logCannon(currentLaunchId, "Humanoid died - forcing cannon cleanup")
		cleanupDeadCannonSession("died")
	end
end)

char.AncestryChanged:Connect(function(_, parent)
	if not parent and shouldForceCleanup() then
		logCannon(currentLaunchId, "Character removed - forcing cannon cleanup")
		if sessionEndedByDeath or not isHumanoidAlive() then
			cleanupDeadCannonSession("character_removed")
		else
			cleanupCannonSession("character_removed", false)
		end
	end
end)

script.AncestryChanged:Connect(function(_, parent)
	if not parent and shouldForceCleanup() then
		logCannon(currentLaunchId, "Script removed - forcing cannon cleanup")
		if sessionEndedByDeath or not isHumanoidAlive() then
			cleanupDeadCannonSession("script_removed")
		else
			cleanupCannonSession("script_removed", false)
		end
	end
end)

landButton.MouseButton1Click:Connect(function()
	triggerLanding("button_click")
end)

Remotes.CannonDropEvent.OnClientEvent:Connect(function(mode, velocity)
	if sessionEndedByDeath and mode ~= "Prepare" then
		logCannon(currentLaunchId, "Ignored cannon event after death cleanup", "mode=" .. tostring(mode))
		return
	end

	if mode == "Prepare" then
		local newSessionToken = beginCannonSession()
		logCannon(
			currentLaunchId,
			"Prepare received",
			"sessionToken=" .. tostring(newSessionToken),
			"isDescending=" .. tostring(isDescending),
			"canDrop=" .. tostring(canDrop)
		)
		disableLocalControls()
		applyPrepLocomotionLock()
		clearLocalMovementIntent()
		setLandButtonVisible(false)
		hum.AutoRotate = false
		hrp.AssemblyAngularVelocity = zeroVector
		forceUpright()
		startPrepareLockLoop(newSessionToken)
		logCannon(currentLaunchId, "Prepare complete", "sessionToken=" .. tostring(newSessionToken))
	elseif mode == "Reset" then
		logCannon(currentLaunchId, "Reset received", "isDescending=" .. tostring(isDescending), "canDrop=" .. tostring(canDrop))
		cleanupCannonSession("reset", false)
		logCannon(currentLaunchId, "Reset complete", "isDescending=" .. tostring(isDescending))
	elseif mode == "Launch" then
		if not isFlightSessionActive then
			logCannon(currentLaunchId, "Launch ignored without active session")
			return
		end

		logCannon(currentLaunchId, "Launch received", "velocity=" .. tostring(velocity), "isDescending=" .. tostring(isDescending))
		isPreparing = false
		isDescending = false
		restorePrepLocomotion()
		enableLocalControls()
		hum.AutoRotate = true
		setCharacterCanCollide(false)
		hrp.AssemblyAngularVelocity = zeroVector
		hrp.AssemblyLinearVelocity = velocity
		canDrop = true
		currentLaunchId += 1
		local thisLaunch = currentLaunchId
		flightSampleToken += 1
		local thisSampleToken = flightSampleToken
		logCannon(thisLaunch, "Launch applied", "isDescending=" .. tostring(isDescending))
		setLandButtonVisible(true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

		task.spawn(function()
			local launchStart = tick()
			while tick() - launchStart <= DEBUG_SAMPLE_DURATION do
				task.wait(DEBUG_SAMPLE_INTERVAL)
				if currentLaunchId ~= thisLaunch or flightSampleToken ~= thisSampleToken then
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
	elseif mode == "Descend" then
		if not isFlightSessionActive then
			logCannon(currentLaunchId, "Descend ignored without active session")
			return
		end

		logCannon(currentLaunchId, "Descend received", "velocity=" .. tostring(velocity), "isDescending=" .. tostring(isDescending))
		canDrop = false
		isDescending = true
		setLandButtonVisible(false)
		hrp.AssemblyLinearVelocity = velocity
	else
		logCannon(currentLaunchId, "Unknown mode received", tostring(mode))
	end
end)

hum.Seated:Connect(function(active, seatPart)
	if isCannonSessionActive() or active then
		logCannon(
			currentLaunchId,
			"Seated changed",
			"active=" .. tostring(active),
			"seatPart=" .. seatPartLabel(seatPart)
		)
	end
end)

hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
	if isCannonSessionActive() then
		logCannon(currentLaunchId, "SeatPart changed", "seatPart=" .. seatPartLabel(hum.SeatPart))
	end
end)

hum.StateChanged:Connect(function(_, newState)
	if sessionEndedByDeath and newState == Enum.HumanoidStateType.Landed then
		logCannon(currentLaunchId, "Ignored landed state after death cleanup")
		return
	end

	if newState == Enum.HumanoidStateType.Landed then
		if not isFlightSessionActive then
			return
		end

		if isDescending then
			logCannon(currentLaunchId, "Landed during descent", "isDescending=" .. tostring(isDescending))
			cleanupCannonSession("landed_descend", true)
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
		cleanupCannonSession("landed", true)
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
