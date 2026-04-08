-- Main.client.luau (testing)

local Remotes = require(game.ReplicatedStorage.Remotes)

print("=== CLIENT REMOTE TESTS ===")
print("ClaimBase:", Remotes.ClaimBase and "PASS" or "FAIL")
print("CollectSlot:", Remotes.CollectSlot and "PASS" or "FAIL")
print("UpdateCash:", Remotes.UpdateCash and "PASS" or "FAIL")
