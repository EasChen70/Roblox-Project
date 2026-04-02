-- shared/Config.luau

local Config = {
	-- Base
	MaxSlots = 12, -- max brainrot slots per base
	MaxPlayers = 5, -- max players per server
	IncomeTickRate = 1, -- seconds between each cash accumulate per brainrot in slot

	-- Spawner
	SpawnInterval = 5, -- seconds between new brainrot spawns in area
	MaxSpawns = 8, -- max brainrot spawns

	-- TODO: Slap
	-- SlapCooldown = 1,
	-- SlapForce = 50,
	-- SlapRange = 10,

	-- TODO: Cannon
	-- CannonTiers = {
	--     { power = 50, cost = 0 },
	--     { power = 100, cost = 500 },
	--     { power = 200, cost = 2000 },
	-- }
}

return Config