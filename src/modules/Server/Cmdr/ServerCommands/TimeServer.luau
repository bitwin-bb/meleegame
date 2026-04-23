--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for TimeServer.")

local WeatherServiceServer = require(gameRoot.Server.Services.WeatherServiceServer)

local TIME_PRESETS = {
	day = 8.5,
	dawn = 5.5,
	dusk = 18.5,
	midnight = 0,
	night = 22,
	noon = 12,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeToken(valueRaw: any): string
	return string.lower(string.gsub(trim(valueRaw), "[%s_%-%.]", ""))
end

local function parseBooleanToken(valueRaw: any): boolean?
	local token = normalizeToken(valueRaw)
	if token == "on" or token == "true" or token == "yes" or token == "enable" or token == "enabled" then
		return true
	end
	if token == "off" or token == "false" or token == "no" or token == "disable" or token == "disabled" then
		return false
	end
	return nil
end

local function parseTimeValue(valueRaw: any): (number?, string?)
	local rawText = trim(valueRaw)
	if rawText == "" then
		return nil, nil
	end

	local presetToken = normalizeToken(rawText)
	local presetClockTime = TIME_PRESETS[presetToken]
	if presetClockTime ~= nil then
		return presetClockTime, presetToken
	end

	local numericClockTime = tonumber(rawText)
	if numericClockTime ~= nil and numericClockTime == numericClockTime then
		return numericClockTime, nil
	end

	return nil, nil
end

local function formatClockTime(clockTimeRaw: number): string
	local clockTime = clockTimeRaw % 24
	if clockTime < 0 then
		clockTime += 24
	end

	local hours = math.floor(clockTime)
	local minutes = math.floor((clockTime - hours) * 60 + 0.5)
	if minutes >= 60 then
		minutes -= 60
		hours = (hours + 1) % 24
	end

	return string.format("%02d:%02d", hours, minutes)
end

return function(_context, actionRaw: string, valueRaw: string)
	local action = normalizeToken(actionRaw)

	if action == "set" then
		local clockTime, preset = parseTimeValue(valueRaw)
		if clockTime == nil then
			return "Use a preset like day/night/dawn/dusk/noon/midnight or a numeric hour from 0 to 24."
		end

		WeatherServiceServer:setDayNightCycleEnabled(false, true)
		local appliedClockTime = WeatherServiceServer:setClockTime(clockTime, true)
		if preset ~= nil then
			return (`Set time to {preset} ({formatClockTime(appliedClockTime)}) and paused the day/night cycle.`)
		end
		return (`Set time to {formatClockTime(appliedClockTime)} and paused the day/night cycle.`)
	end

	if action == "cycle" then
		local enabled = parseBooleanToken(valueRaw)
		if enabled == nil then
			return "Use `time cycle on` or `time cycle off`."
		end

		WeatherServiceServer:setDayNightCycleEnabled(enabled, true)
		if enabled then
			return "Enabled the day/night cycle."
		end
		return "Disabled the day/night cycle."
	end

	return "Use `time set <preset|hour>` or `time cycle <on|off>`."
end
