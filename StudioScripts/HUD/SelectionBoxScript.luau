local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer

-- CONFIGURATION
local MAX_DISTANCE = 70 
-- List all the folder names you want to scan
local FOLDER_NAMES = {
	"SpawnZones", 
	"SpawnZonesRare", 
	"SpawnZonesEpic", 
	"SpawnZonesLegendary", 
	"SpawnZonesMythic", 
	"SpawnZonesSecret", 
	"SpawnZonesDivine"
}

local allBoxes = {}

-- Function to find boxes across all rarity folders
local function refreshBoxes()
	allBoxes = {}
	for _, folderName in pairs(FOLDER_NAMES) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, descendant in pairs(folder:GetDescendants()) do
				if descendant:IsA("SelectionBox") then
					-- Auto-Adornee: If it's not set, point it to the parent (the Floor)
					if not descendant.Adornee then
						descendant.Adornee = descendant.Parent
					end
					table.insert(allBoxes, descendant)
				end
			end
		else
			warn("Folder not found in Workspace: " .. folderName)
		end
	end
end

-- Initial scan
refreshBoxes()

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	if hrp then
		local playerPos = hrp.Position

		for _, box in pairs(allBoxes) do
			if box.Adornee and box.Adornee:IsA("BasePart") then
				local distance = (playerPos - box.Adornee.Position).Magnitude

				-- Toggle visibility based on distance
				if distance <= MAX_DISTANCE then
					box.Visible = true
				else
					box.Visible = false
				end
			end
		end
	end
end)