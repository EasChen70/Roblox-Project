-- shared/Util.luau
local Util = {}

function Util.formatMoney(amount)
	local tiers = {
		{1e12, "t"},
		{1e9, "b"},
		{1e6, "m"},
		{1e3, "k"},
	}
	for _, tier in tiers do
		if amount >= tier[1] then
			return "$" .. string.format("%.1f", amount / tier[1]) .. tier[2]
		end
	end
	return "$" .. math.floor(amount)
end

return Util