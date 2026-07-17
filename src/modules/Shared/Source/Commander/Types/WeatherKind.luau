local require = require(script.Parent.loader).load(script)

local WeatherServiceUtils = require("WeatherServiceUtils")

local WEATHER_OPTIONS = {
	{
		Name = "Clear",
		Value = WeatherServiceUtils.WEATHER_TYPE_CLEAR,
	},
	{
		Name = "Rainstorm",
		Value = WeatherServiceUtils.WEATHER_TYPE_RAINSTORM,
	},
	{
		Name = "Thunderstorm",
		Value = WeatherServiceUtils.WEATHER_TYPE_THUNDERSTORM,
	},
}

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	local trimmed = string.match(valueRaw, "^%s*(.-)%s*$") or ""
	local normalized = string.gsub(trimmed, "[%s_%-%.]", "")
	return string.lower(normalized)
end

local function getWeatherValue(valueRaw: any): string?
	local token = normalizeToken(valueRaw)
	if token == "clear" or token == "sunny" then
		return WeatherServiceUtils.WEATHER_TYPE_CLEAR
	end
	if token == "rain" or token == "rainstorm" or token == "storm" then
		return WeatherServiceUtils.WEATHER_TYPE_RAINSTORM
	end
	if token == "thunder" or token == "thunderstorm" or token == "lightning" then
		return WeatherServiceUtils.WEATHER_TYPE_THUNDERSTORM
	end
	return nil
end

return function(registry)
	local cmdrUtil = registry.Cmdr.Util

	registry:RegisterType("weatherKind", {
		Transform = function(text: string)
			local fuzzyFinder = cmdrUtil.MakeFuzzyFinder(WEATHER_OPTIONS)
			local matches = fuzzyFinder(text)
			local exactValue = getWeatherValue(text)

			if exactValue == nil then
				return matches
			end

			local exactEntry = nil :: { Name: string, Value: string }?
			for _, entry in WEATHER_OPTIONS do
				if entry.Value == exactValue then
					exactEntry = entry
					break
				end
			end

			if exactEntry == nil then
				return matches
			end

			local orderedMatches = { exactEntry }
			for _, entry in matches do
				if entry.Value ~= exactEntry.Value then
					orderedMatches[#orderedMatches + 1] = entry
				end
			end

			return orderedMatches
		end,

		Validate = function(items)
			return #items > 0, "No matching weather type was found."
		end,

		Autocomplete = function(items)
			return cmdrUtil.GetNames(items)
		end,

		Parse = function(items)
			return items[1].Value
		end,
	})
end
