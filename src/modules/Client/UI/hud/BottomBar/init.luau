local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NavButton = require(script:FindFirstAncestor("game").Client.UI.core.components.NavButton)
local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

local BOTTOM_BAR_HEIGHT = 56
local BOTTOM_BAR_EDGE_PADDING = 12

type BottomBarButton = {
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

type BottomBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	padding: UDim?,
	buttons: { BottomBarButton }?,
	navigateEvent: BindableEvent?,
	onButtonActivated: ((payload: any, inputObject: InputObject?, button: BottomBarButton) -> ())?,
}

return function(props: BottomBarProps)
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
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
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
		Size = props.size or UDim2.new(1, 0, 0, BOTTOM_BAR_HEIGHT + BOTTOM_BAR_EDGE_PADDING),
		Position = props.position or UDim2.fromScale(0.5, 1),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		LayoutOrder = props.layoutOrder or 4,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
	}, {
		BottomBarContent = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			Selectable = false,
			ZIndex = zIndex,
		}, {
			EdgePadding = e("UIPadding", {
				PaddingTop = UDim.new(0, 0),
				PaddingBottom = UDim.new(0, BOTTOM_BAR_EDGE_PADDING),
				PaddingLeft = UDim.new(0, BOTTOM_BAR_EDGE_PADDING),
				PaddingRight = UDim.new(0, BOTTOM_BAR_EDGE_PADDING),
			}),
			ButtonList = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Active = false,
				Selectable = false,
				ZIndex = zIndex,
			}, children),
		}),
	})
end
