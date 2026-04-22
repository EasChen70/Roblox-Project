local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local teleportEvent = Remotes.TeleportRequest 

local TARGET_POSITION = Vector3.new(1435, 25, -162) 

teleportEvent.OnServerEvent:Connect(function(player)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChild("Humanoid")

    if hrp and humanoid then
        -- 1. KILL ALL MOMENTUM
        -- This stops the "sliding" or "flying" effect instantly
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        -- 2. RESET HUMANOID STATE
        -- If they were launched, they might be in 'PlatformStand' or 'Ragdoll'
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

        -- 3. DEFINE POSITION AND ROTATION
        local targetCFrame = CFrame.new(TARGET_POSITION)
        local rotation = CFrame.Angles(0, math.rad(90), 0)

        -- 4. TELEPORT
        hrp.CFrame = targetCFrame * rotation

        -- 5. SAFETY DOUBLE-CHECK
        -- Sometimes physics updates a frame late, so we clear velocity again
        task.defer(function()
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
        end)
    end
end)