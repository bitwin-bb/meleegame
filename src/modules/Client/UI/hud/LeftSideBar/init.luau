local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local NavButton = require(script:FindFirstAncestor("game").Client.UI.core.components.NavButton)
local InventoryHotbar = require(script:FindFirstAncestor("game").Client.UI.features.inventory.hud.inventoryHotbar)

local e: typeof(React.createElement) = React.createElement

type LeftSideBarButton = {
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

type LeftSideBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	padding: UDim?,
	buttons: { LeftSideBarButton }?,
	navigateEvent: BindableEvent?,
	inventoryHotbarProps: { [string]: any }?,
	onButtonActivated: ((payload: any, inputObject: InputObject?, button: LeftSideBarButton) -> ())?,
}

return function(props: LeftSideBarProps)
	local buttons = props.buttons or {}
	local zIndex = props.zIndex or 10
	local buttonListChildren = {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = props.padding or UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, button in ipairs(buttons) do
		local key = button.key or button.id or button.route or tostring(index)
		buttonListChildren["Button_" .. key] = e(NavButton, {
			id = button.id,
			route = button.route,
			label = button.label,
			icon = button.icon,
			size = button.size or UDim2.fromOffset(190, 40),
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

	local inventoryHotbarProps = {
		layoutOrder = 6,
		zIndex = zIndex + 1,
		position = UDim2.new(0, 4, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
	}
	if props.inventoryHotbarProps ~= nil then
		for key, value in pairs(props.inventoryHotbarProps) do
			inventoryHotbarProps[key] = value
		end
	end

	return e("Frame", {
		Name = "LeftSideBar",
		Size = props.size or UDim2.new(0, 220, 1, -144),
		Position = props.position or UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 2,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
	}, {
		ButtonList = e("Frame", {
			Name = "ButtonList",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, buttonListChildren),
		InventoryHotbar = e(InventoryHotbar, inventoryHotbarProps),
	})
end
