--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type TextUnderlineOptions = {
	enabled: boolean?,
	fromOffset: Vector2?,
	toOffset: Vector2?,
	minWidthScale: number?,
	maxWidthScale: number?,
	spring: SpringOptions?,
}

export type TextUnderlineState = {
	progress: number,
	offset: Vector2,
	widthScale: number,
	transparency: number,
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 2.6,
	damping = 0.84,
}

local DEFAULT_FROM_OFFSET = Vector2.new(0, 10)
local DEFAULT_TO_OFFSET = Vector2.zero
local DEFAULT_MIN_WIDTH_SCALE = 0.04
local DEFAULT_MAX_WIDTH_SCALE = 1

local function sanitizeVector2(valueRaw: any, fallback: Vector2): Vector2
	if typeof(valueRaw) ~= "Vector2" then
		return fallback
	end
	if valueRaw.X ~= valueRaw.X or valueRaw.Y ~= valueRaw.Y then
		return fallback
	end
	return valueRaw
end

local function sanitizeScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(0.01, valueRaw)
end

local function smoothstep(alphaRaw: number): number
	local alpha = math.clamp(alphaRaw, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function useTextUnderline(options: TextUnderlineOptions?): TextUnderlineState
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local fromOffset = sanitizeVector2(if options then options.fromOffset else nil, DEFAULT_FROM_OFFSET)
	local toOffset = sanitizeVector2(if options then options.toOffset else nil, DEFAULT_TO_OFFSET)
	local minWidthScale = sanitizeScale(if options then options.minWidthScale else nil, DEFAULT_MIN_WIDTH_SCALE)
	local maxWidthScale =
		math.max(minWidthScale, sanitizeScale(if options then options.maxWidthScale else nil, DEFAULT_MAX_WIDTH_SCALE))
	local spring = if options and options.spring ~= nil then options.spring else DEFAULT_SPRING

	local targetRef = React.useRef(if enabled then 1 else 0)
	local progress, setProgress = React.useState(targetRef.current)

	React.useEffect(function()
		targetRef.current = if enabled then 1 else 0
	end, { enabled })

	React.useEffect(function()
		local motion: NumberMotion = Ripple.createMotion(progress)
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			motion:spring(targetRef.current, spring)
			local nextProgress = math.clamp(motion:step(deltaTime), 0, 1)
			setProgress(nextProgress)
		end)

		return function()
			connection:Disconnect()
			motion:destroy()
		end
	end, { spring })

	local fluidProgress = smoothstep(progress)
	local offset = fromOffset:Lerp(toOffset, fluidProgress)
	local widthScale = minWidthScale + (maxWidthScale - minWidthScale) * fluidProgress

	local totalDistance = (toOffset - fromOffset).Magnitude
	local remainingDistance = (toOffset - offset).Magnitude
	local transparency = if totalDistance <= 0.0001
		then math.clamp(1 - fluidProgress, 0, 1)
		else math.clamp(remainingDistance / totalDistance, 0, 1)

	return {
		progress = progress,
		offset = offset,
		widthScale = widthScale,
		transparency = transparency,
	}
end

return useTextUnderline
