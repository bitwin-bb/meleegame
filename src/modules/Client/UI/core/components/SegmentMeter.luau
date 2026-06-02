--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type SegmentState = {
	index: number,
	fillAlpha: number,
	isEmpty: boolean?,
	isFull: boolean?,
	[string]: any,
}

export type SegmentMeterProps = {
	segments: { SegmentState },
	renderSegment: (SegmentState) -> React.ReactNode,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	segmentHeight: number?,
	padding: UDim?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	active: boolean?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	children: { React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: SegmentMeterProps): React.ReactNode
	local children: { React.ReactNode } = {
		e("UIPadding", {
			PaddingTop = UDim.new(0, 0),
			PaddingBottom = UDim.new(0, 0),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = props.horizontalAlignment or Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = props.padding or UDim.new(0, 4),
		}),
	}

	for _, segment in ipairs(props.segments) do
		children[#children + 1] = props.renderSegment(segment)
	end

	if props.children ~= nil then
		for _, child in props.children do
			children[#children + 1] = child
		end
	end

	return e("Frame", {
		Size = props.size or UDim2.fromOffset(0, props.segmentHeight or 30),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = props.anchorPoint,
		Position = props.position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = props.active,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		[React.Event.MouseEnter] = props.onMouseEnter,
		[React.Event.MouseLeave] = props.onMouseLeave,
	}, children)
end
