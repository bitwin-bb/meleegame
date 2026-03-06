local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local NavButton = require(ReplicatedStorage.UI.core.components.NavButton)

local e: typeof(React.createElement) = React.createElement

type TopBarButton = {
	key: string?,
	id: string?,
	route: string?,
	label: string?,
	icon: string?,
	layoutOrder: number?,
	visible: boolean?,
	selected: boolean?,
	disabled: boolean?,
	size: UDim2?,
	textSize: number?,
	font: Enum.Font?,
	onActivated: ((payload: any, inputObject: InputObject?) -> ())?,
	navigateEvent: BindableEvent?,
}

type TopBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	padding: UDim?,
	buttons: { TopBarButton }?,
	navigateEvent: BindableEvent?,
	onButtonActivated: ((payload: any, inputObject: InputObject?, button: TopBarButton) -> ())?,
}

return function(props: TopBarProps)
	local buttons = props.buttons or {}
	local zIndex = props.zIndex or 10
	local children = {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = props.padding or UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, button in ipairs(buttons) do
		local key = button.key or button.id or button.route or tostring(index)
		children["Button_" .. key] = e(NavButton, {
			id = button.id,
			route = button.route,
			label = button.label,
			icon = button.icon,
			size = button.size or UDim2.fromOffset(170, 40),
			layoutOrder = button.layoutOrder or index,
			visible = button.visible,
			selected = button.selected,
			disabled = button.disabled,
			textSize = button.textSize,
			font = button.font,
			zIndex = zIndex + 1,
			navigateEvent = button.navigateEvent or props.navigateEvent,
			onActivated = function(payload: any, inputObject: InputObject?)
				if button.onActivated then
					button.onActivated(payload, inputObject)
				end

				if props.onButtonActivated then
					props.onButtonActivated(payload, inputObject, button)
				end
			end,
		})
	end

	return e("Frame", {
		Name = "TopBar",
		Size = props.size or UDim2.new(1, -24, 0, 56),
		Position = props.position or UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 1,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
	}, children)
end
