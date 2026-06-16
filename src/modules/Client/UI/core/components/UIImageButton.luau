local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local usePressState = require("usePressState")

export type ImageButtonProps = {
	image: string?,
	imagePressed: string?,
	imageHovered: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	disabled: boolean?,
	selected: boolean?,
	active: boolean?,
	selectable: boolean?,
	autoButtonColor: boolean?,
	backgroundTransparency: number?,
	imageTransparency: number?,
	imageColor3: Color3?,
	onActivated: ((GuiButton, InputObject?) -> ())?,
	onHoverChanged: ((boolean) -> ())?,
	onPressedChanged: ((boolean) -> ())?,
	children: { React.ReactNode }?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ImageButtonProps): React.ReactNode
	local disabled = props.disabled == true
	local pressState = usePressState({
		disabled = disabled,
		onHoverChanged = props.onHoverChanged,
		onPressedChanged = props.onPressedChanged,
	})
	local image = props.image or ""
	if (pressState.pressed or props.selected == true) and props.imagePressed ~= nil then
		image = props.imagePressed
	elseif pressState.hovered and props.imageHovered ~= nil then
		image = props.imageHovered
	end

	local buttonProps: { [any]: any } = {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		ZIndex = props.zIndex,
		BackgroundTransparency = if props.backgroundTransparency ~= nil then props.backgroundTransparency else 1,
		BorderSizePixel = 0,
		AutoButtonColor = if props.autoButtonColor ~= nil then props.autoButtonColor else false,
		Active = if props.active ~= nil then props.active else not disabled,
		Selectable = if props.selectable ~= nil then props.selectable else not disabled,
		Image = image,
		ImageColor3 = props.imageColor3,
		ImageTransparency = if disabled then 0.5 else props.imageTransparency,
		[React.Event.MouseEnter] = pressState.eventHandlers[React.Event.MouseEnter],
		[React.Event.MouseLeave] = pressState.eventHandlers[React.Event.MouseLeave],
		[React.Event.InputBegan] = pressState.eventHandlers[React.Event.InputBegan],
		[React.Event.InputEnded] = pressState.eventHandlers[React.Event.InputEnded],
		[React.Event.Activated] = function(rbx: GuiButton, inputObject: InputObject?)
			pressState.setPressed(false)
			if disabled or props.onActivated == nil then
				return
			end
			props.onActivated(rbx, inputObject)
		end,
	}

	if props.native ~= nil then
		for key, value in props.native do
			buttonProps[key] = value
		end
	end

	return e("ImageButton", buttonProps, props.children)
end
