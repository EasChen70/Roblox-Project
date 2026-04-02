-- shared/Remotes.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local remoteNames = {
	"ClaimBase",       -- client → server: request a base on join
	"BaseAssigned",    -- server → client: tells client which base they got
	"CollectSlot",     -- client → server: player clicked a CollectButton
	"UpdateCash",      -- server → client: send new cash total to display
	"GrabBrainrot",    -- client → server: player touched a brainrot in common area
	"PlaceBrainrot",   -- client → server: player places brainrot on a slot
}

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