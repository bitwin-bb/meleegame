local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NavButton = require("NavButton")
local React: any = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")

local e: typeof(React.createElement) = React.createElement

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
	local responsive = Responsive.useResponsiveMetrics()
	local hudTokens = responsive.tokens.hud
	local buttons = props.buttons or ({} :: any)
	local zIndex = props.zIndex or 10
	local children = {
		e("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = props.padding or UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, button in ipairs(buttons) do
		children[#children + 1] = e(NavButton, {
			id = button.id,
			route = button.route,
			label = button.label,
			icon = button.icon,
			size = button.size or UDim2.fromOffset(hudTokens.navButtonWidth, hudTokens.navButtonHeight),
			layoutOrder = button.layoutOrder or index,
			visible = button.visible,
			selected = button.selected,
			disabled = button.disabled,
			textSize = button.textSize or hudTokens.navButtonTextSize,
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
		Size = props.size or UDim2.new(1, 0, 0, hudTokens.bottomBarHeight + responsive.safeArea.bottom),
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
		e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			Selectable = false,
			ZIndex = zIndex,
		}, {
			e("UIPadding", {
				PaddingTop = UDim.new(0, 0),
				PaddingBottom = UDim.new(0, responsive.safeArea.bottom),
				PaddingLeft = UDim.new(0, responsive.safeArea.left),
				PaddingRight = UDim.new(0, responsive.safeArea.right),
			}),
			e("Frame", {
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
