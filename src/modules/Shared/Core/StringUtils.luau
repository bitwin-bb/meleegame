--!strict
local StringUtils = {}

function StringUtils.Trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

function StringUtils.Sanitize(valueRaw: any, fallback: string?): string?
	local value = StringUtils.Trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

function StringUtils.CompactToken(valueRaw: any): string
	local value = StringUtils.Trim(valueRaw)
	if value == "" then
		return ""
	end
	return string.lower(string.gsub(value, "[%s_%-%.]+", ""))
end

StringUtils.trim = StringUtils.Trim
StringUtils.sanitize = StringUtils.Sanitize
StringUtils.compactToken = StringUtils.CompactToken

return StringUtils
