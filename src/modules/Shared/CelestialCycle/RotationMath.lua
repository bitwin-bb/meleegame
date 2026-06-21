local require = require(script.Parent.loader).load(script)

local Range = require("Range")
local SunPositionUtils = require("SunPositionUtils")
local Table = require("Table")

local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local MoonAssets = require("MoonAssets")
local SunAsset = require("SunAsset")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState
type CelestialBodyState = CelestialCycleTypes.CelestialBodyState
type DayPart = CelestialCycleTypes.DayPart
type MoonPhaseName = CelestialCycleTypes.MoonPhaseName

local RotationMath = {}

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function RotationMath.NormalizeClockTime(clockTimeRaw: any): number
	local clockTime = if typeof(clockTimeRaw) == "number" and clockTimeRaw == clockTimeRaw then clockTimeRaw else 0
	return Range.wrap(clockTime, 0, 24)
end

function RotationMath.ResolveDayProgress(clockTimeRaw: any): number
	return RotationMath.NormalizeClockTime(clockTimeRaw) / 24
end

function RotationMath.ResolveMoonPhase(worldDayIndexRaw: any): MoonPhaseName
	local worldDayIndex = if typeof(worldDayIndexRaw) == "number" then math.max(0, math.floor(worldDayIndexRaw)) else 0
	local phaseIndex = (worldDayIndex % CelestialCycleConstants.MOON_PHASE_DAY_COUNT) + 1
	return CelestialCycleConstants.MOON_PHASES[phaseIndex] :: MoonPhaseName
end

function RotationMath.ResolveDayPart(clockTimeRaw: any): DayPart
	local clockTime = RotationMath.NormalizeClockTime(clockTimeRaw)
	local resolved = "Night"
	for _, threshold in CelestialCycleConstants.DAY_PARTS do
		if clockTime >= threshold.startsAt then
			resolved = threshold.name
		end
	end
	return resolved :: DayPart
end

local function directionToPosition(direction: Vector3): UDim2
	local center = CelestialCycleConstants.BODY_ARC_CENTER
	local radius = CelestialCycleConstants.BODY_ARC_RADIUS
	return UDim2.fromScale(center.X + direction.X * radius.X, center.Y - direction.Y * radius.Y)
end

local function directionToAlpha(direction: Vector3): number
	return clamp01((direction.Y + 0.08) / 0.22)
end

local function resolveBodyState(
	name: "Sun" | "Moon",
	image: string,
	phase: MoonPhaseName?,
	direction: Vector3,
	zIndex: number
): CelestialBodyState
	local alpha = directionToAlpha(direction)
	return {
		name = name,
		image = image,
		phase = phase,
		visible = alpha > 0.001,
		alpha = alpha,
		position = directionToPosition(direction),
		size = CelestialCycleConstants.BODY_SIZE,
		rotation = math.deg(math.atan2(direction.Y, direction.X)),
		zIndex = zIndex,
	}
end

function RotationMath.ResolveCycleState(clockTimeRaw: any, worldDayIndexRaw: any): CelestialCycleState
	local clockTime = RotationMath.NormalizeClockTime(clockTimeRaw)
	local worldDayIndex = if typeof(worldDayIndexRaw) == "number" then math.max(0, math.floor(worldDayIndexRaw)) else 0
	local sunDirection, moonDirection =
		SunPositionUtils.getSunPosition(clockTime, CelestialCycleConstants.GEO_LATITUDE)
	local moonPhase = RotationMath.ResolveMoonPhase(worldDayIndex)

	return {
		ready = true,
		clockTime = clockTime,
		worldDayIndex = worldDayIndex,
		dayProgress = RotationMath.ResolveDayProgress(clockTime),
		dayPart = RotationMath.ResolveDayPart(clockTime),
		moonPhase = moonPhase,
		sun = resolveBodyState("Sun", SunAsset.getImage(), nil, sunDirection, 10),
		moon = resolveBodyState("Moon", MoonAssets.getImageForPhase(moonPhase), moonPhase, moonDirection, 9),
	}
end

RotationMath.normalizeClockTime = RotationMath.NormalizeClockTime
RotationMath.resolveDayProgress = RotationMath.ResolveDayProgress
RotationMath.resolveMoonPhase = RotationMath.ResolveMoonPhase
RotationMath.resolveDayPart = RotationMath.ResolveDayPart
RotationMath.resolveCycleState = RotationMath.ResolveCycleState

return Table.readonly(RotationMath)
