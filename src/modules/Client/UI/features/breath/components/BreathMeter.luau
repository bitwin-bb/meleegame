--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local SegmentMeter = require(script:FindFirstAncestor("game").Client.UI.core.components.SegmentMeter)
local bubbleComponent = require(script.Parent.bubble)

export type BreathSegment = {
	index: number,
	fillAlpha: number,
}

export type BreathMeterProps = {
	bubbles: { BreathSegment },
	fillAlphas: { number }?,
	bubbleSize: UDim2,
	padding: UDim?,
	zIndex: number,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BreathMeterProps): React.ReactNode
	return e(SegmentMeter, {
		segments = props.bubbles,
		size = UDim2.fromOffset(0, props.bubbleSize.Y.Offset),
		segmentHeight = props.bubbleSize.Y.Offset,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, 0, 1, -4),
		active = true,
		zIndex = props.zIndex,
		padding = props.padding,
		onMouseEnter = props.onMouseEnter,
		onMouseLeave = props.onMouseLeave,
		renderSegment = function(segment)
			local bubble = segment :: any
			local animatedFillAlpha = if props.fillAlphas ~= nil then props.fillAlphas[bubble.index] else nil
			return e(bubbleComponent, {
				index = bubble.index,
				fillAlpha = animatedFillAlpha or bubble.fillAlpha,
				size = props.bubbleSize,
				zIndex = props.zIndex + 1,
			})
		end,
	})
end
