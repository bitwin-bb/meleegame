--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)

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
	return e("Frame", {
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.index,
		ZIndex = props.zIndex,
	}, {
		e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.bubble,
			ImageColor3 = EMPTY_BUBBLE_COLOR,
			ImageTransparency = 0,
			ZIndex = props.zIndex + 1,
		}),
		e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.bubble,
			ImageColor3 = FILLED_BUBBLE_COLOR,
			ImageTransparency = 1 - math.clamp(props.fillAlpha, 0, 1),
			ZIndex = props.zIndex + 2,
		}),
	})
end
