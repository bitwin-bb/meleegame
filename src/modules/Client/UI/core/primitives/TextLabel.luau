--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

export type GradientEffect = {
	enabled: boolean?,
	color: ColorSequence?,
	transparency: NumberSequence?,
	rotation: number?,
	offset: Vector2?,
	animated: boolean?,
	scrollSpeed: number?,
	direction: Vector2?,
}

export type RainbowEffect = {
	enabled: boolean?,
	speed: number?,
	saturation: number?,
	value: number?,
	gradient: boolean?,
	spread: number?,
}

export type ShadowEffect = {
	enabled: boolean?,
	color: Color3?,
	transparency: number?,
	offset: Vector2?,
	layers: number?,
}

export type OutlineEffect = {
	enabled: boolean?,
	color: Color3?,
	transparency: number?,
	thickness: number?,
}

export type PulseEffect = {
	enabled: boolean?,
	speed: number?,
	minScale: number?,
	maxScale: number?,
}

export type TextEffects = {
	gradient: GradientEffect?,
	rainbow: RainbowEffect?,
	shadow: ShadowEffect?,
	outline: OutlineEffect?,
	pulse: PulseEffect?,
}

export type TextLabelProps = {
	text: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	automaticSize: Enum.AutomaticSize?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	backgroundColor3: Color3?,
	backgroundTransparency: number?,
	borderSizePixel: number?,
	clipsDescendants: boolean?,
	richText: boolean?,
	textScaled: boolean?,
	textWrapped: boolean?,
	textTruncate: Enum.TextTruncate?,
	maxVisibleGraphemes: number?,
	textXAlignment: Enum.TextXAlignment?,
	textYAlignment: Enum.TextYAlignment?,
	font: Enum.Font?,
	textSize: number?,
	lineHeight: number?,
	textColor3: Color3?,
	textTransparency: number?,
	textStrokeColor3: Color3?,
	textStrokeTransparency: number?,
	effects: TextEffects?,
	native: { [string]: any }?,
	children: { [string]: React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_TEXT_TRANSPARENCY = 0
local DEFAULT_BACKGROUND_TRANSPARENCY = 1
local DEFAULT_SIZE = UDim2.fromOffset(180, 24)
local DEFAULT_POSITION = UDim2.fromScale(0, 0)
local DEFAULT_ANCHOR_POINT = Vector2.new(0, 0)
local DEFAULT_Z_INDEX = 1
local DEFAULT_SHADOW_COLOR = Color3.fromRGB(0, 0, 0)

local DEFAULT_RAINBOW_SPEED = 0.2
local DEFAULT_RAINBOW_SATURATION = 0.95
local DEFAULT_RAINBOW_VALUE = 1
local DEFAULT_RAINBOW_SPREAD = 0.18

local DEFAULT_GRADIENT_SCROLL_SPEED = 0.4
local DEFAULT_GRADIENT_DIRECTION = Vector2.new(1, 0)
local DEFAULT_GRADIENT_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 220, 255)),
})

local DEFAULT_SHADOW_OFFSET = Vector2.new(2, 2)
local DEFAULT_SHADOW_LAYERS = 2
local DEFAULT_SHADOW_TRANSPARENCY = 0.55

local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(0, 0, 0)
local DEFAULT_OUTLINE_TRANSPARENCY = 0.15
local DEFAULT_OUTLINE_THICKNESS = 1

local DEFAULT_PULSE_SPEED = 1.25
local DEFAULT_PULSE_MIN_SCALE = 0.95
local DEFAULT_PULSE_MAX_SCALE = 1.05

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function sanitizeVector2(value: any, fallback: Vector2): Vector2
	if typeof(value) ~= "Vector2" then
		return fallback
	end
	if value.X ~= value.X or value.Y ~= value.Y then
		return fallback
	end
	return value
end

local function sanitizeColor(value: any, fallback: Color3): Color3
	if typeof(value) ~= "Color3" then
		return fallback
	end
	return value
end

local function normalizeDirection(direction: Vector2): Vector2
	local magnitude = direction.Magnitude
	if magnitude <= 1e-4 then
		return DEFAULT_GRADIENT_DIRECTION
	end
	return direction / magnitude
end

