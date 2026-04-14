local Players = game:GetService("Players")
Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = 0
	money.Parent = stats

	local income = Instance.new("IntValue")
	income.Name = "Money/Sec"
	income.Value = 0
	income.Parent = stats

	local rebirth = Instance.new("IntValue")
	rebirth.Name = "Rebirths"
	rebirth.Value = 0
	rebirth.Parent = stats

end)

