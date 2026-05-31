--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
local SegmentIcon = require(script:FindFirstAncestor("game").Client.UI.core.components.SegmentIcon)
local SegmentMeter = require(script:FindFirstAncestor("game").Client.UI.core.components.SegmentMeter)

export type ManaSegment = {
	index: number,
	fillAlpha: number,
}

export type ManaMeterProps = {
	stars: { ManaSegment },
	starSize: UDim2,
	padding: UDim?,
	zIndex: number,
	hoverAlpha: number?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
}

local e: typeof(React.createElement) = React.createElement

local EMPTY_STAR_COLOR = Color3.fromRGB(24, 44, 75)
local FILLED_STAR_COLOR = Color3.fromRGB(133, 189, 255)

local function ManaStarItem(props: {
	star: ManaSegment,
	starSize: UDim2,
	zIndex: number,
	hoverAlpha: number,
})
	local fillAlpha = math.clamp(props.star.fillAlpha, 0, 1)
	local hoverAlpha = math.clamp(props.hoverAlpha, 0, 1)
	local fillTransparency = math.clamp((1 - fillAlpha) - (0.14 * hoverAlpha * fillAlpha), 0, 1)
	local scale = 1 + 0.03 * hoverAlpha

	return e(SegmentIcon, {
		icon = ImageIds.mana,
		size = props.starSize,
		layoutOrder = props.star.index,
		zIndex = props.zIndex,
		fillAlpha = fillAlpha,
		emptyColor = EMPTY_STAR_COLOR,
		fullColor = FILLED_STAR_COLOR,
		fullTransparency = fillTransparency,
		scale = scale,
	})
end

return function(props: ManaMeterProps): React.ReactNode
	return e(SegmentMeter, {
		segments = props.stars,
		size = UDim2.fromOffset(0, props.starSize.Y.Offset),
		segmentHeight = props.starSize.Y.Offset,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, 0, 1, -4),
		active = true,
		zIndex = props.zIndex,
		padding = props.padding,
		onMouseEnter = props.onMouseEnter,
		onMouseLeave = props.onMouseLeave,
		renderSegment = function(segment)
			return e(ManaStarItem, {
				star = segment :: any,
				starSize = props.starSize,
				zIndex = props.zIndex + 1,
				hoverAlpha = props.hoverAlpha or 0,
			})
		end,
	})
end
