local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemSlot = require("ItemSlot")
local React: any = require(ReplicatedStorage.Packages.React)
local useItemAppear: any = require("useItemAppear")

local e: typeof(React.createElement) = React.createElement

local INVENTORY_ITEM_ICON_SIZE = 30

export type InventorySlotProps = {
	layoutOrder: number?,
	size: UDim2,
	position: UDim2,
	image: string,
	tint: Color3,
	imageTransparency: number,
	zIndex: number,
	active: boolean,
	selectable: boolean,
	itemIcon: string?,
	itemAmount: number,
	itemAppearEnabled: boolean?,
	itemAppearTrigger: any?,
	itemTransparency: number,
	stackTextTransparency: number,
	stackStrokeTransparency: number,
	selectedStrokeTransparency: number?,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	onSecondaryInput: (() -> ())?,
	onInputBegan: ((GuiObject, InputObject) -> ())?,
	onActivated: (() -> ())?,
}

return function(props: InventorySlotProps): React.ReactNode
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

	return e("Frame", {
		Size = props.size,
		Position = props.position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
	}, {
		e(ItemSlot, {
			buttonProps = {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = props.image,
				ImageColor3 = props.tint,
				ImageTransparency = props.imageTransparency,
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
			amount = if props.itemAmount > 1 then props.itemAmount else nil,
			stackLabelProps = {
				size = UDim2.fromOffset(0, 0),
				automaticSize = Enum.AutomaticSize.XY,
				position = UDim2.new(1, -5, 1, -4),
				anchorPoint = Vector2.new(1, 1),
				font = Enum.Font.PatrickHand,
				textSize = if shouldUseItemAppear then 11 * stackAmountAppearScale else 11,
				textColor3 = Color3.fromRGB(248, 253, 255),
				textStrokeColor3 = Color3.fromRGB(0, 0, 0),
				textTransparency = props.stackTextTransparency,
				textStrokeTransparency = props.stackStrokeTransparency,
				zIndex = props.zIndex + 1,
			},
			icon = props.itemIcon,
			iconProps = {
				size = UDim2.fromOffset(INVENTORY_ITEM_ICON_SIZE * itemScale, INVENTORY_ITEM_ICON_SIZE * itemScale),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				imageColor3 = Color3.fromRGB(255, 255, 255),
				imageTransparency = props.itemTransparency,
				zIndex = props.zIndex + 1,
			},
			strokeProps = if props.selectedStrokeTransparency ~= nil
				then {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Color3.fromRGB(128, 226, 255),
					Transparency = props.selectedStrokeTransparency,
					Thickness = 1.25,
				}
				else nil,
		}),
	})
end
