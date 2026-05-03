local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

export type NavButtonTheme = {
	backgroundColor: Color3,
	hoveredBackgroundColor: Color3,
	pressedBackgroundColor: Color3,
	selectedBackgroundColor: Color3,
	disabledBackgroundColor: Color3,
	textColor: Color3,
	disabledTextColor: Color3,
	iconColor: Color3,
	disabledIconColor: Color3,
	strokeColor: Color3,
	selectedStrokeColor: Color3,
}

export type NavButtonActivatePayload = {
	id: string,
	route: string,
	label: string?,
	selected: boolean,
	source: string,
	timestamp: number,
}

export type NavButtonProps = {
	id: string?,
	route: string?,
	label: string?,
	icon: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	disabled: boolean?,
	selected: boolean?,
	automaticSize: Enum.AutomaticSize?,
	textSize: number?,
	font: Enum.Font?,
	iconSize: UDim2?,
	iconColor3: Color3?,
	padding: UDim?,
	cornerRadius: UDim?,
	backgroundTransparency: number?,
	strokeTransparency: number?,
	theme: NavButtonTheme?,
	navigateEvent: BindableEvent?,
	onActivated: ((payload: NavButtonActivatePayload, inputObject: InputObject?) -> ())?,
	onHoverChanged: ((isHovered: boolean) -> ())?,
	onPressedChanged: ((isPressed: boolean) -> ())?,
}

local DEFAULT_THEME: NavButtonTheme = {
	backgroundColor = Color3.fromRGB(32, 40, 52),
	hoveredBackgroundColor = Color3.fromRGB(45, 55, 71),
	pressedBackgroundColor = Color3.fromRGB(57, 67, 86),
	selectedBackgroundColor = Color3.fromRGB(31, 80, 126),
	disabledBackgroundColor = Color3.fromRGB(24, 28, 35),
	textColor = Color3.fromRGB(238, 243, 252),
	disabledTextColor = Color3.fromRGB(129, 136, 147),
	iconColor = Color3.fromRGB(229, 236, 249),
	disabledIconColor = Color3.fromRGB(117, 124, 136),
	strokeColor = Color3.fromRGB(90, 102, 122),
	selectedStrokeColor = Color3.fromRGB(118, 204, 255),
}

local DEFAULT_SIZE = UDim2.fromOffset(180, 42)
local DEFAULT_ICON_SIZE = UDim2.fromOffset(20, 20)

type NavButtonState = {
	isHovered: boolean,
	isPressed: boolean,
}

local function isPressInput(inputObject: InputObject?): boolean
	if inputObject == nil then
		return false
	end

	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
		or inputObject.KeyCode == Enum.KeyCode.ButtonA
end

local function resolveInputSource(inputObject: InputObject?): string
	if inputObject == nil then
		return "unknown"
	end

	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		return "mouse"
	end

	if inputObject.UserInputType == Enum.UserInputType.Touch then
		return "touch"
	end

	if inputObject.UserInputType == Enum.UserInputType.Gamepad1 then
		return "gamepad"
	end

	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		return "keyboard"
	end

	return "unknown"
end

local NavButton = React.Component:extend("NavButton")

function NavButton:init()
	self.state = {
		isHovered = false,
		isPressed = false,
	} :: NavButtonState
end

function NavButton:UpdateHover(nextValue: boolean)
	self:setState({
		isHovered = nextValue,
	})

	local onHoverChanged = self.props.onHoverChanged
	if onHoverChanged then
		onHoverChanged(nextValue)
	end
end

function NavButton:UpdatePressed(nextValue: boolean)
	self:setState({
		isPressed = nextValue,
	})

	local onPressedChanged = self.props.onPressedChanged
	if onPressedChanged then
		onPressedChanged(nextValue)
	end
end

