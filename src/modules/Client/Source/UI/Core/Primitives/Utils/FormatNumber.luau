local require = require(script.Parent.loader).load(script)

local function formatNumber(valueRaw: any): string
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else 0
	local absolute = math.abs(math.floor(value))
	local raw = tostring(absolute)
	local remainder = #raw % 3
	local groups = {}

	if remainder > 0 then
		table.insert(groups, string.sub(raw, 1, remainder))
	end

	local index = remainder + 1
	while index <= #raw do
		table.insert(groups, string.sub(raw, index, index + 2))
		index += 3
	end

	local formatted = table.concat(groups, ",")
	if value < 0 then
		return "-" .. formatted
	end
	return formatted
end

return formatNumber
