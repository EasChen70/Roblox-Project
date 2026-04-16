local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local Base = require(game:GetService("ServerScriptService").Base)

Remotes.TeleportHomeEvent.OnServerEvent:Connect(function(player)
	local base = Base.getPlayerBase(player)
	if not base then return end

	local platform = base:FindFirstChild("Platform")
	if not platform then return end

	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	root.CFrame = CFrame.new(platform.Position + Vector3.new(0, 5, 0))
end)