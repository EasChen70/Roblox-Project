local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Config)
local Base = require(game.ServerScriptService.Base)
local Remotes = require(game.ReplicatedStorage.Remotes)
local Util = require(game.ReplicatedStorage.Util)

local Income = {}

local onDataChangedCallback = nil

function Income.onDataChanged(cb)
	onDataChangedCallback = cb
end

local bases = game.Workspace.Map.Bases

local function getPlacedBrainrot(slot)
	for _, child in slot:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Placed") then
			return child
		end
	end
	return nil
end

local function createBillboard(collectButton)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "CashDisplay"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.Parent = collectButton

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 1

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = label

	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.Text = "$0"
	label.Rotation = 90
	label.Parent = surface

	return surface
end

local function updateBillboard(collectButton, amount)
	local billboard = collectButton:FindFirstChild("CashDisplay")
	if not billboard then return end
	local label = billboard:FindFirstChild("Amount")
	if not label then return end
	label.Text = Util.formatMoney(amount)
end

function Income.setup()
	for _, base in bases:GetChildren() do
		local slots = base:FindFirstChild("Slots")
		if not slots then continue end

		for i = 1, Config.MaxSlots do
			local slot = slots:FindFirstChild("Slot" .. i)
			if not slot then continue end

			slot:SetAttribute("AccumulatedCash", 0)

			local collectButton = slot:FindFirstChild("CollectButton")
			if not collectButton then continue end

			if not collectButton:FindFirstChild("CashDisplay") then
				createBillboard(collectButton)
			end

			collectButton.Touched:Connect(function(hit)
				local character = hit.Parent
				local player = Players:GetPlayerFromCharacter(character)
				if not player then return end
				if Base.getOwner(base) ~= player then return end

				local accumulated = slot:GetAttribute("AccumulatedCash") or 0
				if accumulated <= 0 then return end

				local stats = player:FindFirstChild("leaderstats")
				if not stats then return end

				local money = stats:FindFirstChild("Money")
				if not money then return end

				money.Value += accumulated
				slot:SetAttribute("AccumulatedCash", 0)
				updateBillboard(collectButton, 0)

				Remotes.CollectSlot:FireClient(player)

				if onDataChangedCallback then
					onDataChangedCallback(player)
				end
			end)
		end
	end
end

function Income.start()
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTickRate)

			for _, base in bases:GetChildren() do
				local owner = Base.getOwner(base)
				local totalIncome = 0

				local slots = base:FindFirstChild("Slots")
				if not slots then continue end

				for i = 1, Config.MaxSlots do
					local slot = slots:FindFirstChild("Slot" .. i)
					if not slot then continue end

					local brainrot = getPlacedBrainrot(slot)
					if not brainrot then continue end

					local incomePerSec = brainrot:GetAttribute("IncomePerSec") or 0
					totalIncome += incomePerSec

					local current = slot:GetAttribute("AccumulatedCash") or 0
					slot:SetAttribute("AccumulatedCash", current + incomePerSec)

					local collectButton = slot:FindFirstChild("CollectButton")
					if collectButton then
						updateBillboard(collectButton, current + incomePerSec)
					end
				end

				if owner then
					local stats = owner:FindFirstChild("leaderstats")
					if stats then
						local incomeStat = stats:FindFirstChild("Money/Sec")
						if incomeStat then
							incomeStat.Value = totalIncome
						end
					end

					Base.updateSignIncome(base, Util.formatMoney(totalIncome) .. "/s")
				end
			end
		end
	end)
end

return Income