function NavButton:EmitActivated(inputObject: InputObject?)
	local props: NavButtonProps = self.props
	local isDisabled = props.disabled == true
	local isSelected = props.selected == true
	if isDisabled then
		return
	end

	local resolvedRoute = props.route or props.id or props.label or ""
	local payload: NavButtonActivatePayload = {
		id = props.id or resolvedRoute,
		route = resolvedRoute,
		label = props.label,
		selected = isSelected,
		source = resolveInputSource(inputObject),
		timestamp = os.clock(),
	}

	if props.onActivated then
		props.onActivated(payload, inputObject)
	end

	if props.navigateEvent then
		props.navigateEvent:Fire(payload)
	end
end

function NavButton:render()
	local props: NavButtonProps = self.props
	local state: NavButtonState = self.state

	local theme = props.theme or DEFAULT_THEME
	local isDisabled = props.disabled == true
	local isSelected = props.selected == true
	local hasLabel = props.label ~= nil and props.label ~= ""
	local hasIcon = props.icon ~= nil and props.icon ~= ""

	local backgroundColor = theme.backgroundColor
	if isDisabled then
		backgroundColor = theme.disabledBackgroundColor
	elseif isSelected then
		backgroundColor = theme.selectedBackgroundColor
	elseif state.isPressed then
		backgroundColor = theme.pressedBackgroundColor
	elseif state.isHovered then
		backgroundColor = theme.hoveredBackgroundColor
	end

	local textColor = isDisabled and theme.disabledTextColor or theme.textColor
	local iconColor = props.iconColor3
		or (if isDisabled then theme.disabledIconColor else theme.iconColor)
	local strokeColor = isSelected and theme.selectedStrokeColor or theme.strokeColor
	local backgroundTransparency = if typeof(props.backgroundTransparency) == "number"
			and props.backgroundTransparency == props.backgroundTransparency
		then math.clamp(props.backgroundTransparency, 0, 1)
		else 0
	local strokeTransparency = if typeof(props.strokeTransparency) == "number" and props.strokeTransparency
			== props.strokeTransparency
		then math.clamp(props.strokeTransparency, 0, 1)
		else (if isDisabled then 0.45 else 0.15)

	return e("ImageButton", {
		Size = props.size or DEFAULT_SIZE,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		ZIndex = props.zIndex or 1,
		AutomaticSize = props.automaticSize,
		BackgroundColor3 = backgroundColor,
		BackgroundTransparency = backgroundTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not isDisabled,
		Selectable = not isDisabled,
		Image = "",
		[React.Event.MouseEnter] = function()
			if not isDisabled then
				self:updateHover(true)
			end
		end,
		[React.Event.MouseLeave] = function()
			self:updateHover(false)
			self:updatePressed(false)
		end,
		[React.Event.InputBegan] = function(_rbx: GuiObject, inputObject: InputObject)
			if isDisabled then
				return
			end

			if isPressInput(inputObject) then
				self:updatePressed(true)
			end
		end,
		[React.Event.InputEnded] = function(_rbx: GuiObject, inputObject: InputObject)
			if isPressInput(inputObject) then
				self:updatePressed(false)
			end
		end,
		[React.Event.Activated] = function(_rbx: GuiButton, inputObject: InputObject?)
			self:updatePressed(false)
			self:emitActivated(inputObject)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = props.cornerRadius or UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
			Thickness = isSelected and 2 or 1,
			Transparency = strokeTransparency,
		}),
		Content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = (props.zIndex or 1) + 1,
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = props.padding or UDim.new(0, 12),
				PaddingRight = props.padding or UDim.new(0, 12),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
			ListLayout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = hasLabel and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			Icon = if hasIcon
				then e("ImageLabel", {
					Size = props.iconSize or DEFAULT_ICON_SIZE,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					Image = props.icon,
					ImageColor3 = iconColor,
				})
				else nil,
			Label = if hasLabel
				then e("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
					Font = props.font or Enum.Font.GothamSemibold,
					Text = props.label or "",
					TextColor3 = textColor,
					TextSize = props.textSize or 16,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Center,
				})
				else nil,
		}),
	})
end

NavButton.updateHover = NavButton.UpdateHover
NavButton.updatePressed = NavButton.UpdatePressed
NavButton.emitActivated = NavButton.EmitActivated

return NavButton
