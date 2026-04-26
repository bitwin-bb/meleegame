--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GuiUtils = require(script.Parent.internal.gui)
local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local useSpring = require(script.Parent.useSpring)
local useViewport = require(script.Parent.useViewport)

export type ParallaxOptions = {
	enabled: boolean?,
	depth: number?,
	maxOffset: Vector2?,
	invert: boolean?,
	spring: Ripple.SpringOptions?,
}

export type ParallaxResult = {
	offset: Vector2,
	binding: React.Binding<Vector2>,
	normalized: Vector2,
}

local DEFAULT_MAX_OFFSET = Vector2.new(18, 14)

local function sanitizeDepth(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 1
	end
	return math.max(valueRaw, 0)
end

local function computeNormalizedPosition(screenPosition: Vector2, viewport: Vector2): Vector2
	if viewport.X <= 0 or viewport.Y <= 0 then
		return Vector2.zero
	end

	local normalizedX = math.clamp((screenPosition.X / viewport.X) * 2 - 1, -1, 1)
	local normalizedY = math.clamp((screenPosition.Y / viewport.Y) * 2 - 1, -1, 1)
	return Vector2.new(normalizedX, normalizedY)
end

local function useParallax(options: ParallaxOptions?): ParallaxResult
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local depth = sanitizeDepth(if options ~= nil then options.depth else nil)
	local maxOffset = if options ~= nil and options.maxOffset ~= nil then options.maxOffset else DEFAULT_MAX_OFFSET
	local invert = if options ~= nil and options.invert ~= nil then options.invert == true else false
	local viewportState = useViewport()
	local normalized, setNormalized = React.useState(Vector2.zero)

	React.useEffect(function()
		local function updateFromInput(inputObjectRaw: any)
			if not enabled then
				setNormalized(Vector2.zero)
				return
			end

			local screenPosition = GuiUtils.ResolveScreenPositionFromInput(inputObjectRaw)
			if screenPosition == nil then
				local mousePosition = UserInputService:GetMouseLocation()
				screenPosition = Vector2.new(mousePosition.X, mousePosition.Y)
			end

			setNormalized(computeNormalizedPosition(screenPosition, viewportState.viewport))
		end

		updateFromInput(nil)

		local changedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if
				inputObject.UserInputType == Enum.UserInputType.MouseMovement
				or inputObject.UserInputType == Enum.UserInputType.Touch
			then
				updateFromInput(inputObject)
			end
		end)

		local lastInputConnection = UserInputService.LastInputTypeChanged:Connect(function()
			updateFromInput(nil)
		end)

		return function()
			changedConnection:Disconnect()
			lastInputConnection:Disconnect()
		end
	end, { enabled, viewportState.viewport })

	local direction = if invert then -1 else 1
	local targetOffset = if enabled
		then Vector2.new(normalized.X * maxOffset.X * depth * direction, normalized.Y * maxOffset.Y * depth * direction)
		else Vector2.zero
	local springState = useSpring(targetOffset, {
		enabled = enabled,
		initialValue = Vector2.zero,
		spring = if options ~= nil then options.spring else nil,
	})

	return {
		offset = springState.value,
		binding = springState.binding,
		normalized = normalized,
	}
end

return useParallax
