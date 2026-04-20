local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local teleportEvent = Remotes.TeleportRequest  -- We already have a Remotes.luau so removed TeleportRequest

local TARGET_POSITION = Vector3.new(1435, 25, -162) 

teleportEvent.OnServerEvent:Connect(function(player)
    local character = player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        -- 1. Define the position
        local targetCFrame = CFrame.new(TARGET_POSITION)

        -- 2. Define the rotation (90 degrees left)
        -- We use math.rad() because CFrame angles use Radians, not Degrees
        local rotation = CFrame.Angles(0, math.rad(90), 0)

        -- 3. Combine them and teleport
        character.HumanoidRootPart.CFrame = targetCFrame * rotation
    end
end)