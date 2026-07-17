local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ease = require("Ease")
local React: any = require(ReplicatedStorage.Packages.React)

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
local DEFAULT_NORMAL_SCALE = 1
local DEFAULT_HOVERED_SCALE = 1.06
local DEFAULT_PRESSED_SCALE = 0.96
local DEFAULT_SELECTED_SCALE = 1.08
local DEFAULT_SCALE_ANIMATION_TIME = 0.16
local SCALE_EPSILON = 0.001

type NavButtonState = {
	isHovered: boolean,
	isPressed: boolean,
	renderScale: number,
}

type ScaleAnimation = {
	fromScale: number,
	toScale: number,
	startedAt: number,
	duration: number,
}

local function isPressInput(inputObject: InputObject?): boolean
	if inputObject == nil then
		return false
	end

	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
		or inputObject.KeyCode == Enum.KeyCode.ButtonA
end

local function getInputSource(inputObject: InputObject?): string
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

local function coerceScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return fallback
	end
	return valueRaw
end

local function getScaleTarget(props: NavButtonProps, state: NavButtonState?): number
	if props.disabled == true then
		return DEFAULT_NORMAL_SCALE
	end

	if state ~= nil and state.isPressed then
		return DEFAULT_PRESSED_SCALE
	end

	if props.selected == true then
		return DEFAULT_SELECTED_SCALE
	end

	if state ~= nil and state.isHovered then
		return DEFAULT_HOVERED_SCALE
	end

	return DEFAULT_NORMAL_SCALE
end

local NavButton = React.Component:extend("NavButton")

function NavButton:init()
	self.state = {
		isHovered = false,
		isPressed = false,
		renderScale = coerceScale(getScaleTarget(self.props, nil), DEFAULT_NORMAL_SCALE),
	} :: NavButtonState
	self.scaleTarget = self.state.renderScale
	self.scaleAnimation = nil :: ScaleAnimation?
	self.scaleConnection = nil :: RBXScriptConnection?
end

function NavButton:componentDidMount()
	self:SyncScaleTarget()
end

function NavButton:componentDidUpdate()
	self:SyncScaleTarget()
end

function NavButton:componentWillUnmount()
	if self.scaleConnection ~= nil then
		self.scaleConnection:Disconnect()
		self.scaleConnection = nil
	end
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

function NavButton:EnsureScaleLoop()
	if self.scaleConnection ~= nil then
		return
	end

	self.scaleConnection = RunService.RenderStepped:Connect(function()
		self:StepScaleAnimation()
	end)
end

function NavButton:StopScaleLoop()
	if self.scaleConnection == nil then
		return
	end

	self.scaleConnection:Disconnect()
	self.scaleConnection = nil
end

function NavButton:AnimateScaleTo(nextTarget: number)
	local currentScale = coerceScale(self.state.renderScale, DEFAULT_NORMAL_SCALE)
	if math.abs(currentScale - nextTarget) <= SCALE_EPSILON then
		self.scaleAnimation = nil
		self:StopScaleLoop()
		if math.abs(currentScale - nextTarget) > 0 then
			self:setState({
				renderScale = nextTarget,
			})
		end
		return
	end

	self.scaleAnimation = {
		fromScale = currentScale,
		toScale = nextTarget,
		startedAt = os.clock(),
		duration = DEFAULT_SCALE_ANIMATION_TIME,
	}
	self:EnsureScaleLoop()
end

function NavButton:SyncScaleTarget()
	local nextTarget = getScaleTarget(self.props, self.state)
	if self.scaleTarget ~= nil and math.abs(self.scaleTarget - nextTarget) <= SCALE_EPSILON then
		return
	end

	self.scaleTarget = nextTarget
	self:AnimateScaleTo(nextTarget)
end

function NavButton:StepScaleAnimation()
	local animation: ScaleAnimation? = self.scaleAnimation
	if animation == nil then
		self:StopScaleLoop()
		return
	end

	local alpha = math.clamp((os.clock() - animation.startedAt) / animation.duration, 0, 1)
	local nextScale = animation.toScale
	if alpha < 1 then
		local easedAlpha = Ease.OutBack(alpha)
		nextScale = animation.fromScale + (animation.toScale - animation.fromScale) * easedAlpha
	else
		self.scaleAnimation = nil
		self:StopScaleLoop()
	end

	if math.abs(coerceScale(self.state.renderScale, DEFAULT_NORMAL_SCALE) - nextScale) <= SCALE_EPSILON then
		return
	end

	self:setState({
		renderScale = nextScale,
	})
end

function NavButton:EmitActivated(inputObject: InputObject?)
	local props: NavButtonProps = self.props
	local isDisabled = props.disabled == true
	local isSelected = props.selected == true
	if isDisabled then
		return
	end

	local GotRoute = props.route or props.id or props.label or ""
	local payload: NavButtonActivatePayload = {
		id = props.id or GotRoute,
		route = GotRoute,
		label = props.label,
		selected = isSelected,
		source = getInputSource(inputObject),
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
	local iconColor = props.iconColor3 or (if isDisabled then theme.disabledIconColor else theme.iconColor)
	local strokeColor = isSelected and theme.selectedStrokeColor or theme.strokeColor
	local backgroundTransparency = if typeof(props.backgroundTransparency) == "number"
			and props.backgroundTransparency == props.backgroundTransparency
		then math.clamp(props.backgroundTransparency, 0, 1)
		else 0
	local strokeTransparency = if typeof(props.strokeTransparency) == "number"
			and props.strokeTransparency == props.strokeTransparency
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
				self:UpdateHover(true)
			end
		end,
		[React.Event.MouseLeave] = function()
			self:UpdateHover(false)
			self:UpdatePressed(false)
		end,
		[React.Event.InputBegan] = (function(_rbx: GuiObject, inputObject: InputObject)
			if isDisabled then
				return
			end

			if isPressInput(inputObject) then
				self:UpdatePressed(true)
			end
		end) :: any,
		[React.Event.InputEnded] = (function(_rbx: GuiObject, inputObject: InputObject)
			if isPressInput(inputObject) then
				self:UpdatePressed(false)
			end
		end) :: any,
		[React.Event.Activated] = (function(_rbx: GuiButton, inputObject: InputObject?)
			self:UpdatePressed(false)
			self:EmitActivated(inputObject)
		end) :: any,
	}, {
		e("UIScale", {
			Scale = state.renderScale,
		}),
		e("UICorner", {
			CornerRadius = props.cornerRadius or UDim.new(0, 10),
		}),
		e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
			Thickness = isSelected and 2 or 1,
			Transparency = strokeTransparency,
		}),
		e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = (props.zIndex or 1) + 1,
		}, {
			e("UIPadding", {
				PaddingLeft = props.padding or UDim.new(0, 12),
				PaddingRight = props.padding or UDim.new(0, 12),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
			e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = hasLabel and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			if hasIcon
				then e("ImageLabel", {
					Size = props.iconSize or DEFAULT_ICON_SIZE,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					Image = props.icon,
					ImageColor3 = iconColor,
				})
				else nil,
			if hasLabel
				then e("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
					Font = props.font or Enum.Font.PatrickHand,
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
return NavButton
