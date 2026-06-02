--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local ImageIds = require(gameRoot.Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
local SegmentIcon = require(gameRoot.Client.UI.core.components.SegmentIcon)

export type BubbleProps = {
	index: number,
	fillAlpha: number,
	size: UDim2,
	zIndex: number,
}

local e: typeof(React.createElement) = React.createElement

local EMPTY_BUBBLE_COLOR = Color3.fromRGB(31, 60, 83)
local FILLED_BUBBLE_COLOR = Color3.fromRGB(189, 234, 255)

return function(props: BubbleProps)
	return e(SegmentIcon, {
		icon = ImageIds.bubble,
		size = props.size,
		layoutOrder = props.index,
		zIndex = props.zIndex,
		fillAlpha = math.clamp(props.fillAlpha, 0, 1),
		emptyColor = EMPTY_BUBBLE_COLOR,
		fullColor = FILLED_BUBBLE_COLOR,
	})
end
