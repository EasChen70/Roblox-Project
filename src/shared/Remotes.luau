-- shared/Remotes.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local remoteNames = { "BaseAssigned", "CollectSlot", "TeleportHomeEvent", 
					  "TeleportRequest", "UpgradeCannon", "GrabStateChanged", "DropBrainrot", "UpgradeSound",}

if RunService:IsServer() then
	-- Server creates the folder and remotes
	local folder = Instance.new("Folder")
	folder.Name = "RemoteEvents"
	folder.Parent = ReplicatedStorage

	for _, name in remoteNames do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		Remotes[name] = remote
	end
else
	-- Client waits for them to exist
	local folder = ReplicatedStorage:WaitForChild("RemoteEvents")

	for _, name in remoteNames do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes