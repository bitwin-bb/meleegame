--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type FocusOptions = {
	initialFocused: boolean?,
	onChanged: ((boolean) -> ())?,
	onFocused: (() -> ())?,
	onBlurred: ((boolean?) -> ())?,
}

export type FocusResult = {
	focused: boolean,
	setFocused: (boolean) -> (),
	eventHandlers: { [any]: (...any) -> () },
}

local function useFocus(options: FocusOptions?): FocusResult
	local initialFocused = if options ~= nil and options.initialFocused ~= nil
		then options.initialFocused == true
		else false
	local onChanged = useStableCallback(if options ~= nil then options.onChanged else nil)
	local onFocusedCallback = useStableCallback(if options ~= nil then options.onFocused else nil)
	local onBlurred = useStableCallback(if options ~= nil then options.onBlurred else nil)
	local focusedRef = React.useRef(initialFocused)
	local focused, setFocusedState = React.useState(initialFocused)

	local setFocused = React.useCallback(function(nextFocusedRaw: boolean)
		local nextFocused = nextFocusedRaw == true
		if focusedRef.current == nextFocused then
			return
		end

		focusedRef.current = nextFocused
		setFocusedState(nextFocused)
		onChanged(nextFocused)
		if nextFocused then
			onFocusedCallback()
		end
	end, { onChanged, onFocusedCallback })

	local onFocused = React.useCallback(function()
		setFocused(true)
	end, { setFocused })

	local onFocusLost = React.useCallback(function(_rbx: TextBox, enterPressed: boolean?)
		setFocused(false)
		onBlurred(enterPressed == true)
	end, { setFocused, onBlurred })

	return {
		focused = focused,
		setFocused = setFocused,
		eventHandlers = {
			[React.Event.Focused] = onFocused,
			[React.Event.FocusLost] = onFocusLost,
		},
	}
end

return useFocus
