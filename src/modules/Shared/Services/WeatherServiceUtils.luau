--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Range = require(script:FindFirstAncestor("game").Shared.Modules.Math.Range)
local WorldSimulationShared = require(script:FindFirstAncestor("game").Shared.Services.Shared)

local WeatherServiceUtils = {}

export type WeatherType = "Clear" | "Rainstorm" | "Thunderstorm"
export type SkyKey = "Overworld" | "Corruption" | "Underground" | "SnowBiome"

export type WeatherServiceConfig = {
	enabled: boolean,
	dayNightCycleEnabled: boolean,
	dayDurationSeconds: number,
	initialClockTime: number,
	weatherCycleEnabled: boolean,
	initialWeatherType: WeatherType,
	weatherDurationMinSeconds: number,
	weatherDurationMaxSeconds: number,
	weatherTransitionSeconds: number,
	statePushIntervalSeconds: number,
	defaultSkyTransitionSeconds: number,
	defaultCloudTransitionSeconds: number,
	defaultRainTransitionSeconds: number,
	biomeSampleIntervalSeconds: number,
	clearWeatherWeight: number,
	rainstormWeatherWeight: number,
	thunderstormWeatherWeight: number,
}

export type WeatherServiceState = {
	ready: boolean,
	dayNightCycleEnabled: boolean,
	clockTime: number,
	clockSpeed: number,
	weatherType: WeatherType,
	weatherTransitionSeconds: number,
	rainIntensity: number,
	skyTransitionSeconds: number,
	cloudTransitionSeconds: number,
	rainTransitionSeconds: number,
	biomeSampleIntervalSeconds: number,
	snapshotServerTime: number,
	updatedAt: number,
}

WeatherServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"

WeatherServiceUtils.WEATHER_TYPE_CLEAR = "Clear"
WeatherServiceUtils.WEATHER_TYPE_RAINSTORM = "Rainstorm"
WeatherServiceUtils.WEATHER_TYPE_THUNDERSTORM = "Thunderstorm"

WeatherServiceUtils.SKY_KEY_OVERWORLD = "Overworld"
WeatherServiceUtils.SKY_KEY_CORRUPTION = "Corruption"
WeatherServiceUtils.SKY_KEY_UNDERGROUND = "Underground"
WeatherServiceUtils.SKY_KEY_SNOW_BIOME = "SnowBiome"

WeatherServiceUtils.BIOME_TYPE_NORMAL = 1
WeatherServiceUtils.BIOME_TYPE_CORRUPTION = 2

local DEFAULT_CONFIG: WeatherServiceConfig = {
	enabled = true,
	dayNightCycleEnabled = true,
	dayDurationSeconds = 16 * 60,
	initialClockTime = 8.5,
	weatherCycleEnabled = true,
	initialWeatherType = "Clear",
	weatherDurationMinSeconds = 75,
	weatherDurationMaxSeconds = 190,
	weatherTransitionSeconds = 6,
	statePushIntervalSeconds = 0.5,
	defaultSkyTransitionSeconds = 4,
	defaultCloudTransitionSeconds = 4,
	defaultRainTransitionSeconds = 1.2,
	biomeSampleIntervalSeconds = 0.3,
	clearWeatherWeight = 0.58,
	rainstormWeatherWeight = 0.3,
	thunderstormWeatherWeight = 0.12,
}

