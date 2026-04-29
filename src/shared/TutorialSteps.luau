local TutorialSteps = {}

TutorialSteps.ORDER = {
	"freeCannonUpgrade",
	"useLaunchCannon",
	"grabBrainrot",
	"returnToBase",
	"placeBrainrot",
	"collectCash",
	"upgradeBrainrot",
}

TutorialSteps.TAGS = {
	CannonShop = "Tutorial_CannonShop",
	LaunchCannon = "Tutorial_LaunchCannon",
	GrabTarget = "Tutorial_GrabTarget",
	ReturnCannon = "Tutorial_ReturnCannon",
	BrainrotSlot = "Tutorial_BrainrotSlot",
	CollectButton = "Tutorial_CollectButton",
	UpgradeBillboard = "Tutorial_UpgradeBillboard",
}

TutorialSteps.COMPLETE_MESSAGE = "Good Job! Have Fun :)"
TutorialSteps.COMPLETE_DISPLAY_TIME = 3

TutorialSteps.STEPS = {
	freeCannonUpgrade = {
		id = "freeCannonUpgrade",
		prompt = "Upgrade your cannon!",
		targetTag = TutorialSteps.TAGS.CannonShop,
		completionFlag = "freeCannonUpgrade",
	},
	useLaunchCannon = {
		id = "useLaunchCannon",
		prompt = "Use the cannon!",
		targetTag = TutorialSteps.TAGS.LaunchCannon,
		completionFlag = "useLaunchCannon",
	},
	grabBrainrot = {
		id = "grabBrainrot",
		prompt = "Grab a brainrot!",
		targetTag = TutorialSteps.TAGS.GrabTarget,
		completionFlag = "grabBrainrot",
	},
	returnToBase = {
		id = "returnToBase",
		prompt = "Launch to base!",
		targetTag = TutorialSteps.TAGS.ReturnCannon,
		completionFlag = "returnToBase",
	},
	placeBrainrot = {
		id = "placeBrainrot",
		prompt = "Place it on a slot!",
		targetTag = TutorialSteps.TAGS.BrainrotSlot,
		completionFlag = "placeBrainrot",
	},
	collectCash = {
		id = "collectCash",
		prompt = "Collect your cash!",
		targetTag = TutorialSteps.TAGS.CollectButton,
		completionFlag = "collectCash",
	},
	upgradeBrainrot = {
		id = "upgradeBrainrot",
		prompt = "Upgrade your brainrot!",
		targetTag = TutorialSteps.TAGS.UpgradeBillboard,
		completionFlag = "upgradeBrainrot",
	},
}

TutorialSteps.LIST = {}
for _, stepId in ipairs(TutorialSteps.ORDER) do
	table.insert(TutorialSteps.LIST, TutorialSteps.STEPS[stepId])
end

return TutorialSteps
