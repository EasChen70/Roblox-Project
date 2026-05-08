local BaseIdentity = {}

local function normalizeInteger(value)
	if type(value) == "number" then
		if value == math.floor(value) then
			return value
		end
		return nil
	end

	if type(value) == "string" then
		local parsed = tonumber(value)
		if parsed and parsed == math.floor(parsed) then
			return parsed
		end
	end

	return nil
end

function BaseIdentity.normalizeBaseId(value)
	return normalizeInteger(value)
end

function BaseIdentity.getNameSuffixId(name)
	local suffix = type(name) == "string" and string.match(name, "(%d+)$") or nil
	return suffix and tonumber(suffix) or nil
end

function BaseIdentity.getConfiguredBaseId(base)
	local rawValue = base and base:GetAttribute("BaseId") or nil
	local configuredId = normalizeInteger(rawValue)
	if configuredId ~= nil then
		return configuredId
	end

	if rawValue == nil then
		return nil, "missing"
	end

	return nil, "invalid"
end

function BaseIdentity.getResolvedBaseId(base)
	local configuredId = BaseIdentity.getConfiguredBaseId(base)
	if configuredId ~= nil then
		return configuredId
	end

	return BaseIdentity.getNameSuffixId(base and base.Name or nil)
end

function BaseIdentity.getSortKey(base)
	local configuredId, issue = BaseIdentity.getConfiguredBaseId(base)
	local fallbackId = BaseIdentity.getNameSuffixId(base and base.Name or nil)
	local resolvedId = configuredId or fallbackId

	return {
		configuredId = configuredId,
		fallbackId = fallbackId,
		resolvedId = resolvedId,
		issue = issue,
		name = base and base.Name or "",
		finalOrder = resolvedId ~= nil and resolvedId or math.huge,
	}
end

function BaseIdentity.compareBases(a, b)
	local aKey = BaseIdentity.getSortKey(a)
	local bKey = BaseIdentity.getSortKey(b)

	if aKey.finalOrder ~= bKey.finalOrder then
		return aKey.finalOrder < bKey.finalOrder
	end

	return aKey.name < bKey.name
end

function BaseIdentity.getSortedBases(container)
	local sortedBases = container:GetChildren()
	table.sort(sortedBases, BaseIdentity.compareBases)
	return sortedBases
end

function BaseIdentity.findBaseById(container, baseId)
	local normalizedBaseId = normalizeInteger(baseId)
	if not container or normalizedBaseId == nil then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if BaseIdentity.getResolvedBaseId(child) == normalizedBaseId then
			return child
		end
	end

	return nil
end

return BaseIdentity
