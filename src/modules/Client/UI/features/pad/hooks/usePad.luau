--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

export type PadOptions = {
	enabled: boolean?,
	collapsedSize: Vector2?,
	expandedSize: Vector2?,
	phaseDuration: number?,
}

export type PadState = {
	size: Vector2,
	progress: number,
	expanding: boolean,
}

local DEFAULT_COLLAPSED_SIZE = Vector2.new(44, 44)
local DEFAULT_EXPANDED_SIZE = Vector2.new(52, 52)
local DEFAULT_PHASE_DURATION = 0.7

local function sanitizeVector2(valueRaw: any, fallback: Vector2): Vector2
	if typeof(valueRaw) ~= "Vector2" then
		return fallback
	end
	if valueRaw.X ~= valueRaw.X or valueRaw.Y ~= valueRaw.Y then
		return fallback
	end
	return valueRaw
end

local function sanitizeDuration(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(0.05, valueRaw)
end

local function createPadState(size: Vector2, progress: number, expanding: boolean): PadState
	return {
		size = size,
		progress = math.clamp(progress, 0, 1),
		expanding = expanding,
	}
end

local function usePad(options: PadOptions?): PadState
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local collapsedSize = sanitizeVector2(
		if options ~= nil then options.collapsedSize else nil,
		DEFAULT_COLLAPSED_SIZE
	)
	local requestedExpandedSize = sanitizeVector2(
		if options ~= nil then options.expandedSize else nil,
		DEFAULT_EXPANDED_SIZE
	)
	local expandedSize = Vector2.new(
		math.max(collapsedSize.X, requestedExpandedSize.X),
		math.max(collapsedSize.Y, requestedExpandedSize.Y)
	)
	local phaseDuration = sanitizeDuration(if options ~= nil then options.phaseDuration else nil, DEFAULT_PHASE_DURATION)

	local phaseElapsedRef = React.useRef(0)
	local expandingRef = React.useRef(true)
	local padState, setPadState = React.useState(createPadState(collapsedSize, 0, true))

	React.useEffect(function()
		phaseElapsedRef.current = 0
		expandingRef.current = true
		setPadState(createPadState(collapsedSize, 0, true))
	end, { enabled, collapsedSize, expandedSize, phaseDuration })

	React.useEffect(function()
		if not enabled then
			setPadState(createPadState(collapsedSize, 0, true))
			return nil
		end

		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			phaseElapsedRef.current += math.max(0, deltaTime)

			local expanding = expandingRef.current
			local phaseProgress = math.clamp(phaseElapsedRef.current / phaseDuration, 0, 1)
			local fromSize = if expanding then collapsedSize else expandedSize
			local toSize = if expanding then expandedSize else collapsedSize
			local size = fromSize:Lerp(toSize, phaseProgress)
			local displayProgress = if expanding then phaseProgress else 1 - phaseProgress

			setPadState(createPadState(size, displayProgress, expanding))

			if phaseProgress >= 1 then
				phaseElapsedRef.current = 0
				expandingRef.current = not expanding
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, { enabled, collapsedSize, expandedSize, phaseDuration })

	return padState
end

return usePad
