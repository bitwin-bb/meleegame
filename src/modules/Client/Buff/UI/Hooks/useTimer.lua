local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")
local useInterval = require("useInterval")

export type TimerResult = {
	text: string,
	remainingSeconds: number?,
	progress: number,
	isInfinite: boolean,
}

local UPDATE_INTERVAL_SECONDS = 0.2
local DAY_SECONDS = 86400
local HOUR_SECONDS = 3600
local MINUTE_SECONDS = 60

local function CoerceNumber(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end

	return math.max(0, valueRaw)
end

local function abbreviateTime(secondsRaw: number?): string
	if secondsRaw == nil or secondsRaw == math.huge then
		return "inf"
	end

	local seconds = math.max(0, math.ceil(secondsRaw))
	if seconds >= DAY_SECONDS then
		return `{math.ceil(seconds / DAY_SECONDS)}d`
	end
	if seconds >= HOUR_SECONDS then
		return `{math.ceil(seconds / HOUR_SECONDS)}h`
	end
	if seconds >= MINUTE_SECONDS then
		return `{math.ceil(seconds / MINUTE_SECONDS)}m`
	end
	return `{seconds}s`
end

local function GetEmainingSeconds(recordRaw: any, now: number): number?
	if typeof(recordRaw) ~= "table" then
		return nil
	end

	local record = recordRaw :: { [string]: any }
	local remainingSeconds = CoerceNumber(record.remainingSeconds)
	if remainingSeconds ~= nil then
		return remainingSeconds
	end

	local expiresAt = CoerceNumber(record.expiresAt)
	if expiresAt ~= nil then
		return math.max(0, expiresAt - now)
	end

	return nil
end

local function GetProgress(recordRaw: any, remainingSeconds: number?): number
	if typeof(recordRaw) ~= "table" or remainingSeconds == nil then
		return 0
	end

	local duration = CoerceNumber((recordRaw :: { [string]: any }).duration)
	if duration == nil or duration <= 0 then
		return 0
	end

	return math.clamp(remainingSeconds / duration, 0, 1)
end

local function useTimer(recordRaw: any): TimerResult
	local now, setNow = React.useState(os.clock())

	useInterval(
		function()
			setNow(os.clock())
		end,
		UPDATE_INTERVAL_SECONDS,
		{
			enabled = typeof(recordRaw) == "table",
		}
	)

	local remainingSeconds = GetEmainingSeconds(recordRaw, now)
	local isInfinite = remainingSeconds == nil
	local result = {
		text = abbreviateTime(remainingSeconds),
		remainingSeconds = remainingSeconds,
		progress = GetProgress(recordRaw, remainingSeconds),
		isInfinite = isInfinite,
	}

	return Table.copy(result) :: TimerResult
end

return useTimer
