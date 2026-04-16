--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type BiomeNameAppearanceOptions = {
	enabled: boolean?,
	fromOffset: Vector2?,
	toOffset: Vector2?,
	minScale: number?,
	maxScale: number?,
	spring: SpringOptions?,
}

export type BiomeNameAppearanceState = {
	progress: number,
	offset: Vector2,
	scale: number,
	transparency: number,
	strokeTransparency: number,
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 2.9,
	damping = 0.86,
}

local DEFAULT_FROM_OFFSET = Vector2.new(0, -22)
local DEFAULT_TO_OFFSET = Vector2.zero
local DEFAULT_MIN_SCALE = 0.82
local DEFAULT_MAX_SCALE = 1

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
	return math.max(0.05, valueRaw)
end

local function smoothstep(alphaRaw: number): number
	local alpha = math.clamp(alphaRaw, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function useBiomeNameAppearance(options: BiomeNameAppearanceOptions?): BiomeNameAppearanceState
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local fromOffset = sanitizeVector2(if options then options.fromOffset else nil, DEFAULT_FROM_OFFSET)
	local toOffset = sanitizeVector2(if options then options.toOffset else nil, DEFAULT_TO_OFFSET)
	local minScale = sanitizeScale(if options then options.minScale else nil, DEFAULT_MIN_SCALE)
	local maxScale = math.max(minScale, sanitizeScale(if options then options.maxScale else nil, DEFAULT_MAX_SCALE))
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
	local scale = minScale + (maxScale - minScale) * fluidProgress
	local scaleAlpha = if maxScale - minScale <= 0.0001 then fluidProgress else math.clamp((scale - minScale) / (maxScale - minScale), 0, 1)
	local transparency = math.clamp(1 - scaleAlpha, 0, 1)
	local strokeTransparency = math.clamp(0.18 + transparency * 0.82, 0, 1)

	return {
		progress = progress,
		offset = offset,
		scale = scale,
		transparency = transparency,
		strokeTransparency = strokeTransparency,
	}
end

return useBiomeNameAppearance
