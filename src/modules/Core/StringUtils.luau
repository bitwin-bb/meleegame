--!strict
local StringUtils = {}

function StringUtils.trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

function StringUtils.sanitize(valueRaw: any, fallback: string?): string?
	local value = StringUtils.trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

function StringUtils.compactToken(valueRaw: any): string
	local value = StringUtils.trim(valueRaw)
	if value == "" then
		return ""
	end
	return string.lower(string.gsub(value, "[%s_%-%.]+", ""))
end

return StringUtils
