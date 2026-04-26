--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cleanup = require(script.Parent.internal.cleanup)
local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type LongPressOptions = {
	duration: number?,
	enabled: boolean?,
	inputTypes: { Enum.UserInputType }?,
	cancelOnPointerLeave: boolean?,
	onLongPress: ((InputObject?) -> ())?,
	onPressStart: ((InputObject?) -> ())?,
	onPressEnd: ((boolean, InputObject?) -> ())?,
}

export type LongPressResult = {
	pressing: boolean,
	longPressed: boolean,
	cancel: () -> (),
	eventHandlers: { [any]: (...any) -> () },
}

local DEFAULT_DURATION_SECONDS = 0.45
local DEFAULT_INPUT_TYPES = {
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.Touch,
}

local function sanitizeDurationSeconds(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return DEFAULT_DURATION_SECONDS
	end
	return math.max(valueRaw, 0)
end

local function matchesInputType(inputObject: InputObject, inputTypesRaw: { Enum.UserInputType }?): boolean
	local inputTypes = if type(inputTypesRaw) == "table" and #inputTypesRaw > 0
		then inputTypesRaw
		else DEFAULT_INPUT_TYPES
	for _, inputType in inputTypes do
		if inputObject.UserInputType == inputType then
			return true
		end
	end
	return false
end

local function useLongPress(options: LongPressOptions?): LongPressResult
	local durationSeconds = sanitizeDurationSeconds(if options ~= nil then options.duration else nil)
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local inputTypes = if options ~= nil then options.inputTypes else nil
	local cancelOnPointerLeave = if options ~= nil and options.cancelOnPointerLeave ~= nil
		then options.cancelOnPointerLeave == true
		else true
	local onLongPress = useStableCallback(if options ~= nil then options.onLongPress else nil)
	local onPressStart = useStableCallback(if options ~= nil then options.onPressStart else nil)
	local onPressEnd = useStableCallback(if options ~= nil then options.onPressEnd else nil)
	local pressingRef = React.useRef(false)
	local longPressedRef = React.useRef(false)
	local activeInputRef = React.useRef(nil :: InputObject?)
	local timerThreadRef = React.useRef(nil :: thread?)
	local endedConnectionRef = React.useRef(nil)
	local timerGenerationRef = React.useRef(0)
	local pressing, setPressing = React.useState(false)
	local longPressed, setLongPressed = React.useState(false)

	local cancel = React.useCallback(function()
		timerGenerationRef.current += 1
		Cleanup.CancelTask(timerThreadRef.current)
		timerThreadRef.current = nil
		Cleanup.Call(endedConnectionRef.current)
		endedConnectionRef.current = nil
		pressingRef.current = false
		longPressedRef.current = false
		activeInputRef.current = nil
		setPressing(false)
		setLongPressed(false)
	end, {})

	local finishPress = React.useCallback(function(resolvedInputObject: InputObject?)
		if not pressingRef.current and not longPressedRef.current then
			cancel()
			return
		end

		local didLongPress = longPressedRef.current
		local inputObject = if resolvedInputObject ~= nil then resolvedInputObject else activeInputRef.current
		cancel()
		onPressEnd(didLongPress, inputObject)
	end, { cancel, onPressEnd })

	local beginPress = React.useCallback(function(inputObject: InputObject)
		if not enabled or not matchesInputType(inputObject, inputTypes) then
			return
		end

		cancel()
		pressingRef.current = true
		longPressedRef.current = false
		activeInputRef.current = inputObject
		setPressing(true)
		setLongPressed(false)
		onPressStart(inputObject)

		timerGenerationRef.current += 1
		local generation = timerGenerationRef.current
		timerThreadRef.current = task.delay(durationSeconds, function()
			if timerGenerationRef.current ~= generation or not pressingRef.current then
				return
			end

			timerThreadRef.current = nil
			longPressedRef.current = true
			setLongPressed(true)
			onLongPress(activeInputRef.current)
		end)

		endedConnectionRef.current = UserInputService.InputEnded:Connect(function(endedInputObject: InputObject)
			local activeInput = activeInputRef.current
			if activeInput == nil then
				return
			end
			if endedInputObject == activeInput or endedInputObject.UserInputType == activeInput.UserInputType then
				finishPress(endedInputObject)
			end
		end)
	end, {
		enabled,
		inputTypes,
		cancel,
		durationSeconds,
		onPressStart,
		onLongPress,
		finishPress,
	})

	React.useEffect(function()
		return function()
			cancel()
		end
	end, { cancel })

	return {
		pressing = pressing,
		longPressed = longPressed,
		cancel = cancel,
		eventHandlers = {
			[React.Event.InputBegan] = function(_rbx: GuiObject, inputObject: InputObject)
				beginPress(inputObject)
			end,
			[React.Event.InputEnded] = function(_rbx: GuiObject, inputObject: InputObject)
				local activeInput = activeInputRef.current
				if activeInput == nil then
					return
				end
				if inputObject == activeInput or inputObject.UserInputType == activeInput.UserInputType then
					finishPress(inputObject)
				end
			end,
			[React.Event.MouseLeave] = function()
				if cancelOnPointerLeave then
					finishPress(activeInputRef.current)
				end
			end,
		},
	}
end

return useLongPress
