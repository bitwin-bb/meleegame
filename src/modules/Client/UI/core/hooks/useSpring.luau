--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

export type SpringOptions = {
	enabled: boolean?,
	initialValue: any?,
	spring: Ripple.SpringOptions?,
	clamp: ((any) -> any)?,
}

export type SpringResult<T> = {
	value: T,
	binding: React.Binding<T>,
	setTarget: (T) -> (),
	jumpTo: (T) -> (),
	motion: any,
}

local DEFAULT_SPRING: Ripple.SpringOptions = {
	frequency = 2.6,
	damping = 0.82,
}

local function useSpring<T>(target: T, options: SpringOptions?): SpringResult<T>
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local initialValue = if options ~= nil and options.initialValue ~= nil then options.initialValue else target
	local spring = if options ~= nil and options.spring ~= nil then options.spring else DEFAULT_SPRING
	local clamp = if options ~= nil then options.clamp else nil
	local targetRef = React.useRef(target)
	local motionRef = React.useRef(nil)
	local currentValueRef = React.useRef(initialValue)
	local value, setValue = React.useState(initialValue)
	local binding, setBinding = React.useBinding(initialValue)

	local function applyValue(nextValueRaw: any)
		local nextValue = if typeof(clamp) == "function" then clamp(nextValueRaw) else nextValueRaw
		if currentValueRef.current == nextValue then
			return
		end

		currentValueRef.current = nextValue
		setValue(nextValue)
		setBinding(nextValue)
	end

	React.useEffect(function()
		targetRef.current = target
	end, { target })

	React.useEffect(function()
		local motion = Ripple.createMotion(currentValueRef.current)
		motion:immediate(currentValueRef.current)
		motionRef.current = motion

		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			if not enabled then
				if currentValueRef.current ~= targetRef.current then
					motion:immediate(targetRef.current)
					applyValue(targetRef.current)
				end
				return
			end

			motion:spring(targetRef.current, spring)
			applyValue(motion:step(deltaTime))
		end)

		return function()
			connection:Disconnect()
			motion:destroy()
			motionRef.current = nil
		end
	end, { enabled, spring })

	local setTarget = React.useCallback(function(nextTarget: T)
		targetRef.current = nextTarget
	end, {})

	local jumpTo = React.useCallback(function(nextTarget: T)
		targetRef.current = nextTarget
		local motion = motionRef.current
		if motion ~= nil then
			motion:immediate(nextTarget)
		end
		applyValue(nextTarget)
	end, {})

	return {
		value = value,
		binding = binding,
		setTarget = setTarget,
		jumpTo = jumpTo,
		motion = motionRef.current,
	}
end

return useSpring