local function buildRainbowSequence(
	baseHue: number,
	saturation: number,
	value: number,
	spread: number
): ColorSequence
	local colorA = Color3.fromHSV((baseHue) % 1, saturation, value)
	local colorB = Color3.fromHSV((baseHue + spread) % 1, saturation, value)
	local colorC = Color3.fromHSV((baseHue + spread * 2) % 1, saturation, value)
	local colorD = Color3.fromHSV((baseHue + spread * 3) % 1, saturation, value)

	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorA),
		ColorSequenceKeypoint.new(0.33, colorB),
		ColorSequenceKeypoint.new(0.66, colorC),
		ColorSequenceKeypoint.new(1, colorD),
	})
end

local function TextLabel(props: TextLabelProps)
	local effects = props.effects
	local gradient = if effects then effects.gradient else nil
	local rainbow = if effects then effects.rainbow else nil
	local shadow = if effects then effects.shadow else nil
	local outline = if effects then effects.outline else nil
	local pulse = if effects then effects.pulse else nil

	local rainbowEnabled = rainbow ~= nil and rainbow.enabled ~= false
	local rainbowGradientEnabled = rainbowEnabled and rainbow.gradient == true
	local rainbowSpeed = sanitizeNumber(
		if rainbow then rainbow.speed else nil,
		DEFAULT_RAINBOW_SPEED,
		0,
		8
	)
	local rainbowSaturation = sanitizeNumber(
		if rainbow then rainbow.saturation else nil,
		DEFAULT_RAINBOW_SATURATION,
		0,
		1
	)
	local rainbowValue = sanitizeNumber(if rainbow then rainbow.value else nil, DEFAULT_RAINBOW_VALUE, 0, 1)
	local rainbowSpread = sanitizeNumber(if rainbow then rainbow.spread else nil, DEFAULT_RAINBOW_SPREAD, 0.01, 1)

	local gradientEnabled = gradient ~= nil and gradient.enabled ~= false
	local gradientAnimated = gradientEnabled and gradient ~= nil and gradient.animated == true
	local gradientScrollSpeed = sanitizeNumber(
		if gradient then gradient.scrollSpeed else nil,
		DEFAULT_GRADIENT_SCROLL_SPEED,
		0,
		8
	)
	local gradientDirection = normalizeDirection(
		sanitizeVector2(if gradient then gradient.direction else nil, DEFAULT_GRADIENT_DIRECTION)
	)
	local gradientRotation = sanitizeNumber(if gradient then gradient.rotation else nil, 0, -360, 360)
	local gradientTransparency = if gradient and gradient.transparency then gradient.transparency else nil
	local baseGradientOffset = sanitizeVector2(if gradient then gradient.offset else nil, Vector2.new(0, 0))
	local baseGradientColor = if gradient and gradient.color then gradient.color else DEFAULT_GRADIENT_COLOR

	local shadowEnabled = shadow ~= nil and shadow.enabled ~= false
	local shadowColor = sanitizeColor(if shadow then shadow.color else nil, DEFAULT_SHADOW_COLOR)
	local shadowOffset = sanitizeVector2(if shadow then shadow.offset else nil, DEFAULT_SHADOW_OFFSET)
	local shadowLayers = math.floor(sanitizeNumber(if shadow then shadow.layers else nil, DEFAULT_SHADOW_LAYERS, 1, 8))
	local shadowTransparency = sanitizeNumber(
		if shadow then shadow.transparency else nil,
		DEFAULT_SHADOW_TRANSPARENCY,
		0,
		1
	)

	local outlineEnabled = outline ~= nil and outline.enabled ~= false
	local outlineColor = sanitizeColor(if outline then outline.color else nil, DEFAULT_OUTLINE_COLOR)
	local outlineTransparency = sanitizeNumber(
		if outline then outline.transparency else nil,
		DEFAULT_OUTLINE_TRANSPARENCY,
		0,
		1
	)
	local outlineThickness = sanitizeNumber(if outline then outline.thickness else nil, DEFAULT_OUTLINE_THICKNESS, 1, 4)

	local pulseEnabled = pulse ~= nil and pulse.enabled == true
	local pulseSpeed = sanitizeNumber(if pulse then pulse.speed else nil, DEFAULT_PULSE_SPEED, 0, 12)
	local pulseMinScale = sanitizeNumber(if pulse then pulse.minScale else nil, DEFAULT_PULSE_MIN_SCALE, 0.01, 100)
	local pulseMaxScale = sanitizeNumber(if pulse then pulse.maxScale else nil, DEFAULT_PULSE_MAX_SCALE, 0.01, 100)

	local baseTextColor = sanitizeColor(props.textColor3, DEFAULT_TEXT_COLOR)
	local baseTextTransparency = sanitizeNumber(props.textTransparency, DEFAULT_TEXT_TRANSPARENCY, 0, 1)

	local animatedTextColor, setAnimatedTextColor = React.useBinding(baseTextColor)
	local animatedGradientOffset, setAnimatedGradientOffset = React.useBinding(baseGradientOffset)
	local animatedGradientColor, setAnimatedGradientColor = React.useBinding(baseGradientColor)
	local pulseScale, setPulseScale = React.useBinding(1)

	React.useEffect(function()
		setAnimatedTextColor(baseTextColor)
		setAnimatedGradientOffset(baseGradientOffset)
		setAnimatedGradientColor(baseGradientColor)
		setPulseScale(1)

		local isAnimating = rainbowEnabled or gradientAnimated or pulseEnabled
		if not isAnimating then
			return
		end

		local elapsed = 0
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			elapsed += deltaTime

			if rainbowEnabled then
				local hue = (elapsed * rainbowSpeed) % 1
				if rainbowGradientEnabled then
					setAnimatedGradientColor(buildRainbowSequence(hue, rainbowSaturation, rainbowValue, rainbowSpread))
				else
					setAnimatedTextColor(Color3.fromHSV(hue, rainbowSaturation, rainbowValue))
				end
			end

			if gradientAnimated then
				local shift = math.sin(elapsed * gradientScrollSpeed * math.pi * 2)
				local displacement = gradientDirection * shift
				setAnimatedGradientOffset(baseGradientOffset + displacement)
			end

			if pulseEnabled then
				local alpha = (math.sin(elapsed * pulseSpeed * math.pi * 2) + 1) * 0.5
				local scaleValue = pulseMinScale + (pulseMaxScale - pulseMinScale) * alpha
				setPulseScale(scaleValue)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {
		baseTextColor,
		baseGradientColor,
		baseGradientOffset,
		rainbowEnabled,
		rainbowGradientEnabled,
		rainbowSpeed,
		rainbowSaturation,
		rainbowValue,
		rainbowSpread,
		gradientAnimated,
		gradientScrollSpeed,
		gradientDirection,
		pulseEnabled,
		pulseSpeed,
		pulseMinScale,
		pulseMaxScale,
	})

	local resolvedTextColor = if rainbowEnabled and not rainbowGradientEnabled then animatedTextColor else baseTextColor
	local resolvedGradientColor = if rainbowEnabled and rainbowGradientEnabled then animatedGradientColor else baseGradientColor
	local resolvedGradientOffset = if gradientAnimated then animatedGradientOffset else baseGradientOffset

	local textCommonProps = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 0),
		AnchorPoint = Vector2.new(0, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		ClipsDescendants = false,
		Text = props.text or "",
		RichText = props.richText == true,
		Font = props.font or Enum.Font.GothamBold,
		TextSize = props.textSize or 16,
		TextScaled = props.textScaled == true,
		TextWrapped = props.textWrapped == true,
		TextTruncate = props.textTruncate,
		MaxVisibleGraphemes = props.maxVisibleGraphemes,
		TextXAlignment = props.textXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.textYAlignment or Enum.TextYAlignment.Center,
		LineHeight = props.lineHeight,
	}

	local children: { [string]: React.ReactNode } = {}

	if pulseEnabled then
		children.PulseScale = e("UIScale", {
			Scale = pulseScale,
		})
	end

	local rootZIndex = props.zIndex or DEFAULT_Z_INDEX
	local shadowZIndex = math.max(0, rootZIndex - 2)
	local outlineZIndex = math.max(0, rootZIndex - 1)

	if shadowEnabled then
		for layer = 1, shadowLayers do
			local alpha = layer / shadowLayers
			local layerOffset = shadowOffset * alpha
			local layerTransparency = math.clamp(
				shadowTransparency + (1 - alpha) * 0.2,
				0,
				1
			)

			children[`Shadow_{layer}`] = e("TextLabel", {
				ZIndex = shadowZIndex,
				TextColor3 = shadowColor,
				TextTransparency = layerTransparency,
				TextStrokeTransparency = 1,
				Position = UDim2.fromOffset(layerOffset.X, layerOffset.Y),
				Font = textCommonProps.Font,
				Text = textCommonProps.Text,
				TextSize = textCommonProps.TextSize,
				TextScaled = textCommonProps.TextScaled,
				TextWrapped = textCommonProps.TextWrapped,
				TextXAlignment = textCommonProps.TextXAlignment,
				TextYAlignment = textCommonProps.TextYAlignment,
				TextTruncate = textCommonProps.TextTruncate,
				MaxVisibleGraphemes = textCommonProps.MaxVisibleGraphemes,
				RichText = textCommonProps.RichText,
				LineHeight = textCommonProps.LineHeight,
				Size = textCommonProps.Size,
				BackgroundTransparency = textCommonProps.BackgroundTransparency,
				BorderSizePixel = textCommonProps.BorderSizePixel,
			})
		end
	end

	if outlineEnabled then
		local offset = math.max(1, math.floor(outlineThickness))
		local outlineOffsets = {
			Vector2.new(-offset, 0),
			Vector2.new(offset, 0),
			Vector2.new(0, -offset),
			Vector2.new(0, offset),
			Vector2.new(-offset, -offset),
			Vector2.new(-offset, offset),
			Vector2.new(offset, -offset),
			Vector2.new(offset, offset),
		}

		for index, outlineOffset in outlineOffsets do
			children[`Outline_{index}`] = e("TextLabel", {
				ZIndex = outlineZIndex,
				TextColor3 = outlineColor,
				TextTransparency = outlineTransparency,
				TextStrokeTransparency = 1,
				Position = UDim2.fromOffset(outlineOffset.X, outlineOffset.Y),
				Font = textCommonProps.Font,
				Text = textCommonProps.Text,
				TextSize = textCommonProps.TextSize,
				TextScaled = textCommonProps.TextScaled,
				TextWrapped = textCommonProps.TextWrapped,
				TextXAlignment = textCommonProps.TextXAlignment,
				TextYAlignment = textCommonProps.TextYAlignment,
				TextTruncate = textCommonProps.TextTruncate,
				MaxVisibleGraphemes = textCommonProps.MaxVisibleGraphemes,
				RichText = textCommonProps.RichText,
				LineHeight = textCommonProps.LineHeight,
				Size = textCommonProps.Size,
				BackgroundTransparency = textCommonProps.BackgroundTransparency,
				BorderSizePixel = textCommonProps.BorderSizePixel,
			})
		end
	end

	local rootProps = {
		Size = props.size or DEFAULT_SIZE,
		Position = props.position or DEFAULT_POSITION,
		AnchorPoint = props.anchorPoint or DEFAULT_ANCHOR_POINT,
		AutomaticSize = props.automaticSize,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		ZIndex = rootZIndex,
		BackgroundColor3 = props.backgroundColor3,
		BackgroundTransparency = sanitizeNumber(
			props.backgroundTransparency,
			DEFAULT_BACKGROUND_TRANSPARENCY,
			0,
			1
		),
		BorderSizePixel = if props.borderSizePixel ~= nil then props.borderSizePixel else 0,
		ClipsDescendants = if props.clipsDescendants ~= nil then props.clipsDescendants else false,
		Text = textCommonProps.Text,
		RichText = textCommonProps.RichText,
		Font = textCommonProps.Font,
		TextSize = textCommonProps.TextSize,
		TextScaled = textCommonProps.TextScaled,
		TextWrapped = textCommonProps.TextWrapped,
		TextTruncate = textCommonProps.TextTruncate,
		MaxVisibleGraphemes = textCommonProps.MaxVisibleGraphemes,
		TextXAlignment = textCommonProps.TextXAlignment,
		TextYAlignment = textCommonProps.TextYAlignment,
		LineHeight = textCommonProps.LineHeight,
		TextColor3 = resolvedTextColor,
		TextTransparency = baseTextTransparency,
		TextStrokeColor3 = props.textStrokeColor3,
		TextStrokeTransparency = props.textStrokeTransparency,
	}

	if props.native then
		for index, value in props.native do
			(rootProps :: any)[index] = value
		end
	end

	if gradientEnabled or rainbowGradientEnabled then
		children.Gradient = e("UIGradient", {
			Color = resolvedGradientColor,
			Offset = resolvedGradientOffset,
			Rotation = gradientRotation,
			Transparency = gradientTransparency,
		})
	end

	if props.children then
		for childName, child in props.children do
			children[childName] = child
		end
	end

	return e("TextLabel", rootProps, children)
end

return TextLabel
