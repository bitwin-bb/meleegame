--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"

local function requireFromGameRoot(...: string): any
	local packageContainer = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	if packageContainer == nil then
		packageContainer = ReplicatedStorage:FindFirstChild(PACKAGE_NAME)
	end
	if packageContainer == nil then
		packageContainer = ReplicatedStorage:WaitForChild(PACKAGE_NAME, 5)
	end
	assert(packageContainer ~= nil, `Could not find the {PACKAGE_NAME} package container for Cmdr types.`)

	local current = packageContainer:FindFirstChild("game")
	assert(current ~= nil, `Could not find the "game" folder in {PACKAGE_NAME}.`)

	for index = 1, select("#", ...) do
		local segment = select(index, ...)
		current = current:FindFirstChild(segment)
		assert(current ~= nil, `Could not resolve Cmdr type dependency segment "{segment}".`)
	end

	return require(current)
end

local WeatherServiceUtils = requireFromGameRoot("Shared", "Services", "WeatherService", "WeatherServiceUtils")

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
	return string.lower(string.gsub(trimmed, "[%s_%-%.]", ""))
end

local function resolveWeatherValue(valueRaw: any): string?
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
			local exactValue = resolveWeatherValue(text)

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
