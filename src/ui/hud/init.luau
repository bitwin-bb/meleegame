local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local TopBar = require(ReplicatedStorage.UI.hud.TopBar)
local BottomBar = require(ReplicatedStorage.UI.hud.BottomBar)
local LeftSideBar = require(ReplicatedStorage.UI.hud.LeftSideBar)
local RightSideBar = require(ReplicatedStorage.UI.hud.RightSideBar)

local e: typeof(React.createElement) = React.createElement

type HudBarOrders = {
	top: number?,
	left: number?,
	right: number?,
	bottom: number?,
}

type HudProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	barOrders: HudBarOrders?,
	navigateEvent: BindableEvent?,
	topButtons: { any }?,
	bottomButtons: { any }?,
	leftButtons: { any }?,
	rightButtons: { any }?,
	hpBarProps: { [string]: any }?,
	manaBarProps: { [string]: any }?,
	inventoryHotbarProps: { [string]: any }?,
	onNavigate: ((barName: string, payload: any, inputObject: InputObject?, button: any) -> ())?,
}

local DEFAULT_BAR_ORDERS: HudBarOrders = {
	top = 1,
	left = 2,
	right = 3,
	bottom = 4,
}

return function(props: HudProps)
	local barOrders = props.barOrders or DEFAULT_BAR_ORDERS
	local baseZIndex = props.zIndex or 10

	return e("Frame", {
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 1,
		ZIndex = baseZIndex,
		Visible = props.visible ~= false,
	}, {
		TopBar = e(TopBar, {
			layoutOrder = barOrders.top or DEFAULT_BAR_ORDERS.top,
			zIndex = baseZIndex + 1,
			buttons = props.topButtons,
			navigateEvent = props.navigateEvent,
			onButtonActivated = function(payload: any, inputObject: InputObject?, button: any)
				if props.onNavigate then
					props.onNavigate("TopBar", payload, inputObject, button)
				end
			end,
		}),
		LeftSideBar = e(LeftSideBar, {
			layoutOrder = barOrders.left or DEFAULT_BAR_ORDERS.left,
			zIndex = baseZIndex + 1,
			buttons = props.leftButtons,
			navigateEvent = props.navigateEvent,
			inventoryHotbarProps = props.inventoryHotbarProps,
			onButtonActivated = function(payload: any, inputObject: InputObject?, button: any)
				if props.onNavigate then
					props.onNavigate("LeftSideBar", payload, inputObject, button)
				end
			end,
		}),
		RightSideBar = e(RightSideBar, {
			layoutOrder = barOrders.right or DEFAULT_BAR_ORDERS.right,
			zIndex = baseZIndex + 1,
			buttons = props.rightButtons,
			navigateEvent = props.navigateEvent,
			hpBarProps = props.hpBarProps,
			manaBarProps = props.manaBarProps,
			onButtonActivated = function(payload: any, inputObject: InputObject?, button: any)
				if props.onNavigate then
					props.onNavigate("RightSideBar", payload, inputObject, button)
				end
			end,
		}),
		BottomBar = e(BottomBar, {
			layoutOrder = barOrders.bottom or DEFAULT_BAR_ORDERS.bottom,
			zIndex = baseZIndex + 1,
			buttons = props.bottomButtons,
			navigateEvent = props.navigateEvent,
			onButtonActivated = function(payload: any, inputObject: InputObject?, button: any)
				if props.onNavigate then
					props.onNavigate("BottomBar", payload, inputObject, button)
				end
			end,
		}),
	})
end
