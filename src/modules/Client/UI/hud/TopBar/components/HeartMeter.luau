--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
local SegmentMeter = require(script:FindFirstAncestor("game").Client.UI.core.components.SegmentMeter)
local useBeatMotion = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useBeatMotion)

export type HeartSegment = {
	index: number,
	health: number,
	fillAlpha: number,
	isEmpty: boolean,
}

export type HeartMeterProps = {
	hearts: { HeartSegment },
	heartSize: UDim2,
	padding: UDim?,
	zIndex: number,
	useLifeFruitHearts: boolean?,
	beatHeartIndex: number?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
}

local e: typeof(React.createElement) = React.createElement

local EMPTY_HEART_COLOR = Color3.fromRGB(59, 25, 29)
local FILLED_HEART_COLOR = Color3.fromRGB(255, 90, 118)
local EMPTY_LIFE_FRUIT_HEART_COLOR = Color3.fromRGB(52, 78, 28)
local FILLED_LIFE_FRUIT_HEART_COLOR = Color3.fromRGB(255, 255, 255)

local function HeartItem(props: {
	heart: HeartSegment,
	heartSize: UDim2,
	heartImage: string,
	emptyColor: Color3,
	filledColor: Color3,
	zIndex: number,
	isBeating: boolean,
})
	local heart = props.heart
	local beatMotion = useBeatMotion({
		enabled = props.isBeating,
		auto = true,
		bpm = 72,
		baseScale = 1,
		primaryScale = 1.08,
		secondaryScale = 1.04,
	})
	local fillAlpha = math.clamp(heart.fillAlpha, 0, 1)
	local heartColor = if heart.isEmpty then props.emptyColor else props.filledColor

	return e("Frame", {
		Size = props.heartSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = heart.index,
		ZIndex = props.zIndex,
	}, {
		e("UIScale", {
			Scale = beatMotion.scale,
		}),
		e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = props.heartImage,
			ImageColor3 = props.emptyColor,
			ImageTransparency = 0,
			ZIndex = props.zIndex + 1,
		}),
		e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = props.heartImage,
			ImageColor3 = heartColor,
			ImageTransparency = 1 - fillAlpha,
			ZIndex = props.zIndex + 2,
		}),
	})
end

return function(props: HeartMeterProps): React.ReactNode
	local useLifeFruitHearts = props.useLifeFruitHearts == true
	local heartImage = if useLifeFruitHearts
		then if typeof((ImageIds :: any).lifeFruitHeart) == "string" and (ImageIds :: any).lifeFruitHeart ~= ""
			then (ImageIds :: any).lifeFruitHeart
			else ImageIds.heartLifeFruit
		else ImageIds.normalHeart
	local emptyHeartColor = if useLifeFruitHearts then EMPTY_LIFE_FRUIT_HEART_COLOR else EMPTY_HEART_COLOR
	local filledHeartColor = if useLifeFruitHearts then FILLED_LIFE_FRUIT_HEART_COLOR else FILLED_HEART_COLOR

	return e(SegmentMeter, {
		segments = props.hearts,
		size = UDim2.fromOffset(0, props.heartSize.Y.Offset),
		segmentHeight = props.heartSize.Y.Offset,
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, 0, 1, -4),
		active = true,
		zIndex = props.zIndex,
		padding = props.padding,
		onMouseEnter = props.onMouseEnter,
		onMouseLeave = props.onMouseLeave,
		renderSegment = function(segment)
			local heart = segment :: any
			return e(HeartItem, {
				heart = heart,
				heartSize = props.heartSize,
				heartImage = heartImage,
				emptyColor = emptyHeartColor,
				filledColor = filledHeartColor,
				zIndex = props.zIndex + 1,
				isBeating = props.beatHeartIndex ~= nil and heart.index == props.beatHeartIndex,
			})
		end,
	})
end
