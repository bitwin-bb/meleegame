--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type SlotSelectOptions = {
	enabled: boolean?,
	normalScale: number?,
	selectedScale: number?,
	spring: SpringOptions?,
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 0.25,
	damping = 0.82,
}

local DEFAULT_NORMAL_SCALE = 1
local DEFAULT_SELECTED_SCALE = 1.12

local function sanitizeScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return fallback
	end
	return valueRaw
end

local function useSlotSelect(options: SlotSelectOptions?): number
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local normalScale = sanitizeScale(if options then options.normalScale else nil, DEFAULT_NORMAL_SCALE)
	local selectedScale = math.max(
		normalScale,
		sanitizeScale(if options then options.selectedScale else nil, DEFAULT_SELECTED_SCALE)
	)
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

	return normalScale + (selectedScale - normalScale) * progress
end

return useSlotSelect
