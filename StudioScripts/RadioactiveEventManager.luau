-- [[UPDATED: Radioactive Event Manager (With Rotated & Lowered Billboard)]] --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Config = require(ReplicatedStorage.Config)

local eventActiveValue = Instance.new("BoolValue")
eventActiveValue.Name = "IsRadioactiveEventActive"
eventActiveValue.Value = false
eventActiveValue.Parent = ReplicatedStorage

local radioactiveAtmosphere = Instance.new("Atmosphere")
radioactiveAtmosphere.Color = Color3.fromRGB(0, 255, 0)
radioactiveAtmosphere.Decay = Color3.fromRGB(0, 100, 0)
radioactiveAtmosphere.Haze = 3
radioactiveAtmosphere.Density = 0.35

-- [[CHANGED: Auto-generate the Billboard (Rotated and Lowered)]] --
local billboardPart = Instance.new("Part")
billboardPart.Name = "RadioactiveTimer"
billboardPart.Size = Vector3.new(100, 75, 1) 

-- ROTATED: Added CFrame.Angles to rotate it 90 degrees on the Y-axis
billboardPart.CFrame = CFrame.new(1413, 34.092, -185.601) * CFrame.Angles(0, math.rad(90), 0)

billboardPart.Anchored = true 
billboardPart.CanCollide = false 
billboardPart.Transparency = 1 
billboardPart.Parent = workspace

-- [[Double-Sided GUI]] --
local surfaceGui = Instance.new("SurfaceGui")
surfaceGui.Face = Enum.NormalId.Front 
surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
surfaceGui.PixelsPerStud = 25
surfaceGui.Parent = billboardPart

local textLabel = Instance.new("TextLabel")
textLabel.Name = "EventText" 
textLabel.Size = UDim2.new(1, 0, 1, 0) 
textLabel.BackgroundTransparency = 1 
textLabel.TextColor3 = Color3.fromRGB(255, 0, 0) 
textLabel.TextStrokeTransparency = 0 
textLabel.TextScaled = true
textLabel.Font = Enum.Font.Creepster 
textLabel.Parent = surfaceGui

-- Clone the exact same UI onto the back face!
local backGui = surfaceGui:Clone()
backGui.Face = Enum.NormalId.Back
backGui.Parent = billboardPart

-- Helper function to turn raw seconds into a clean "MM:SS" digital clock format
local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

while true do
	for timeLeft = Config.RadioactiveEventCooldown, 1, -1 do
		-- [[CHANGED: Added ☢️ Emoji]] --
		local displayText = "☢️ NEXT RADIOACTIVE EVENT ☢️\n" .. formatTime(timeLeft)
		surfaceGui.EventText.Text = displayText
		backGui.EventText.Text = displayText
		task.wait(1) 
	end

	eventActiveValue.Value = true
	radioactiveAtmosphere.Parent = Lighting

	for timeLeft = Config.RadioactiveEventDuration, 1, -1 do
		-- [[CHANGED: Added ☢️ Emoji]] --
		local displayText = "☢️ RADIOACTIVE EVENT ENDS IN ☢️\n" .. formatTime(timeLeft)
		surfaceGui.EventText.Text = displayText
		backGui.EventText.Text = displayText
		task.wait(1)
	end

	eventActiveValue.Value = false
	radioactiveAtmosphere.Parent = nil
end