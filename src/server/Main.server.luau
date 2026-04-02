-- Main.server.luau (testing)

local Config = require(game.ReplicatedStorage.Config)
local Remotes = require(game.ReplicatedStorage.Remotes)

-- Config tests
print("=== CONFIG TESTS ===")
print("MaxSlots:", Config.MaxSlots, Config.MaxSlots == 12 and "PASS" or "FAIL")
print("MaxPlayers:", Config.MaxPlayers, Config.MaxPlayers == 5 and "PASS" or "FAIL")
print("IncomeTickRate:", Config.IncomeTickRate, Config.IncomeTickRate == 1 and "PASS" or "FAIL")
print("SpawnInterval:", Config.SpawnInterval, Config.SpawnInterval == 5 and "PASS" or "FAIL")
print("MaxSpawns:", Config.MaxSpawns, Config.MaxSpawns == 8 and "PASS" or "FAIL")

-- Remote tests
print("=== REMOTE TESTS ===")
print("ClaimBase:", Remotes.ClaimBase and "PASS" or "FAIL")
print("BaseAssigned:", Remotes.BaseAssigned and "PASS" or "FAIL")
print("CollectSlot:", Remotes.CollectSlot and "PASS" or "FAIL")
print("UpdateCash:", Remotes.UpdateCash and "PASS" or "FAIL")
print("GrabBrainrot:", Remotes.GrabBrainrot and "PASS" or "FAIL")
print("PlaceBrainrot:", Remotes.PlaceBrainrot and "PASS" or "FAIL")

-- Verify remotes folder exists in ReplicatedStorage
local folder = game.ReplicatedStorage:FindFirstChild("RemoteEvents")
print("=== FOLDER TEST ===")
print("Remotes folder exists:", folder and "PASS" or "FAIL")
print("Remote count:", folder and #folder:GetChildren() or 0, folder and #folder:GetChildren() == 6 and "PASS" or "FAIL")