local RAIN_INTENSITY_BY_WEATHER: { [WeatherType]: number } = {
	Clear = 0,
	Rainstorm = 0.72,
	Thunderstorm = 1,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeString(valueRaw: any, fallback: string?): string?
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(trim(valueRaw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function normalizeClockTime(clockTimeRaw: any, fallback: number): number
	local value = sanitizeNumber(clockTimeRaw, fallback, -100000, 100000)
	return Range.wrap(value, 0, 24)
end

local function sanitizeWeatherType(weatherTypeRaw: any, fallback: WeatherType?): WeatherType
	if weatherTypeRaw == "Clear" then
		return "Clear"
	end
	if weatherTypeRaw == "Rainstorm" then
		return "Rainstorm"
	end
	if weatherTypeRaw == "Thunderstorm" then
		return "Thunderstorm"
	end
	return fallback or "Clear"
end

local function sanitizeSkyKey(skyKeyRaw: any, fallback: SkyKey?): SkyKey
	if skyKeyRaw == "Overworld" then
		return "Overworld"
	end
	if skyKeyRaw == "Corruption" then
		return "Corruption"
	end
	if skyKeyRaw == "Underground" then
		return "Underground"
	end
	if skyKeyRaw == "SnowBiome" then
		return "SnowBiome"
	end
	local text = sanitizeString(skyKeyRaw, nil)
	if text ~= nil then
		local lowered = string.lower(text)
		if lowered == "overworld" then
			return "Overworld"
		end
		if lowered == "corruption" then
			return "Corruption"
		end
		if lowered == "underground" then
			return "Underground"
		end
		if lowered == "snowbiome" or lowered == "snow_biome" or lowered == "snow" then
			return "SnowBiome"
		end
	end
	return fallback or "Overworld"
end

function WeatherServiceUtils.CreateDefaultConfig(): WeatherServiceConfig
	return {
		enabled = DEFAULT_CONFIG.enabled,
		dayNightCycleEnabled = DEFAULT_CONFIG.dayNightCycleEnabled,
		dayDurationSeconds = DEFAULT_CONFIG.dayDurationSeconds,
		initialClockTime = DEFAULT_CONFIG.initialClockTime,
		weatherCycleEnabled = DEFAULT_CONFIG.weatherCycleEnabled,
		initialWeatherType = DEFAULT_CONFIG.initialWeatherType,
		weatherDurationMinSeconds = DEFAULT_CONFIG.weatherDurationMinSeconds,
		weatherDurationMaxSeconds = DEFAULT_CONFIG.weatherDurationMaxSeconds,
		weatherTransitionSeconds = DEFAULT_CONFIG.weatherTransitionSeconds,
		statePushIntervalSeconds = DEFAULT_CONFIG.statePushIntervalSeconds,
		defaultSkyTransitionSeconds = DEFAULT_CONFIG.defaultSkyTransitionSeconds,
		defaultCloudTransitionSeconds = DEFAULT_CONFIG.defaultCloudTransitionSeconds,
		defaultRainTransitionSeconds = DEFAULT_CONFIG.defaultRainTransitionSeconds,
		biomeSampleIntervalSeconds = DEFAULT_CONFIG.biomeSampleIntervalSeconds,
		clearWeatherWeight = DEFAULT_CONFIG.clearWeatherWeight,
		rainstormWeatherWeight = DEFAULT_CONFIG.rainstormWeatherWeight,
		thunderstormWeatherWeight = DEFAULT_CONFIG.thunderstormWeatherWeight,
	}
end

function WeatherServiceUtils.ResolveConfig(
	configRaw: any,
	fallbackRaw: WeatherServiceConfig?
): WeatherServiceConfig
	local fallback = if fallbackRaw ~= nil then fallbackRaw else WeatherServiceUtils.CreateDefaultConfig()
	local source = if typeof(configRaw) == "table" then (configRaw :: { [string]: any }) else {}

	local weatherDurationMinSeconds = sanitizeNumber(
		source.weatherDurationMinSeconds,
		fallback.weatherDurationMinSeconds,
		8,
		3600
	)
	local weatherDurationMaxSeconds = sanitizeNumber(
		source.weatherDurationMaxSeconds,
		fallback.weatherDurationMaxSeconds,
		weatherDurationMinSeconds,
		7200
	)

	local clearWeatherWeight = sanitizeNumber(source.clearWeatherWeight, fallback.clearWeatherWeight, 0, 1000)
	local rainstormWeatherWeight =
		sanitizeNumber(source.rainstormWeatherWeight, fallback.rainstormWeatherWeight, 0, 1000)
	local thunderstormWeatherWeight = sanitizeNumber(
		source.thunderstormWeatherWeight,
		fallback.thunderstormWeatherWeight,
		0,
		1000
	)

	return {
		enabled = sanitizeBoolean(source.enabled, fallback.enabled),
		dayNightCycleEnabled = sanitizeBoolean(source.dayNightCycleEnabled, fallback.dayNightCycleEnabled),
		dayDurationSeconds = sanitizeNumber(source.dayDurationSeconds, fallback.dayDurationSeconds, 30, 36000),
		initialClockTime = normalizeClockTime(source.initialClockTime, fallback.initialClockTime),
		weatherCycleEnabled = sanitizeBoolean(source.weatherCycleEnabled, fallback.weatherCycleEnabled),
		initialWeatherType = sanitizeWeatherType(source.initialWeatherType, fallback.initialWeatherType),
		weatherDurationMinSeconds = weatherDurationMinSeconds,
		weatherDurationMaxSeconds = weatherDurationMaxSeconds,
		weatherTransitionSeconds = sanitizeNumber(source.weatherTransitionSeconds, fallback.weatherTransitionSeconds, 0, 60),
		statePushIntervalSeconds = sanitizeNumber(source.statePushIntervalSeconds, fallback.statePushIntervalSeconds, 0.05, 5),
		defaultSkyTransitionSeconds = sanitizeNumber(
			source.defaultSkyTransitionSeconds,
			fallback.defaultSkyTransitionSeconds,
			0,
			20
		),
		defaultCloudTransitionSeconds = sanitizeNumber(
			source.defaultCloudTransitionSeconds,
			fallback.defaultCloudTransitionSeconds,
			0,
			20
		),
		defaultRainTransitionSeconds = sanitizeNumber(
			source.defaultRainTransitionSeconds,
			fallback.defaultRainTransitionSeconds,
			0.01,
			20
		),
		biomeSampleIntervalSeconds = sanitizeNumber(
			source.biomeSampleIntervalSeconds,
			fallback.biomeSampleIntervalSeconds,
			0.05,
			5
		),
		clearWeatherWeight = clearWeatherWeight,
		rainstormWeatherWeight = rainstormWeatherWeight,
		thunderstormWeatherWeight = thunderstormWeatherWeight,
	}
end

function WeatherServiceUtils.GetRainIntensityForWeather(weatherTypeRaw: any): number
	local weatherType = sanitizeWeatherType(weatherTypeRaw, "Clear")
	return RAIN_INTENSITY_BY_WEATHER[weatherType] or 0
end

function WeatherServiceUtils.IsThunderWeather(weatherTypeRaw: any): boolean
	return sanitizeWeatherType(weatherTypeRaw, "Clear") == "Thunderstorm"
end

function WeatherServiceUtils.ChooseWeightedWeatherType(
	randomObjectRaw: any,
	configRaw: any,
	currentWeatherTypeRaw: any?
): WeatherType
	local randomObject = if typeof(randomObjectRaw) == "Random" then (randomObjectRaw :: Random) else Random.new()
	local config = WeatherServiceUtils.ResolveConfig(configRaw, nil)

	local clearWeight = config.clearWeatherWeight
	local rainstormWeight = config.rainstormWeatherWeight
	local thunderstormWeight = config.thunderstormWeatherWeight
	local totalWeight = clearWeight + rainstormWeight + thunderstormWeight

	if totalWeight <= 0 then
		return "Clear"
	end

	local function rollType(): WeatherType
		local roll = randomObject:NextNumber(0, totalWeight)
		if roll <= clearWeight then
			return "Clear"
		end
		if roll <= clearWeight + rainstormWeight then
			return "Rainstorm"
		end
		return "Thunderstorm"
	end

	local currentWeatherType = sanitizeWeatherType(currentWeatherTypeRaw, nil)
	local rolled = rollType()
	if currentWeatherType == nil or rolled ~= currentWeatherType then
		return rolled
	end

	if totalWeight <= (if currentWeatherType == "Clear"
		then clearWeight
		elseif currentWeatherType == "Rainstorm"
		then rainstormWeight
		else thunderstormWeight)
	then
		return rolled
	end

	local rerolled = rollType()
	if rerolled ~= currentWeatherType then
		return rerolled
	end
	return rolled
end

function WeatherServiceUtils.CreateStateFromConfig(configRaw: any): WeatherServiceState
	local config = WeatherServiceUtils.ResolveConfig(configRaw, nil)
	local clockSpeed = if config.dayNightCycleEnabled then 24 / config.dayDurationSeconds else 0
	return {
		ready = config.enabled,
		dayNightCycleEnabled = config.dayNightCycleEnabled,
		clockTime = normalizeClockTime(config.initialClockTime, DEFAULT_CONFIG.initialClockTime),
		clockSpeed = clockSpeed,
		weatherType = sanitizeWeatherType(config.initialWeatherType, DEFAULT_CONFIG.initialWeatherType),
		weatherTransitionSeconds = config.weatherTransitionSeconds,
		rainIntensity = WeatherServiceUtils.GetRainIntensityForWeather(config.initialWeatherType),
		skyTransitionSeconds = config.defaultSkyTransitionSeconds,
		cloudTransitionSeconds = config.defaultCloudTransitionSeconds,
		rainTransitionSeconds = config.defaultRainTransitionSeconds,
		biomeSampleIntervalSeconds = config.biomeSampleIntervalSeconds,
		snapshotServerTime = 0,
		updatedAt = os.clock(),
	}
end

function WeatherServiceUtils.SanitizeState(
	stateRaw: any,
	fallbackRaw: WeatherServiceState?
): WeatherServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else WeatherServiceUtils.CreateStateFromConfig(nil)
	local source = if typeof(stateRaw) == "table" then (stateRaw :: { [string]: any }) else {}

	local dayNightCycleEnabled = sanitizeBoolean(source.dayNightCycleEnabled, fallback.dayNightCycleEnabled)
	local clockSpeed = sanitizeNumber(source.clockSpeed, fallback.clockSpeed, -100, 100)
	if not dayNightCycleEnabled then
		clockSpeed = 0
	end

	local weatherType = sanitizeWeatherType(source.weatherType, fallback.weatherType)
	local rainIntensity = sanitizeNumber(
		source.rainIntensity,
		WeatherServiceUtils.GetRainIntensityForWeather(weatherType),
		0,
		1
	)

	return {
		ready = sanitizeBoolean(source.ready, fallback.ready),
		dayNightCycleEnabled = dayNightCycleEnabled,
		clockTime = normalizeClockTime(source.clockTime, fallback.clockTime),
		clockSpeed = clockSpeed,
		weatherType = weatherType,
		weatherTransitionSeconds = sanitizeNumber(
			source.weatherTransitionSeconds,
			fallback.weatherTransitionSeconds,
			0,
			60
		),
		rainIntensity = rainIntensity,
		skyTransitionSeconds = sanitizeNumber(source.skyTransitionSeconds, fallback.skyTransitionSeconds, 0, 20),
		cloudTransitionSeconds = sanitizeNumber(source.cloudTransitionSeconds, fallback.cloudTransitionSeconds, 0, 20),
		rainTransitionSeconds = sanitizeNumber(source.rainTransitionSeconds, fallback.rainTransitionSeconds, 0.01, 20),
		biomeSampleIntervalSeconds = sanitizeNumber(
			source.biomeSampleIntervalSeconds,
			fallback.biomeSampleIntervalSeconds,
			0.05,
			5
		),
		snapshotServerTime = sanitizeNumber(source.snapshotServerTime, fallback.snapshotServerTime, 0, 10 ^ 12),
		updatedAt = sanitizeNumber(source.updatedAt, fallback.updatedAt, 0, 10 ^ 12),
	}
end

function WeatherServiceUtils.CloneState(stateRaw: WeatherServiceState): WeatherServiceState
	local state = stateRaw
	return {
		ready = state.ready,
		dayNightCycleEnabled = state.dayNightCycleEnabled,
		clockTime = state.clockTime,
		clockSpeed = state.clockSpeed,
		weatherType = state.weatherType,
		weatherTransitionSeconds = state.weatherTransitionSeconds,
		rainIntensity = state.rainIntensity,
		skyTransitionSeconds = state.skyTransitionSeconds,
		cloudTransitionSeconds = state.cloudTransitionSeconds,
		rainTransitionSeconds = state.rainTransitionSeconds,
		biomeSampleIntervalSeconds = state.biomeSampleIntervalSeconds,
		snapshotServerTime = state.snapshotServerTime,
		updatedAt = state.updatedAt,
	}
end

function WeatherServiceUtils.AdvanceClockTime(clockTimeRaw: any, dtRaw: any, clockSpeedRaw: any): number
	local clockTime = normalizeClockTime(clockTimeRaw, 12)
	local dt = sanitizeNumber(dtRaw, 0, 0, 60)
	local clockSpeed = sanitizeNumber(clockSpeedRaw, 0, -100, 100)
	if dt <= 0 or clockSpeed == 0 then
		return clockTime
	end
	return normalizeClockTime(clockTime + dt * clockSpeed, clockTime)
end

function WeatherServiceUtils.ShortestClockDeltaHours(fromClockRaw: any, toClockRaw: any): number
	local fromClock = normalizeClockTime(fromClockRaw, 0)
	local toClock = normalizeClockTime(toClockRaw, 0)
	return Range.wrap(toClock - fromClock + 12, 0, 24) - 12
end

function WeatherServiceUtils.ResolveSkyKeyFromWorldSample(
	biomeIdRaw: any,
	biomeTypeRaw: any,
	_depthLayerRaw: any
): SkyKey
	local biomeType = if typeof(biomeTypeRaw) == "number" then math.floor(biomeTypeRaw) else WeatherServiceUtils.BIOME_TYPE_NORMAL
	local biomeId = if typeof(biomeIdRaw) == "number"
		then math.floor(biomeIdRaw)
		else WorldSimulationShared.BIOME_ID.FOREST

	if biomeId == WorldSimulationShared.BIOME_ID.CORRUPTION or biomeType == WeatherServiceUtils.BIOME_TYPE_CORRUPTION then
		return WeatherServiceUtils.SKY_KEY_CORRUPTION
	end
	if biomeId == WorldSimulationShared.BIOME_ID.SNOW then
		return WeatherServiceUtils.SKY_KEY_SNOW_BIOME
	end
	return WeatherServiceUtils.SKY_KEY_OVERWORLD
end

function WeatherServiceUtils.ResolveSkyKeyFromBiomeType(biomeTypeRaw: any): SkyKey
	return WeatherServiceUtils.ResolveSkyKeyFromWorldSample(nil, biomeTypeRaw, nil)
end

function WeatherServiceUtils.ResolveSkyKeyFromBiome(biomeTypeRaw: any, biomeIdRaw: any): SkyKey
	return WeatherServiceUtils.ResolveSkyKeyFromWorldSample(biomeIdRaw, biomeTypeRaw, nil)
end

function WeatherServiceUtils.SanitizeWeatherType(weatherTypeRaw: any, fallback: WeatherType?): WeatherType
	return sanitizeWeatherType(weatherTypeRaw, fallback)
end

function WeatherServiceUtils.SanitizeSkyKey(skyKeyRaw: any, fallback: SkyKey?): SkyKey
	return sanitizeSkyKey(skyKeyRaw, fallback)
end

function WeatherServiceUtils.SanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	return sanitizeNumber(valueRaw, fallback, minimum, maximum)
end

function WeatherServiceUtils.SanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	return sanitizeBoolean(valueRaw, fallback)
end

WeatherServiceUtils.createDefaultConfig = WeatherServiceUtils.CreateDefaultConfig
WeatherServiceUtils.resolveConfig = WeatherServiceUtils.ResolveConfig
WeatherServiceUtils.getRainIntensityForWeather = WeatherServiceUtils.GetRainIntensityForWeather
WeatherServiceUtils.isThunderWeather = WeatherServiceUtils.IsThunderWeather
WeatherServiceUtils.chooseWeightedWeatherType = WeatherServiceUtils.ChooseWeightedWeatherType
WeatherServiceUtils.createStateFromConfig = WeatherServiceUtils.CreateStateFromConfig
WeatherServiceUtils.sanitizeState = WeatherServiceUtils.SanitizeState
WeatherServiceUtils.cloneState = WeatherServiceUtils.CloneState
WeatherServiceUtils.advanceClockTime = WeatherServiceUtils.AdvanceClockTime
WeatherServiceUtils.shortestClockDeltaHours = WeatherServiceUtils.ShortestClockDeltaHours
WeatherServiceUtils.resolveSkyKeyFromWorldSample = WeatherServiceUtils.ResolveSkyKeyFromWorldSample
WeatherServiceUtils.resolveSkyKeyFromBiomeType = WeatherServiceUtils.ResolveSkyKeyFromBiomeType
WeatherServiceUtils.resolveSkyKeyFromBiome = WeatherServiceUtils.ResolveSkyKeyFromBiome
WeatherServiceUtils.sanitizeWeatherType = WeatherServiceUtils.SanitizeWeatherType
WeatherServiceUtils.sanitizeSkyKey = WeatherServiceUtils.SanitizeSkyKey
WeatherServiceUtils.sanitizeNumber = WeatherServiceUtils.SanitizeNumber
WeatherServiceUtils.sanitizeBoolean = WeatherServiceUtils.SanitizeBoolean

return WeatherServiceUtils
