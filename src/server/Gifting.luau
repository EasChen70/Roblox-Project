local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Pickup = require(ServerScriptService.Pickup)
local PlayerData = require(ServerScriptService.PlayerData)

local Gifting = {}

local pendingRequestsById = {}
local pendingRequestsByPlayer = {}
local promptConnections = {}
local initialized = false

local function getGiftPromptAttachment(rootPart)
	local attachment = rootPart:FindFirstChild("GiftPromptAttachment")
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	attachment = Instance.new("Attachment")
	attachment.Name = "GiftPromptAttachment"
	attachment.Position = Vector3.new(0, Config.GiftPromptHeight, 0)
	attachment.Parent = rootPart
	return attachment
end

local function getCharacterState(player)
	local character = player and player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, rootPart
end

local function isPlayerGiftReady(player)
	local _, humanoid, rootPart = getCharacterState(player)
	return humanoid ~= nil and humanoid.Health > 0 and rootPart ~= nil
end

local function arePlayersWithinGiftRange(sender, recipient)
	local _, _, senderRoot = getCharacterState(sender)
	local _, _, recipientRoot = getCharacterState(recipient)
	if not senderRoot or not recipientRoot then
		return false
	end

	return (senderRoot.Position - recipientRoot.Position).Magnitude <= Config.GiftRange
end

local function getItemPayload(itemData)
	return {
		name = itemData.name,
		rarity = itemData.rarity,
		level = itemData.level or 1,
		mutation = itemData.mutation or "None",
	}
end

local function buildResolvedPayload(request, role, success, reason)
	local counterpart = if role == "sender" then request.recipient else request.sender
	local item = getItemPayload(request.itemData)

	return {
		kind = "resolved",
		requestId = request.id,
		role = role,
		success = success == true,
		reason = reason,
		counterpartUserId = counterpart and counterpart.UserId or nil,
		counterpartName = counterpart and counterpart.Name or nil,
		item = item,
		itemName = item.name,
		itemRarity = item.rarity,
		itemLevel = item.level,
		itemMutation = item.mutation,
	}
end

local function fireResolvedForRequest(request, success, senderReason, recipientReason)
	if request.sender and request.sender.Parent then
		Remotes.GiftResult:FireClient(
			request.sender,
			buildResolvedPayload(request, "sender", success, senderReason or recipientReason)
		)
	end

	if request.recipient and request.recipient.Parent then
		Remotes.GiftResult:FireClient(
			request.recipient,
			buildResolvedPayload(request, "recipient", success, recipientReason or senderReason)
		)
	end
end

local function fireImmediateSenderFailure(sender, recipient, itemData, reason)
	if not sender or not sender.Parent then
		return
	end

	local request = {
		id = nil,
		sender = sender,
		recipient = recipient,
		itemData = itemData or {
			name = "",
			rarity = "",
			level = 1,
			mutation = "None",
		},
	}

	Remotes.GiftResult:FireClient(sender, buildResolvedPayload(request, "sender", false, reason))
end

local function disconnectPromptConnections(prompt)
	local connections = promptConnections[prompt]
	if not connections then
		return
	end

	for _, connection in pairs(connections) do
		connection:Disconnect()
	end

	promptConnections[prompt] = nil
end

local function clearPendingRequest(request)
	if pendingRequestsById[request.id] ~= request then
		return
	end

	pendingRequestsById[request.id] = nil
	if pendingRequestsByPlayer[request.sender] == request then
		pendingRequestsByPlayer[request.sender] = nil
	end
	if pendingRequestsByPlayer[request.recipient] == request then
		pendingRequestsByPlayer[request.recipient] = nil
	end

	if request.toolDestroyConnection then
		request.toolDestroyConnection:Disconnect()
		request.toolDestroyConnection = nil
	end
end

local function finalizeCancelledRequest(request, senderReason, recipientReason)
	clearPendingRequest(request)
	Pickup.releaseGiftReservation(request.sender, request.tool)
	fireResolvedForRequest(request, false, senderReason, recipientReason)
end

