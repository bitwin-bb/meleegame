--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type CountDownOptions = {
	enabled: boolean?,
	respawnAt: number?,
	diedAt: number?,
	appearDelay: number?,
	fromOffset: Vector2?,
	toOffset: Vector2?,
	minScale: number?,
	maxScale: number?,
	spring: SpringOptions?,
}

export type CountDownState = {
	progress: number,
	offset: Vector2,
	scale: number,
	transparency: number,
	strokeTransparency: number,
	secondsLeft: number,
	canRespawn: boolean,
	revealed: boolean,
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 2.45,
	damping = 0.84,
}

local DEFAULT_FROM_OFFSET = Vector2.new(0, 8)
local DEFAULT_TO_OFFSET = Vector2.new(0, 56)
local DEFAULT_MIN_SCALE = 0.74
local DEFAULT_MAX_SCALE = 1
local DEFAULT_APPEAR_DELAY = 2
local MIN_APPEAR_DELAY = 0
local MAX_APPEAR_DELAY = 10

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

local function sanitizeRespawnAt(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return valueRaw
end

local function sanitizeDiedAt(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return valueRaw
end

local function sanitizeAppearDelay(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return DEFAULT_APPEAR_DELAY
	end
	return math.clamp(valueRaw, MIN_APPEAR_DELAY, MAX_APPEAR_DELAY)
end

local function smoothstep(alphaRaw: number): number
	local alpha = math.clamp(alphaRaw, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function resolveInitialCountdownSeconds(respawnAt: number?, diedAt: number?): number
	if respawnAt == nil then
		return 0
	end
	if diedAt ~= nil then
		return math.max(0, math.ceil(respawnAt - diedAt))
	end
	return math.max(0, math.ceil(respawnAt - os.clock()))
end

local function computeSecondsLeft(respawnAt: number?): number
	if respawnAt == nil then
		return 0
	end
	return math.max(0, math.ceil(respawnAt - os.clock()))
end

local function shouldRevealCountdown(enabled: boolean, respawnAt: number?, diedAt: number?, appearDelay: number): boolean
	if not enabled or respawnAt == nil then
		return false
	end
	if diedAt == nil then
		return true
	end
	return os.clock() >= (diedAt + appearDelay)
end

local function useCountDown(options: CountDownOptions?): CountDownState
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local respawnAt = sanitizeRespawnAt(if options then options.respawnAt else nil)
	local diedAt = sanitizeDiedAt(if options then options.diedAt else nil)
	local appearDelay = sanitizeAppearDelay(if options then options.appearDelay else nil)
	local fromOffset = sanitizeVector2(if options then options.fromOffset else nil, DEFAULT_FROM_OFFSET)
	local toOffset = sanitizeVector2(if options then options.toOffset else nil, DEFAULT_TO_OFFSET)
	local minScale = sanitizeScale(if options then options.minScale else nil, DEFAULT_MIN_SCALE)
	local maxScale = math.max(minScale, sanitizeScale(if options then options.maxScale else nil, DEFAULT_MAX_SCALE))
	local spring = if options and options.spring ~= nil then options.spring else DEFAULT_SPRING
	local initialCountdownSeconds = resolveInitialCountdownSeconds(respawnAt, diedAt)

	local initiallyRevealed = shouldRevealCountdown(enabled, respawnAt, diedAt, appearDelay)
	local revealRef = React.useRef(initiallyRevealed)
	local progress, setProgress = React.useState(if initiallyRevealed then 1 else 0)
	local revealed, setRevealed = React.useState(initiallyRevealed)
	local secondsLeft, setSecondsLeft = React.useState(function(): number
		if enabled then
			if initiallyRevealed then
				return computeSecondsLeft(respawnAt)
			end
			return initialCountdownSeconds
		end
		return 0
	end)

	React.useEffect(function()
		local nextRevealed = shouldRevealCountdown(enabled, respawnAt, diedAt, appearDelay)
		revealRef.current = nextRevealed
		setRevealed(nextRevealed)
		if enabled then
			if nextRevealed then
				setSecondsLeft(computeSecondsLeft(respawnAt))
			else
				setSecondsLeft(initialCountdownSeconds)
			end
		else
			setSecondsLeft(0)
		end
	end, { enabled, respawnAt, diedAt, appearDelay, initialCountdownSeconds })

	React.useEffect(function()
		local motion: NumberMotion = Ripple.createMotion(progress)
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local nextRevealed = shouldRevealCountdown(enabled, respawnAt, diedAt, appearDelay)
			if revealRef.current ~= nextRevealed then
				revealRef.current = nextRevealed
				setRevealed(nextRevealed)
			end
			motion:spring(if nextRevealed then 1 else 0, spring)
			local nextProgress = math.clamp(motion:step(deltaTime), 0, 1)
			setProgress(nextProgress)
		end)

		return function()
			connection:Disconnect()
			motion:destroy()
		end
	end, { enabled, respawnAt, diedAt, appearDelay, spring })

	React.useEffect(function()
		if not enabled then
			setSecondsLeft(0)
			return
		end

		local function updateSeconds()
			local isRevealed = shouldRevealCountdown(enabled, respawnAt, diedAt, appearDelay)
			if not isRevealed then
				setSecondsLeft(initialCountdownSeconds)
				return
			end

			local nextSeconds = computeSecondsLeft(respawnAt)
			setSecondsLeft(function(previousSeconds: number): number
				if previousSeconds == nextSeconds then
					return previousSeconds
				end
				return nextSeconds
			end)
		end

		updateSeconds()
		local connection = RunService.RenderStepped:Connect(function()
			updateSeconds()
		end)

		return function()
			connection:Disconnect()
		end
	end, { enabled, respawnAt, diedAt, appearDelay, initialCountdownSeconds })

	local fluidProgress = smoothstep(progress)
	local offset = fromOffset:Lerp(toOffset, fluidProgress)
	local scale = minScale + (maxScale - minScale) * fluidProgress

	local totalDistance = (toOffset - fromOffset).Magnitude
	local remainingDistance = (toOffset - offset).Magnitude
	local positionAlpha = if totalDistance <= 0.0001
		then fluidProgress
		else math.clamp(1 - (remainingDistance / totalDistance), 0, 1)
	local transparency = math.clamp(1 - positionAlpha, 0, 1)
	local strokeTransparency = math.clamp(0.14 + transparency * 0.86, 0, 1)

	return {
		progress = progress,
		offset = offset,
		scale = scale,
		transparency = transparency,
		strokeTransparency = strokeTransparency,
		secondsLeft = secondsLeft,
		canRespawn = revealed and secondsLeft <= 0,
		revealed = revealed,
	}
end

return useCountDown
