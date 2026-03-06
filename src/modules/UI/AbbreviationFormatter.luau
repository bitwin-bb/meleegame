--!strict

local AbbreviationFormatter = {}

export type AbbreviationRule = {
	suffix: string,
	threshold: number,
	divisor: number,
	precision: number,
}

export type NumberFormatOptions = {
	precision: number?,
	trimTrailingZeros: boolean?,
	minThreshold: number?,
	forceSign: boolean?,
}

local DEFAULT_RULES: { AbbreviationRule } = {
	{ suffix = "T", threshold = 1e12, divisor = 1e12, precision = 2 },
	{ suffix = "B", threshold = 1e9, divisor = 1e9, precision = 2 },
	{ suffix = "M", threshold = 1e6, divisor = 1e6, precision = 2 },
	{ suffix = "K", threshold = 1e3, divisor = 1e3, precision = 1 },
}

local function normalizePrecision(precisionRaw: any, fallback: number): number
	local precision = if typeof(precisionRaw) == "number" then math.floor(precisionRaw) else fallback
	if precision < 0 then
		return 0
	end
	if precision > 8 then
		return 8
	end
	return precision
end

local function roundTo(value: number, precision: number): number
	local multiplier = 10 ^ precision
	if value >= 0 then
		return math.floor(value * multiplier + 0.5) / multiplier
	end
	return math.ceil(value * multiplier - 0.5) / multiplier
end

local function trimZeros(text: string): string
	if not string.find(text, ".", 1, true) then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function formatFixed(value: number, precision: number, trimTrailing: boolean): string
	local rounded = roundTo(value, precision)
	local raw = string.format("%.*f", precision, rounded)
	if trimTrailing then
		return trimZeros(raw)
	end
	return raw
end

local function signPrefix(value: number, forceSign: boolean): string
	if value < 0 then
		return "-"
	end
	if forceSign and value > 0 then
		return "+"
	end
	return ""
end

function AbbreviationFormatter.formatNumber(valueRaw: any, optionsRaw: NumberFormatOptions?): string
	if typeof(valueRaw) ~= "number" then
		return "0"
	end
	local value = valueRaw :: number
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "inf"
	end
	if value == -math.huge then
		return "-inf"
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local trimTrailing = if options.trimTrailingZeros == nil then true else options.trimTrailingZeros == true
	local minThreshold = if typeof(options.minThreshold) == "number" then math.max(0, options.minThreshold) else 0
	local forceSign = options.forceSign == true

	local magnitude = math.abs(value)
	for _, rule in DEFAULT_RULES do
		if magnitude >= math.max(rule.threshold, minThreshold) then
			local precision = normalizePrecision(options.precision, rule.precision)
			local scaled = magnitude / rule.divisor
			return signPrefix(value, forceSign) .. formatFixed(scaled, precision, trimTrailing) .. rule.suffix
		end
	end

	local precision = normalizePrecision(options.precision, if magnitude >= 100 then 0 else 2)
	return signPrefix(value, forceSign) .. formatFixed(magnitude, precision, trimTrailing)
end

function AbbreviationFormatter.formatPercent(valueRaw: any, precisionRaw: any?, forceSignRaw: any?): string
	if typeof(valueRaw) ~= "number" then
		return "0%"
	end
	local precision = normalizePrecision(precisionRaw, 1)
	local value = valueRaw :: number
	local scaled = value * 100
	local text = formatFixed(math.abs(scaled), precision, true)
	return signPrefix(scaled, forceSignRaw == true) .. text .. "%"
end

function AbbreviationFormatter.formatDps(valueRaw: any, precisionRaw: any?): string
	if typeof(valueRaw) ~= "number" then
		return "0 DPS"
	end
	local text = AbbreviationFormatter.formatNumber(valueRaw, {
		precision = normalizePrecision(precisionRaw, 1),
		trimTrailingZeros = true,
	})
	return text .. " DPS"
end

function AbbreviationFormatter.formatTime(valueRaw: any): string
	if typeof(valueRaw) ~= "number" then
		return "0s"
	end
	local seconds = math.max(0, math.floor(valueRaw))
	if seconds < 60 then
		return string.format("%ds", seconds)
	end
	local minutes = math.floor(seconds / 60)
	seconds %= 60
	if minutes < 60 then
		return string.format("%dm %02ds", minutes, seconds)
	end
	local hours = math.floor(minutes / 60)
	minutes %= 60
	return string.format("%dh %02dm %02ds", hours, minutes, seconds)
end

function AbbreviationFormatter.formatTimeMMSS(valueRaw: any): string
	if typeof(valueRaw) ~= "number" then
		return "00:00"
	end
	local totalSeconds = math.max(0, math.floor(valueRaw))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

function AbbreviationFormatter.formatValue(valueRaw: any, formatKindRaw: any, precisionRaw: any?): string
	local formatKind = if typeof(formatKindRaw) == "string" then formatKindRaw else "number"
	if formatKind == "percent" then
		return AbbreviationFormatter.formatPercent(valueRaw, precisionRaw)
	end
	if formatKind == "dps" then
		return AbbreviationFormatter.formatDps(valueRaw, precisionRaw)
	end
	if formatKind == "time" then
		return AbbreviationFormatter.formatTime(valueRaw)
	end
	if formatKind == "mmss" then
		return AbbreviationFormatter.formatTimeMMSS(valueRaw)
	end
	return AbbreviationFormatter.formatNumber(valueRaw, {
		precision = precisionRaw,
	})
end

return AbbreviationFormatter
