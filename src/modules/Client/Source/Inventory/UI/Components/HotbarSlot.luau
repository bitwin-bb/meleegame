local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemSlot = require("ItemSlot")
local React: any = require(ReplicatedStorage.Packages.React)
local useItemAppear: any = require("useItemAppear")

local HOTBAR_ITEM_ICON_SIZE = 32

export type HotbarSlotProps = {
	index: number,
	size: UDim2,
	image: string,
	tint: Color3,
	zIndex: number,
	active: boolean,
	selectable: boolean,
	scale: number,
	showKeyHint: boolean,
	itemIcon: string?,
	itemAmount: number,
	itemAppearEnabled: boolean?,
	itemAppearTrigger: any?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	onSecondaryInput: (() -> ())?,
	onInputBegan: ((GuiObject, InputObject) -> ())?,
	onActivated: (() -> ())?,
}

return function(props: HotbarSlotProps): React.ReactNode
	local itemHasReachedGoal, setItemHasReachedGoal = React.useState(false)
	local handleItemAppearComplete = React.useCallback(function()
		setItemHasReachedGoal(true)
	end, {})

	React.useEffect(function()
		setItemHasReachedGoal(false)
	end, { props.itemAppearEnabled, props.itemAppearTrigger, props.itemIcon })

	local shouldUseItemAppear = props.itemAppearEnabled == true
	local itemAppearScale = useItemAppear({
		enabled = shouldUseItemAppear,
		trigger = props.itemAppearTrigger,
		onComplete = handleItemAppearComplete,
	})
	local itemScale = if shouldUseItemAppear then itemAppearScale else 1
	local stackAmountAppearScale = useItemAppear({
		enabled = shouldUseItemAppear and itemHasReachedGoal and props.itemAmount > 1,
		trigger = props.itemAppearTrigger,
	})

	return React.createElement(ItemSlot, {
		buttonProps = {
			Size = props.size,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.image,
			ImageColor3 = props.tint,
			ImageTransparency = 0,
			LayoutOrder = props.index,
			ZIndex = props.zIndex,
			AutoButtonColor = false,
			Active = props.active,
			Selectable = props.selectable,
			[React.Event.MouseEnter] = props.onMouseEnter :: any,
			[React.Event.MouseLeave] = props.onMouseLeave :: any,
			[React.Event.MouseButton2Down] = props.onSecondaryInput :: any,
			[React.Event.InputBegan] = props.onInputBegan :: any,
			[React.Event.Activated] = props.onActivated :: any,
		},
		scale = props.scale,
		keyHintText = if props.showKeyHint then tostring(props.index) else nil,
		keyHintProps = {
			Size = UDim2.fromOffset(16, 14),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			Font = Enum.Font.PatrickHand,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(202, 235, 255),
			TextStrokeTransparency = 0.55,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex + 2,
		},
		amount = if props.itemAmount > 1 then props.itemAmount else nil,
		stackLabelProps = {
			size = UDim2.fromOffset(0, 0),
			automaticSize = Enum.AutomaticSize.XY,
			position = UDim2.new(1, -6, 1, -5),
			anchorPoint = Vector2.new(1, 1),
			font = Enum.Font.PatrickHand,
			textSize = if shouldUseItemAppear then 13 * stackAmountAppearScale else 13,
			textColor3 = Color3.fromRGB(248, 253, 255),
			textStrokeColor3 = Color3.fromRGB(0, 0, 0),
			textStrokeTransparency = 0.3,
			textXAlignment = Enum.TextXAlignment.Right,
			textYAlignment = Enum.TextYAlignment.Bottom,
			zIndex = props.zIndex + 3,
		},
		icon = props.itemIcon,
		iconProps = {
			size = UDim2.fromOffset(HOTBAR_ITEM_ICON_SIZE * itemScale, HOTBAR_ITEM_ICON_SIZE * itemScale),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			imageColor3 = Color3.fromRGB(255, 255, 255),
			imageTransparency = 0,
			zIndex = props.zIndex + 2,
		},
	})
end
