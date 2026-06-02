--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local TransparentFrame = require(gameRoot.Client.UI.core.primitives.TransparentFrame)
local useHover = require(gameRoot.Client.UI.core.hooks.useHover)
local useTooltip = require(gameRoot.Client.UI.core.hooks.useTooltip)

export type TooltipAnchorProps = {
	id: string,
	text: string,
	enabled: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	show: ({ id: string, text: string }) -> (),
	hide: (string?) -> (),
	onHoverStart: (() -> ())?,
	children: { React.ReactNode }?,
}

return function(props: TooltipAnchorProps): React.ReactNode
	local hover = useHover({
		onHoverStart = props.onHoverStart,
	})

	useTooltip({
		id = props.id,
		text = props.text,
		enabled = props.enabled,
		hovered = hover.hovered,
		show = props.show,
		hide = props.hide,
	})

	return React.createElement(TransparentFrame, {
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		active = true,
		native = {
			[React.Event.MouseEnter] = hover.eventHandlers[React.Event.MouseEnter],
			[React.Event.MouseLeave] = hover.eventHandlers[React.Event.MouseLeave],
		},
		children = props.children,
	})
end
