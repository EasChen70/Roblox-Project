-- server/Base.luau

local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Config)
local Remotes = require(game.ReplicatedStorage.Remotes)

local Base = {}

local bases = game.Workspace.Map.Bases
local claimedBases = {}

function Base.claimBase(player)
	for _, base in bases:GetChildren() do
		local taken = false
		for _, claimedBase in claimedBases do
			if claimedBase == base then
				taken = true
				break
			end
		end

		if not taken then
			claimedBases[player] = base
			print(player.Name, "claimed", base.Name)
			Remotes.BaseAssigned:FireClient(player, base.Name)
			return base
		end
	end

	warn("No bases available for", player.Name)
	return nil
end

function Base.releaseBase(player)
	if claimedBases[player] then
		print(player.Name, "released", claimedBases[player].Name)
		claimedBases[player] = nil
	end
end

function Base.getOwner(baseModel)
	for player, base in claimedBases do
		if base == baseModel then
			return player
		end
	end
	return nil
end

Players.PlayerAdded:Connect(function(player)
	Base.claimBase(player)
end)

Players.PlayerRemoving:Connect(function(player)
	Base.releaseBase(player)
end)

return Base