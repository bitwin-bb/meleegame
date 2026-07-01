local require = require(script.Parent.loader).load(script)

local StringUtils = {}

function StringUtils.Trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

function StringUtils.Coerce(valueRaw: any, fallback: string?): string?
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
	local normalized = string.gsub(value, "[%s_%-%.]+", "")
	return string.lower(normalized)
end
return StringUtils
