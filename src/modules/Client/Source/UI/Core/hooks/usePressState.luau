local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)
local useStableCallback = require("useStableCallback")

export type PressStateOptions = {
	disabled: boolean?,
	initialHovered: boolean?,
	initialPressed: boolean?,
	onHoverChanged: ((boolean) -> ())?,
	onPressedChanged: ((boolean) -> ())?,
}

export type PressStateResult = {
	hovered: boolean,
	pressed: boolean,
	setHovered: (boolean) -> (),
	setPressed: (boolean) -> (),
	eventHandlers: { [any]: (...any) -> () },
}

local function isPrimaryInput(inputObject: InputObject): boolean
	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
		or inputObject.KeyCode == Enum.KeyCode.ButtonA
end

local function usePressState(options: PressStateOptions?): PressStateResult
	local disabled = options ~= nil and options.disabled == true
	local onHoverChanged = useStableCallback(if options ~= nil then options.onHoverChanged else nil)
	local onPressedChanged = useStableCallback(if options ~= nil then options.onPressedChanged else nil)
	local hovered, setHoveredState = React.useState(options ~= nil and options.initialHovered == true)
	local pressed, setPressedState = React.useState(options ~= nil and options.initialPressed == true)

	local setHovered = (React.useCallback :: any)(function(nextHoveredRaw: boolean)
		local nextHovered = nextHoveredRaw == true and not disabled
		setHoveredState(nextHovered)
		onHoverChanged(nextHovered)
	end, { disabled, onHoverChanged } :: { any })

	local setPressed = (React.useCallback :: any)(function(nextPressedRaw: boolean)
		local nextPressed = nextPressedRaw == true and not disabled
		setPressedState(nextPressed)
		onPressedChanged(nextPressed)
	end, { disabled, onPressedChanged } :: { any })

	local onMouseEnter = React.useCallback(function()
		setHovered(true)
	end, { setHovered })

	local onMouseLeave = React.useCallback(function()
		setHovered(false)
		setPressed(false)
	end, { setHovered, setPressed })

	local onInputBegan = React.useCallback(function(_: GuiObject, inputObject: InputObject)
		if disabled or not isPrimaryInput(inputObject) then
			return
		end
		setPressed(true)
	end, { disabled, setPressed })

	local onInputEnded = React.useCallback(function(_: GuiObject, inputObject: InputObject)
		if not isPrimaryInput(inputObject) then
			return
		end
		setPressed(false)
	end, { setPressed })

	return {
		hovered = hovered,
		pressed = pressed,
		setHovered = setHovered,
		setPressed = setPressed,
		eventHandlers = {
			[React.Event.MouseEnter] = onMouseEnter,
			[React.Event.MouseLeave] = onMouseLeave,
			[React.Event.InputBegan] = onInputBegan,
			[React.Event.InputEnded] = onInputEnded,
		},
	}
end

return usePressState
