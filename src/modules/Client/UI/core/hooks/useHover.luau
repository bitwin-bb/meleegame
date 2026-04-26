--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type HoverOptions = {
	initialHovered: boolean?,
	onChanged: ((boolean) -> ())?,
	onHoverStart: (() -> ())?,
	onHoverEnd: (() -> ())?,
}

export type HoverResult = {
	hovered: boolean,
	setHovered: (boolean) -> (),
	eventHandlers: { [any]: (...any) -> () },
}

local function useHover(options: HoverOptions?): HoverResult
	local initialHovered = if options ~= nil and options.initialHovered ~= nil
		then options.initialHovered == true
		else false
	local onChanged = useStableCallback(if options ~= nil then options.onChanged else nil)
	local onHoverStart = useStableCallback(if options ~= nil then options.onHoverStart else nil)
	local onHoverEnd = useStableCallback(if options ~= nil then options.onHoverEnd else nil)
	local hoveredRef = React.useRef(initialHovered)
	local hovered, setHoveredState = React.useState(initialHovered)

	local setHovered = React.useCallback(function(nextHoveredRaw: boolean)
		local nextHovered = nextHoveredRaw == true
		if hoveredRef.current == nextHovered then
			return
		end

		hoveredRef.current = nextHovered
		setHoveredState(nextHovered)
		onChanged(nextHovered)
		if nextHovered then
			onHoverStart()
		else
			onHoverEnd()
		end
	end, { onChanged, onHoverStart, onHoverEnd })

	local onMouseEnter = React.useCallback(function()
		setHovered(true)
	end, { setHovered })

	local onMouseLeave = React.useCallback(function()
		setHovered(false)
	end, { setHovered })

	return {
		hovered = hovered,
		setHovered = setHovered,
		eventHandlers = {
			[React.Event.MouseEnter] = onMouseEnter,
			[React.Event.MouseLeave] = onMouseLeave,
		},
	}
end

return useHover