local function getRequestValidationFailure(request)
	if not request.sender or not request.sender.Parent then
		return "sender_cancelled"
	end
	if not request.recipient or not request.recipient.Parent then
		return "recipient_cancelled"
	end
	if pendingRequestsById[request.id] ~= request then
		return "cancelled"
	end
	if not isPlayerGiftReady(request.sender) then
		return "sender_cancelled"
	end
	if not isPlayerGiftReady(request.recipient) then
		return "recipient_cancelled"
	end
	if not request.tool or request.tool.Parent == nil then
		return "sender_cancelled"
	end
	if not arePlayersWithinGiftRange(request.sender, request.recipient) then
		return "too_far"
	end
	if not Pickup.hasInventorySpace(request.recipient) then
		return "recipient_full"
	end

	return nil
end

local function cancelRequest(request, reason)
	if pendingRequestsById[request.id] ~= request then
		return
	end

	if reason == "recipient_cancelled" then
		finalizeCancelledRequest(request, "recipient_cancelled", "cancelled")
	elseif reason == "sender_cancelled" then
		finalizeCancelledRequest(request, "cancelled", "sender_cancelled")
	elseif reason == "recipient_full" then
		finalizeCancelledRequest(request, "recipient_full", "recipient_full")
	elseif reason == "too_far" then
		finalizeCancelledRequest(request, "too_far", "too_far")
	elseif reason == "declined" then
		finalizeCancelledRequest(request, "declined", "declined")
	elseif reason == "timed_out" then
		finalizeCancelledRequest(request, "timed_out", "timed_out")
	else
		finalizeCancelledRequest(request, "cancelled", "cancelled")
	end
end

local function resolveAcceptedRequest(request)
	if pendingRequestsById[request.id] ~= request then
		return
	end

	local validationFailure = getRequestValidationFailure(request)
	if validationFailure then
		cancelRequest(request, validationFailure)
		return
	end

	if request.toolDestroyConnection then
		request.toolDestroyConnection:Disconnect()
		request.toolDestroyConnection = nil
	end

	local itemData, consumeReason = Pickup.consumeReservedGiftTool(request.sender, request.tool)
	if consumeReason ~= "ok" or not itemData then
		cancelRequest(request, consumeReason == "tool_missing" and "sender_cancelled" or "cancelled")
		return
	end

	local granted = Pickup.giveItem(
		request.recipient,
		itemData.name,
		itemData.rarity,
		itemData.baseIncome,
		itemData.level,
		itemData.mutation
	)

	if not granted then
		Pickup.giveItem(
			request.sender,
			itemData.name,
			itemData.rarity,
			itemData.baseIncome,
			itemData.level,
			itemData.mutation
		)
		cancelRequest(request, "recipient_full")
		return
	end

	request.itemData = itemData
	clearPendingRequest(request)
	PlayerData.requestSave(request.sender)
	PlayerData.requestSave(request.recipient)
	fireResolvedForRequest(request, true, "accepted", "accepted")
end

local function createPendingRequest(sender, recipient, tool, itemData)
	local request = {
		id = HttpService:GenerateGUID(false),
		sender = sender,
		recipient = recipient,
		tool = tool,
		itemData = itemData,
	}

	pendingRequestsById[request.id] = request
	pendingRequestsByPlayer[sender] = request
	pendingRequestsByPlayer[recipient] = request

	request.toolDestroyConnection = tool.Destroying:Connect(function()
		cancelRequest(request, "sender_cancelled")
	end)

	task.delay(Config.GiftRequestTimeout, function()
		if pendingRequestsById[request.id] == request then
			cancelRequest(request, "timed_out")
		end
	end)

	return request
end

