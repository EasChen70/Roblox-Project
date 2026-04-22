local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local Base = require(game:GetService("ServerScriptService").Base)

Remotes.TeleportHomeEvent.OnServerEvent:Connect(function(player)
    local base = Base.getPlayerBase(player)
    if not base then return end

    local platform = base:FindFirstChild("Platform")
    if not platform then return end

    local character = player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if root and hum then
        -- 1. KILL ALL MOMENTUM
        -- Resets any speed from cannons or falling
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        -- 2. RESET STATE
        -- Ensures the player isn't stuck in a falling or ragdoll state
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)

        -- 3. TELEPORT
        -- Positioned 5 studs above the platform to avoid clipping
        root.CFrame = CFrame.new(platform.Position + Vector3.new(0, 5, 0))

        -- 4. PHYSICS SAFETY
        -- Defer a secondary velocity clear to handle any late physics updates
        task.defer(function()
            if root and root.Parent then
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
        end)
    end
end)