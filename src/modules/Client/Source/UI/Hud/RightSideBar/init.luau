local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreathRoot = require("BreathRoot")
local BuffRoot = require("BuffRoot")
local ManaRoot = require("ManaRoot")
local NavButton = require("NavButton")
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")

local e: typeof(React.createElement) = React.createElement

type RightSideBarButton = {
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

type RightSideBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	padding: UDim?,
	buttons: { RightSideBarButton }?,
	navigateEvent: BindableEvent?,
	manaBarProps: { [string]: any }?,
	buffBarProps: { [string]: any }?,
	breathBarProps: { [string]: any }?,
	onButtonActivated: ((payload: any, inputObject: InputObject?, button: RightSideBarButton) -> ())?,
}

return function(props: RightSideBarProps)
	local responsive = Responsive.useResponsiveMetrics()
	local hudTokens = responsive.tokens.hud
	local meterTokens = responsive.tokens.meter
	local buttons = props.buttons or ({} :: any)
	local zIndex = props.zIndex or 10
	local buttonListChildren = {
		e("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = props.padding or UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, button in ipairs(buttons) do
		buttonListChildren[#buttonListChildren + 1] = e(NavButton, {
			id = button.id,
			route = button.route,
			label = button.label,
			icon = button.icon,
			size = button.size or UDim2.fromOffset(hudTokens.sideButtonWidth, hudTokens.navButtonHeight),
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

	local manaBarProps = {
		layoutOrder = 6,
		zIndex = zIndex + 1,
		position = UDim2.fromScale(1, 0),
		anchorPoint = Vector2.new(1, 0),
		size = UDim2.fromOffset(meterTokens.frameWidth, meterTokens.frameHeight),
		starSize = UDim2.fromOffset(meterTokens.segmentSize, meterTokens.segmentSize),
		padding = UDim.new(0, meterTokens.segmentGap),
		showValueLabel = not responsive.isCompactHud,
	}
	if props.manaBarProps ~= nil then
		for key, value in pairs(props.manaBarProps) do
			manaBarProps[key] = value
		end
	end

	local buffContainerHeight = if responsive.isCompactHud then 126 else 150
	local buffBarProps = {
		layoutOrder = 7,
		zIndex = zIndex + 1,
		position = UDim2.new(1, 0, 0, meterTokens.frameHeight + hudTokens.edgePadding),
		anchorPoint = Vector2.new(1, 0),
		size = UDim2.fromOffset(meterTokens.frameWidth, buffContainerHeight),
	}
	if props.buffBarProps ~= nil then
		for key, value in pairs(props.buffBarProps) do
			buffBarProps[key] = value
		end
	end

	local breathBarProps = {
		layoutOrder = 8,
		zIndex = zIndex + 1,
		position = UDim2.new(1, 0, 0, meterTokens.frameHeight + buffContainerHeight + (hudTokens.edgePadding * 2)),
		anchorPoint = Vector2.new(1, 0),
		size = UDim2.fromOffset(meterTokens.frameWidth, meterTokens.frameHeight),
		bubbleSize = UDim2.fromOffset(meterTokens.segmentSize, meterTokens.segmentSize),
		padding = UDim.new(0, meterTokens.segmentGap),
		showValueLabel = not responsive.isCompactHud,
	}
	if props.breathBarProps ~= nil then
		for key, value in pairs(props.breathBarProps) do
			breathBarProps[key] = value
		end
	end

	return e("Frame", {
		Size = props.size or UDim2.new(0, hudTokens.sideBarWidth + responsive.safeArea.right, 1, 0),
		Position = props.position or UDim2.fromScale(1, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		LayoutOrder = props.layoutOrder or 3,
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
				PaddingTop = UDim.new(0, responsive.safeArea.top + hudTokens.sideBarVerticalPadding),
				PaddingBottom = UDim.new(0, responsive.safeArea.bottom + hudTokens.sideBarVerticalPadding),
				PaddingLeft = UDim.new(0, 0),
				PaddingRight = UDim.new(0, responsive.safeArea.right),
			}),
			e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Active = false,
				Selectable = false,
				ZIndex = zIndex,
			}, buttonListChildren),
			e(ManaRoot, manaBarProps),
			e(BuffRoot, buffBarProps),
			e(BreathRoot, breathBarProps),
		}),
	})
end
