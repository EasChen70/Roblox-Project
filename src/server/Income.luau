-- server/Income.luau

local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.Config)
local Base = require(game.ServerScriptService.Base)

local Income = {}

local bases = game.Workspace.Map.Bases

local function formatMoney(amount)
	if amount < 1000 then
		return "$" .. math.floor(amount)
	elseif amount < 1000000 then
		local k = amount / 1000
		if k >= 100 then
			return "$" .. math.floor(k) .. "k"
		elseif k >= 10 then
			return "$" .. string.format("%.1f", k) .. "k"
		else
			return "$" .. string.format("%.1f", k) .. "k"
		end
	elseif amount < 1000000000 then
		local m = amount / 1000000
		if m >= 100 then
			return "$" .. math.floor(m) .. "m"
		else
			return "$" .. string.format("%.1f", m) .. "m"
		end
	elseif amount < 1000000000000 then
		local b = amount / 1000000000
		if b >= 100 then
			return "$" .. math.floor(b) .. "b"
		else
			return "$" .. string.format("%.1f", b) .. "b"
		end
	else
		local t = amount / 1000000000000
		if t >= 100 then
			return "$" .. math.floor(t) .. "t"
		else
			return "$" .. string.format("%.1f", t) .. "t"
		end
	end
end

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
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 1  
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 3
    stroke.Parent = label
	label.TextScaled = true
	label.Font = Enum.Font.LuckiestGuy
	label.Text = "$0"
	label.Parent = surface
    label.Rotation = 90

	return surface
end

local function updateBillboard(collectButton, amount)
	local billboard = collectButton:FindFirstChild("CashDisplay")
	if not billboard then return end
	local label = billboard:FindFirstChild("Amount")
	if not label then return end
	label.Text = formatMoney(amount)
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

			createBillboard(collectButton)

			collectButton.Touched:Connect(function(hit)
				local character = hit.Parent
				if not character then return end

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
				local audio = game.Workspace.Map:FindFirstChild("Audio")
                if audio then
                    local cashSound = audio:FindFirstChild("cashEffect")
                    if cashSound then
                        local sfx = cashSound:Clone()
                        sfx.Parent = collectButton
                        sfx:Play()
                        sfx.Ended:Once(function()
                            sfx:Destroy()
                        end)
                    end
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
				end
			end
		end
	end)
end

return Income