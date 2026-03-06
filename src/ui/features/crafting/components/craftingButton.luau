--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)

type CraftingButtonProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	disabled: boolean?,
	selected: boolean?,
	text: string?,
	textOffset: Vector2?,
	icon: string?,
	iconPressed: string?,
	onActivated: (() -> ())?,
	onHoldBegan: (() -> ())?,
	onHoldEnded: (() -> ())?,
}

local e: typeof(React.createElement) = React.createElement

local function isPrimaryInput(inputObject: InputObject): boolean
	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
end

return function(props: CraftingButtonProps): React.ReactNode
	local isPressed, setIsPressed = React.useState(false)
	local isDisabled = props.disabled == true
	local isSelected = props.selected == true
	local zIndex = props.zIndex or 20
	local baseIcon = if typeof(props.icon) == "string" and props.icon ~= "" then props.icon else ImageIds.craftButton
	local pressedIcon = if typeof(props.iconPressed) == "string" and props.iconPressed ~= ""
		then props.iconPressed
		else (ImageIds.craftButtonPressed or ImageIds.craftingIconPress or baseIcon)
	local image = if isPressed or isSelected then pressedIcon else baseIcon
	local text = if typeof(props.text) == "string" then props.text else nil
	local textOffset = if typeof(props.textOffset) == "Vector2" then props.textOffset else Vector2.zero

	return e("ImageButton", {
		Name = "CraftingButton",
		Size = props.size or UDim2.fromOffset(58, 58),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not isDisabled,
		Selectable = not isDisabled,
		Image = image,
		ImageTransparency = if isDisabled then 0.5 else 0,
		ZIndex = zIndex,
		[React.Event.InputBegan] = function(_rbx: GuiObject, inputObject: InputObject)
			if isDisabled or not isPrimaryInput(inputObject) then
				return
			end
			setIsPressed(true)
			if props.onHoldBegan ~= nil then
				props.onHoldBegan()
			end
		end,
		[React.Event.InputEnded] = function(_rbx: GuiObject, inputObject: InputObject)
			if not isPrimaryInput(inputObject) then
				return
			end
			setIsPressed(false)
			if props.onHoldEnded ~= nil then
				props.onHoldEnded()
			end
		end,
		[React.Event.MouseLeave] = function()
			if isPressed and props.onHoldEnded ~= nil then
				props.onHoldEnded()
			end
			setIsPressed(false)
		end,
		[React.Event.Activated] = function()
			if isDisabled or props.onActivated == nil then
				return
			end
			props.onActivated()
		end,
	}, {
		Label = if text ~= nil and text ~= ""
			then e("TextLabel", {
				Name = "Label",
				Size = UDim2.new(1, -6, 1, -6),
				Position = UDim2.new(0.5, textOffset.X, 0.5, textOffset.Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = text,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextStrokeTransparency = 0.25,
				ZIndex = zIndex + 1,
			})
			else nil,
	})
end
