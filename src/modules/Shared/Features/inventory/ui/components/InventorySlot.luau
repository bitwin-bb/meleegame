--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemSlot = require(script:FindFirstAncestor("game").Client.UI.core.components.ItemSlot)
local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

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
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Position = UDim2.new(1, -5, 1, -4),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = Color3.fromRGB(248, 253, 255),
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				TextTransparency = props.stackTextTransparency,
				TextStrokeTransparency = props.stackStrokeTransparency,
				ZIndex = props.zIndex + 1,
			},
			icon = props.itemIcon,
			iconProps = {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				ImageTransparency = props.itemTransparency,
				ZIndex = props.zIndex + 1,
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
