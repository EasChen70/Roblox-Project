local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local FunnelAnalytics = {}

local ONBOARDING_START_STEP = 1

local STEP_NAMES = {
	[1] = "Tutorial Started",
	[2] = "Free Cannon Upgrade",
	[3] = "First Cannon Launch",
	[4] = "First Brainrot Grabbed",
	[5] = "Returned To Base",
	[6] = "First Brainrot Placed",
	[7] = "First Cash Collected",
	[8] = "First Brainrot Upgrade",
}

local TUTORIAL_STEP_TO_FUNNEL_STEP = {
	freeCannonUpgrade = 2,
	useLaunchCannon = 3,
	grabBrainrot = 4,
	returnToBase = 5,
	placeBrainrot = 6,
	collectCash = 7,
	upgradeBrainrot = 8,
}

local loggedStepsByPlayer = {}

local function shouldLogAnalytics()
	return not RunService:IsStudio()
end

local function getPlayerState(player)
	local state = loggedStepsByPlayer[player]
	if state then
		return state
	end

	state = {}
	loggedStepsByPlayer[player] = state
	return state
end

local function tryLogStep(player, stepNumber)
	if not player or not shouldLogAnalytics() then
		return
	end

	local stepName = STEP_NAMES[stepNumber]
	if not stepName then
		return
	end

	local playerState = getPlayerState(player)
	if playerState[stepNumber] then
		return
	end

	-- Roblox onboarding funnels already dedupe server-side. This extra guard is
	-- kept for rate-limit hygiene and to avoid repeated analytics attempts.
	playerState[stepNumber] = true

	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName)
	end)
end

function FunnelAnalytics.logOnboardingStart(player)
	tryLogStep(player, ONBOARDING_START_STEP)
end

function FunnelAnalytics.logTutorialStep(player, tutorialStepId)
	local stepNumber = TUTORIAL_STEP_TO_FUNNEL_STEP[tutorialStepId]
	if not stepNumber then
		return
	end

	tryLogStep(player, stepNumber)
end

function FunnelAnalytics.clearPlayer(player)
	loggedStepsByPlayer[player] = nil
end

return FunnelAnalytics
