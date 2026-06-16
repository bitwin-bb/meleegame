local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local CoinSprites = require("CoinSprites")
local Gif = require("Gif")
local ImageIds = require("ImageIds")
local React = require(ReplicatedStorage.Packages.React)

export type IngredientSlotProps = {
	layoutOrder: number?,
	itemId: string,
	required: number,
	isSufficient: boolean,
	icon: string,
	size: UDim2,
	iconSize: UDim2,
	zIndex: number,
}

local e: typeof(React.createElement) = React.createElement

return function(props: IngredientSlotProps): React.ReactNode
	local coinSpriteSheet = CoinSprites.resolveSpriteSheet(props.itemId)

	return e("ImageLabel", {
		Size = props.size,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		Image = ImageIds.recipeIcon,
		ImageColor3 = if props.isSufficient then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(255, 207, 207),
		ZIndex = props.zIndex,
	}, {
		if coinSpriteSheet ~= nil
			then e(Gif, {
				image = coinSpriteSheet,
				frameSize = CoinSprites.frameSize,
				frameCount = CoinSprites.frameCount,
				columns = CoinSprites.columns,
				startFrameIndex = 0,
				fps = CoinSprites.fps,
				size = props.iconSize,
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				backgroundTransparency = 1,
				imageTransparency = 0,
				zIndex = props.zIndex + 1,
				resampleMode = Enum.ResamplerMode.Pixelated,
			})
			else e("ImageLabel", {
				Size = props.iconSize,
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = props.icon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = props.zIndex + 1,
			}),
		e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 10),
			Position = UDim2.new(1, -2, 1, -2),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Text = tostring(props.required),
			Font = Enum.Font.GothamBold,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if props.isSufficient then Color3.fromRGB(157, 239, 182) else Color3.fromRGB(248, 172, 172),
			TextStrokeTransparency = 0.55,
			ZIndex = props.zIndex + 2,
		}),
	})
end