local function handleGiftPromptTriggered(recipient, sender)
	if sender == recipient then
		return
	end
	if not sender or not recipient then
		return
	end
	if pendingRequestsByPlayer[sender] then
		fireImmediateSenderFailure(sender, recipient, nil, "sender_busy")
		return
	end
	if pendingRequestsByPlayer[recipient] then
		fireImmediateSenderFailure(sender, recipient, nil, "recipient_busy")
		return
	end
	if not isPlayerGiftReady(sender) or not isPlayerGiftReady(recipient) then
		fireImmediateSenderFailure(sender, recipient, nil, "too_far")
		return
	end
	if not arePlayersWithinGiftRange(sender, recipient) then
		fireImmediateSenderFailure(sender, recipient, nil, "too_far")
		return
	end
	if not Pickup.hasInventorySpace(recipient) then
		fireImmediateSenderFailure(sender, recipient, nil, "recipient_full")
		return
	end

	local tool, itemData, reserveReason = Pickup.reserveEquippedToolForGift(sender)
	if not tool or not itemData then
		fireImmediateSenderFailure(sender, recipient, nil, reserveReason or "no_equipped_item")
		return
	end

	local request = createPendingRequest(sender, recipient, tool, itemData)
	local item = getItemPayload(itemData)

	Remotes.GiftResult:FireClient(sender, {
		kind = "outgoingPending",
		requestId = request.id,
		targetUserId = recipient.UserId,
		targetName = recipient.Name,
		item = item,
		itemName = item.name,
		itemRarity = item.rarity,
		itemLevel = item.level,
		itemMutation = item.mutation,
	})

	Remotes.GiftResult:FireClient(recipient, {
		kind = "incomingRequest",
		requestId = request.id,
		senderUserId = sender.UserId,
		senderName = sender.Name,
		timeoutSeconds = Config.GiftRequestTimeout,
		item = item,
		itemName = item.name,
		itemRarity = item.rarity,
		itemLevel = item.level,
		itemMutation = item.mutation,
	})
end

local function ensureGiftPrompt(player)
	local _, _, rootPart = getCharacterState(player)
	if not rootPart then
		return
	end

	local attachment = getGiftPromptAttachment(rootPart)
	local prompt = attachment:FindFirstChild("GiftPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GiftPrompt"
		prompt.Parent = attachment
	end

	prompt.ActionText = "Gift"
	prompt.ObjectText = player.Name
	prompt.HoldDuration = Config.GiftHoldDuration
	prompt.MaxActivationDistance = Config.GiftRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("GiftPrompt", true)
	prompt:SetAttribute("GiftTargetUserId", player.UserId)
	prompt:SetAttribute("GiftTargetName", player.Name)

	if promptConnections[prompt] then
		return
	end

	promptConnections[prompt] = {}
	promptConnections[prompt].triggered = prompt.Triggered:Connect(function(triggerPlayer)
		handleGiftPromptTriggered(player, triggerPlayer)
	end)
	promptConnections[prompt].destroying = prompt.Destroying:Connect(function()
		disconnectPromptConnections(prompt)
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			if player.Character == character and character.Parent then
				ensureGiftPrompt(player)
			end
		end)
	end)

	player.CharacterRemoving:Connect(function()
		local request = pendingRequestsByPlayer[player]
		if not request then
			return
		end

		if request.sender == player then
			cancelRequest(request, "sender_cancelled")
		else
			cancelRequest(request, "recipient_cancelled")
		end
	end)

	if player.Character then
		task.spawn(function()
			player.Character:WaitForChild("HumanoidRootPart", 10)
			if player.Character and player.Character.Parent then
				ensureGiftPrompt(player)
			end
		end)
	end
end

function Gifting.cleanupPlayer(player)
	local request = pendingRequestsByPlayer[player]
	if not request then
		return
	end

	if request.sender == player then
		cancelRequest(request, "sender_cancelled")
	else
		cancelRequest(request, "recipient_cancelled")
	end
end

function Gifting.init()
	if initialized then
		return
	end
	initialized = true

	Remotes.GiftDecision.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" then
			return
		end

		local requestId = payload.requestId
		local accepted = payload.accepted == true
		if type(requestId) ~= "string" then
			return
		end

		local request = pendingRequestsById[requestId]
		if not request or request.recipient ~= player then
			return
		end

		if not accepted then
			cancelRequest(request, "declined")
			return
		end

		resolveAcceptedRequest(request)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Gifting.cleanupPlayer(player)
	end)

	Players.PlayerAdded:Connect(bindPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return Gifting
