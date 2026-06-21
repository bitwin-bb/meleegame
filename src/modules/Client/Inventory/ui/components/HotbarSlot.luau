local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local ItemSlot = require("ItemSlot")
local React = require(ReplicatedStorage.Packages.React)

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
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	onSecondaryInput: (() -> ())?,
	onInputBegan: ((GuiObject, InputObject) -> ())?,
	onActivated: (() -> ())?,
}

return function(props: HotbarSlotProps): React.ReactNode
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
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Position = UDim2.new(1, -6, 1, -5),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.PatrickHand,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(248, 253, 255),
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			ZIndex = props.zIndex + 3,
		},
		icon = props.itemIcon,
		iconProps = {
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ImageTransparency = 0,
			ZIndex = props.zIndex + 2,
		},
	})
end
