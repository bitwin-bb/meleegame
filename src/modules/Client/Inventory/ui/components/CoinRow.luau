local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local CoinSprites = require("CoinSprites")
local Gif = require("Gif")
local React = require(ReplicatedStorage.Packages.React)
local formatNumber = require("formatNumber")

export type CoinRowItem = {
	id: string,
	amount: number,
	spriteSheetImage: string,
	hoverId: string,
	hoverText: string,
	layoutOrder: number,
}

export type CoinRowProps = {
	coins: { CoinRowItem },
	slotWidth: number,
	slotHeight: number,
	iconTop: number,
	iconSize: number,
	amountTop: number,
	amountHeight: number,
	emergeTransparency: number,
	zIndex: number,
	onHoverStart: (CoinRowItem) -> (),
	onHoverEnd: (CoinRowItem) -> (),
}

local e: typeof(React.createElement) = React.createElement
local COIN_TEXT_STROKE_TRANSPARENCY = 0.2

return function(props: CoinRowProps): React.ReactNode
	local children: { React.ReactNode } = {
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
		}),
	}

	for _, coin in props.coins do
		children[#children + 1] = e("ImageButton", {
			Size = UDim2.fromOffset(props.slotWidth, props.slotHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			ImageTransparency = 1,
			LayoutOrder = coin.layoutOrder,
			ZIndex = props.zIndex + 1,
			[React.Event.MouseEnter] = function()
				props.onHoverStart(coin)
			end,
			[React.Event.MouseLeave] = function()
				props.onHoverEnd(coin)
			end,
		}, {
			e(Gif, {
				image = coin.spriteSheetImage,
				frameSize = CoinSprites.frameSize,
				frameCount = CoinSprites.frameCount,
				columns = CoinSprites.columns,
				startFrameIndex = 0,
				fps = CoinSprites.fps,
				size = UDim2.fromOffset(props.iconSize, props.iconSize),
				position = UDim2.new(0.5, 0, 0, props.iconTop),
				anchorPoint = Vector2.new(0.5, 0),
				backgroundTransparency = 1,
				imageTransparency = props.emergeTransparency,
				zIndex = props.zIndex + 2,
				resampleMode = Enum.ResamplerMode.Pixelated,
			}),
			e("TextLabel", {
				Size = UDim2.fromOffset(props.slotWidth, props.amountHeight),
				Position = UDim2.new(0.5, 0, 0, props.amountTop),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Text = formatNumber(coin.amount),
				Font = Enum.Font.PatrickHand,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(248, 253, 255),
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				TextTransparency = props.emergeTransparency,
				TextStrokeTransparency = math.clamp(
					COIN_TEXT_STROKE_TRANSPARENCY + props.emergeTransparency * (1 - COIN_TEXT_STROKE_TRANSPARENCY),
					0,
					1
				),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = props.zIndex + 3,
			}),
		})
	end

	return e(React.Fragment, nil, children)
end
