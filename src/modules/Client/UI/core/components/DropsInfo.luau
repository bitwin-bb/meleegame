local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local e: typeof(React.createElement) = React.createElement

export type DropsInfoRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type DropsInfoTheme = {
	backgroundColor: Color3?,
	backgroundTransparency: number?,
	strokeColor: Color3?,
	strokeTransparency: number?,
	accentColor: Color3?,
	titleColor: Color3?,
	titleTransparency: number?,
	subtitleColor: Color3?,
	subtitleTransparency: number?,
	descriptionColor: Color3?,
	descriptionTransparency: number?,
	amountColor: Color3?,
	amountTransparency: number?,
	iconColor: Color3?,
	iconTransparency: number?,
	glowColor: Color3?,
	gradientColor: ColorSequence?,
	gradientTransparency: NumberSequence?,
}

export type DropsInfoProps = {
	name: string?,
	adornee: Instance?,
	portalTarget: Instance?,
	disablePortal: boolean?,
	playerToHideFrom: Player?,
	enabled: boolean?,
	visible: boolean?,
	active: boolean?,
	alwaysOnTop: boolean?,
	resetOnSpawn: boolean?,
	clipsDescendants: boolean?,
	zIndexBehavior: Enum.ZIndexBehavior?,
	displayOrder: number?,
	zIndex: number?,
	billboardSize: UDim2?,
	maxDistance: number?,
	lightInfluence: number?,
	studsOffset: Vector3?,
	studsOffsetWorldSpace: Vector3?,
	extentsOffset: Vector3?,
	cardSize: UDim2?,
	cardAutomaticSize: Enum.AutomaticSize?,
	cardPosition: UDim2?,
	cardAnchorPoint: Vector2?,
	cardCornerRadius: UDim?,
	cardPadding: UDim?,
	contentPadding: UDim?,
	strokeThickness: number?,
	icon: string?,
	iconSize: UDim2?,
	title: string?,
	subtitle: string?,
	description: string?,
	amount: number?,
	amountText: string?,
	amountPrefix: string?,
	rarity: DropsInfoRarity?,
	showIcon: boolean?,
	showAmount: boolean?,
	showRarityPill: boolean?,
	textOnly: boolean?,
	theme: DropsInfoTheme?,
	titleFont: Enum.Font?,
	subtitleFont: Enum.Font?,
	descriptionFont: Enum.Font?,
	amountFont: Enum.Font?,
	titleTextSize: number?,
	subtitleTextSize: number?,
	descriptionTextSize: number?,
	amountTextSize: number?,
	animationEnabled: boolean?,
	paused: boolean?,
	lifetime: number?,
	fadeInTime: number?,
	fadeOutTime: number?,
	floatAmplitude: number?,
	floatSpeed: number?,
	pulseScaleAmplitude: number?,
	pulseSpeed: number?,
	gradientEnabled: boolean?,
	gradientScrollSpeed: number?,
	removeOnExpire: boolean?,
	eventToken: any?,
	onExpire: (() -> ())?,
	onAnimationStep: ((elapsed: number, alpha: number) -> ())?,
	nativeBillboard: { [string]: any }?,
	nativeCard: { [string]: any }?,
	nativeTitle: { [string]: any }?,
	nativeSubtitle: { [string]: any }?,
	nativeDescription: { [string]: any }?,
	nativeAmount: { [string]: any }?,
	nativeIcon: { [string]: any }?,
	children: { [string]: React.ReactNode }?,
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type DropsInfoState = {
	expired: boolean,
}

local DEFAULT_BILLBOARD_SIZE = UDim2.fromOffset(320, 124)
local DEFAULT_CARD_SIZE = UDim2.fromOffset(268, 72)
local DEFAULT_CARD_POSITION = UDim2.new(0.5, 0, 1, 0)
local DEFAULT_CARD_ANCHOR_POINT = Vector2.new(0.5, 1)
local DEFAULT_STUDS_OFFSET = Vector3.new(0, 3.1, 0)
local DEFAULT_EXTENTS_OFFSET = Vector3.new(0, 0, 0)
local DEFAULT_STUDS_OFFSET_WORLD = Vector3.new(0, 0, 0)
local DEFAULT_MAX_DISTANCE = 130
local DEFAULT_LIGHT_INFLUENCE = 0
local DEFAULT_FADE_IN_TIME = 0.16
local DEFAULT_FADE_OUT_TIME = 0.22
local DEFAULT_LIFETIME = 2.6
local DEFAULT_FLOAT_AMPLITUDE = 2.8
local DEFAULT_FLOAT_SPEED = 1.2
local DEFAULT_PULSE_AMPLITUDE = 0.035
local DEFAULT_PULSE_SPEED = 2.1
local DEFAULT_GRADIENT_SCROLL_SPEED = 2.2
local DEFAULT_STROKE_THICKNESS = 1.3
local DEFAULT_CORNER_RADIUS = UDim.new(0, 11)
local DEFAULT_CARD_PADDING = UDim.new(0, 10)
local DEFAULT_CONTENT_PADDING = UDim.new(0, 10)

local DEFAULT_THEME = {
	backgroundColor = Color3.fromRGB(16, 20, 29),
	backgroundTransparency = 0.2,
	strokeColor = Color3.fromRGB(100, 119, 148),
	strokeTransparency = 0.22,
	accentColor = Color3.fromRGB(88, 198, 255),
	titleColor = Color3.fromRGB(246, 249, 255),
	titleTransparency = 0,
	subtitleColor = Color3.fromRGB(188, 203, 224),
	subtitleTransparency = 0.04,
	descriptionColor = Color3.fromRGB(164, 179, 205),
	descriptionTransparency = 0.08,
	amountColor = Color3.fromRGB(255, 255, 255),
	amountTransparency = 0,
	iconColor = Color3.fromRGB(235, 244, 255),
	iconTransparency = 0,
	glowColor = Color3.fromRGB(132, 208, 255),
	gradientColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(13, 17, 24)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(29, 38, 55)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 20, 29)),
	}),
	gradientTransparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.06),
		NumberSequenceKeypoint.new(1, 0.16),
	}),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(171, 177, 186),
	Uncommon = Color3.fromRGB(104, 223, 117),
	Rare = Color3.fromRGB(74, 163, 255),
	Epic = Color3.fromRGB(191, 105, 255),
	Legendary = Color3.fromRGB(255, 193, 79),
	Mythic = Color3.fromRGB(255, 94, 143),
}

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

local function sanitizeColor(value: any, fallback: Color3): Color3
	if typeof(value) ~= "Color3" then
		return fallback
	end
	return value
end

local function sanitizeVector3(value: any, fallback: Vector3): Vector3
	if typeof(value) ~= "Vector3" then
		return fallback
	end
	if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then
		return fallback
	end
	return value
end

local function sanitizeTransparency(value: any, fallback: number): number
	return sanitizeNumber(value, fallback, 0, 1)
end

local function sanitizeString(value: any, fallback: string): string
	if typeof(value) ~= "string" then
		return fallback
	end
	return value
end

local function withAlpha(baseTransparency: number, alpha: number): number
	local safeBase = math.clamp(baseTransparency, 0, 1)
	local safeAlpha = math.clamp(alpha, 0, 1)
	return 1 - ((1 - safeBase) * safeAlpha)
end

local function resolveRarityColor(rarity: DropsInfoRarity?): Color3?
	if rarity == nil then
		return nil
	end
	return (RARITY_COLORS :: any)[rarity]
end

local function applyNativeProps(targetProps: { [string]: any }, nativeProps: { [string]: any }?)
	if nativeProps == nil then
		return
	end

	for index, value in nativeProps do
		targetProps[index] = value
	end
end

local function formatCommas(value: number): string
	local absolute = math.abs(math.floor(value))
	local raw = tostring(absolute)
	local remainder = #raw % 3
	local groups = {}

	if remainder > 0 then
		table.insert(groups, string.sub(raw, 1, remainder))
	end

	local index = remainder + 1
	while index <= #raw do
		table.insert(groups, string.sub(raw, index, index + 2))
		index += 3
	end

	local formatted = table.concat(groups, ",")
	if value < 0 then
		return "-" .. formatted
	end
	return formatted
end

local function resolveAmountText(props: DropsInfoProps): string?
	if props.amountText ~= nil and props.amountText ~= "" then
		return props.amountText
	end

	if typeof(props.amount) == "number" then
		local amountPrefix = sanitizeString(props.amountPrefix, "+")
		local amountValue = math.floor(props.amount)
		return amountPrefix .. formatCommas(amountValue)
	end

	return nil
end

local DropsInfo = React.Component:extend("DropsInfo")

function DropsInfo:init()
	self.state = {
		expired = false,
	} :: DropsInfoState

	self.janitor = Janitor.new() :: JanitorClass
	self.elapsed = 0
	self.didExpire = false

	self.alphaBinding, self.setAlphaBinding = React.createBinding(0)
	self.scaleBinding, self.setScaleBinding = React.createBinding(1)
	self.floatOffsetBinding, self.setFloatOffsetBinding = React.createBinding(0)
	self.gradientOffsetBinding, self.setGradientOffsetBinding = React.createBinding(Vector2.new(0, 0))
	self.glowTransparencyBinding, self.setGlowTransparencyBinding = React.createBinding(1)

	self:resetAnimation(false)
end

function DropsInfo:didMount()
	local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		self:stepAnimation(deltaTime)
	end)
	self.janitor:GiveChore(connection)
end

function DropsInfo:willUnmount()
	self.janitor:Destroy()
end

function DropsInfo:didUpdate(previousProps: DropsInfoProps)
	if previousProps.eventToken ~= self.props.eventToken then
		self:resetAnimation(true)
	end

	if previousProps.visible == false and self.props.visible ~= false then
		self:resetAnimation(true)
	end

	if previousProps.paused == true and self.props.paused ~= true and self.state.expired then
		self:resetAnimation(true)
	end
end

function DropsInfo:ResetAnimation(clearExpiredState: boolean)
	self.elapsed = 0
	self.didExpire = false

	local animationEnabled = self.props.animationEnabled ~= false
	self.setAlphaBinding(if animationEnabled then 0 else 1)
	self.setScaleBinding(1)
	self.setFloatOffsetBinding(0)
	self.setGradientOffsetBinding(Vector2.new(0, 0))
	self.setGlowTransparencyBinding(1)

	if clearExpiredState and self.state.expired then
		self:setState({
			expired = false,
		})
	end
end

function DropsInfo:StepAnimation(deltaTime: number)
	if self.state.expired then
		return
	end

	local props: DropsInfoProps = self.props
	if props.visible == false or props.paused == true then
		return
	end

	self.elapsed += deltaTime

	local animationEnabled = props.animationEnabled ~= false
	local fadeInTime = sanitizeNumber(props.fadeInTime, DEFAULT_FADE_IN_TIME, 0, 10)
	local fadeOutTime = sanitizeNumber(props.fadeOutTime, DEFAULT_FADE_OUT_TIME, 0, 10)
	local lifetime = sanitizeNumber(props.lifetime, DEFAULT_LIFETIME, 0, 600)

	local alpha = 1
	if animationEnabled and fadeInTime > 0 then
		alpha = math.min(alpha, self.elapsed / fadeInTime)
	end

	if lifetime > 0 and fadeOutTime > 0 then
		local fadeOutStart = math.max(0, lifetime - fadeOutTime)
		if self.elapsed >= fadeOutStart then
			local fadeOutAlpha = 1 - ((self.elapsed - fadeOutStart) / fadeOutTime)
			alpha = math.min(alpha, fadeOutAlpha)
		end
	end
	alpha = math.clamp(alpha, 0, 1)

	self.setAlphaBinding(alpha)

	if animationEnabled then
		local floatAmplitude = sanitizeNumber(props.floatAmplitude, DEFAULT_FLOAT_AMPLITUDE, 0, 60)
		local floatSpeed = sanitizeNumber(props.floatSpeed, DEFAULT_FLOAT_SPEED, 0, 15)
		local pulseAmplitude = sanitizeNumber(props.pulseScaleAmplitude, DEFAULT_PULSE_AMPLITUDE, 0, 0.45)
		local pulseSpeed = sanitizeNumber(props.pulseSpeed, DEFAULT_PULSE_SPEED, 0, 24)
		local gradientScrollSpeed = sanitizeNumber(props.gradientScrollSpeed, DEFAULT_GRADIENT_SCROLL_SPEED, 0, 16)

		local wave = math.sin(self.elapsed * floatSpeed * math.pi * 2)
		self.setFloatOffsetBinding(-wave * floatAmplitude)

		local pulseWave = math.sin(self.elapsed * pulseSpeed * math.pi * 2)
		self.setScaleBinding(1 + (pulseWave * pulseAmplitude * alpha))

		local offsetWave = math.sin(self.elapsed * gradientScrollSpeed)
		self.setGradientOffsetBinding(Vector2.new(offsetWave * 0.34, 0))

		local glowWave = (math.sin(self.elapsed * 8.5) + 1) * 0.5
		local glowTransparency = 1 - ((0.12 + glowWave * 0.18) * alpha)
		self.setGlowTransparencyBinding(math.clamp(glowTransparency, 0, 1))
	else
		self.setFloatOffsetBinding(0)
		self.setScaleBinding(1)
		self.setGradientOffsetBinding(Vector2.new(0, 0))
		self.setGlowTransparencyBinding(withAlpha(0.8, alpha))
	end

	if props.onAnimationStep then
		props.onAnimationStep(self.elapsed, alpha)
	end

	if lifetime > 0 and self.elapsed >= lifetime and not self.didExpire then
		self.didExpire = true

		if props.onExpire then
			props.onExpire()
		end

		if props.removeOnExpire ~= false then
			self:setState({
				expired = true,
			})
		end
	end
end

function DropsInfo:ResolvePortalTarget(): Instance?
	if self.props.disablePortal == true then
		return nil
	end

	if self.props.portalTarget ~= nil then
		return self.props.portalTarget
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui and playerGui:IsA("PlayerGui") then
		return playerGui
	end

	return nil
end

function DropsInfo:render()
	local props: DropsInfoProps = self.props
	if props.visible == false or self.state.expired then
		return nil
	end

	local rarityColor = resolveRarityColor(props.rarity)
	local theme = props.theme or {}

	local accentColor = sanitizeColor(theme.accentColor, rarityColor or DEFAULT_THEME.accentColor)
	local backgroundColor = sanitizeColor(theme.backgroundColor, DEFAULT_THEME.backgroundColor)
	local backgroundTransparency = sanitizeTransparency(theme.backgroundTransparency, DEFAULT_THEME.backgroundTransparency)
	local strokeColor = sanitizeColor(theme.strokeColor, accentColor:Lerp(DEFAULT_THEME.strokeColor, 0.4))
	local strokeTransparency = sanitizeTransparency(theme.strokeTransparency, DEFAULT_THEME.strokeTransparency)
	local titleColor = sanitizeColor(theme.titleColor, accentColor:Lerp(DEFAULT_THEME.titleColor, 0.9))
	local titleTransparency = sanitizeTransparency(theme.titleTransparency, DEFAULT_THEME.titleTransparency)
	local subtitleColor = sanitizeColor(theme.subtitleColor, DEFAULT_THEME.subtitleColor)
	local subtitleTransparency = sanitizeTransparency(theme.subtitleTransparency, DEFAULT_THEME.subtitleTransparency)
	local descriptionColor = sanitizeColor(theme.descriptionColor, DEFAULT_THEME.descriptionColor)
	local descriptionTransparency = sanitizeTransparency(theme.descriptionTransparency, DEFAULT_THEME.descriptionTransparency)
	local amountColor = sanitizeColor(theme.amountColor, DEFAULT_THEME.amountColor)
	local amountTransparency = sanitizeTransparency(theme.amountTransparency, DEFAULT_THEME.amountTransparency)
	local iconColor = sanitizeColor(theme.iconColor, DEFAULT_THEME.iconColor)
	local iconTransparency = sanitizeTransparency(theme.iconTransparency, DEFAULT_THEME.iconTransparency)
	local glowColor = sanitizeColor(theme.glowColor, accentColor)
	local gradientColor = if theme.gradientColor ~= nil then theme.gradientColor else DEFAULT_THEME.gradientColor
	local gradientTransparency = if theme.gradientTransparency ~= nil
		then theme.gradientTransparency
		else DEFAULT_THEME.gradientTransparency

	local showIcon = props.showIcon ~= false and props.icon ~= nil and props.icon ~= ""
	local amountText = resolveAmountText(props)
	local showAmount = props.showAmount ~= false and amountText ~= nil
	local showRarityPill = props.showRarityPill == true and props.rarity ~= nil
	local showSubtitle = props.subtitle ~= nil and props.subtitle ~= ""
	local showDescription = props.description ~= nil and props.description ~= ""
	local useGradient = props.gradientEnabled ~= false
	local useTextOnly = props.textOnly == true

	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 30
	local rootPosition = props.cardPosition or DEFAULT_CARD_POSITION
	local rootAnchorPoint = props.cardAnchorPoint or DEFAULT_CARD_ANCHOR_POINT

	if useTextOnly then
		local textValue = sanitizeString(props.title, "")
		if textValue == "" then
			textValue = sanitizeString(props.subtitle, "")
		end
		if textValue == "" then
			textValue = sanitizeString(props.description, "")
		end
		if textValue == "" and amountText ~= nil then
			textValue = amountText
		end
		if textValue == "" then
			textValue = " "
		end

		local textPositionBinding = self.floatOffsetBinding:map(function(offsetY: number)
			return UDim2.new(
				rootPosition.X.Scale,
				rootPosition.X.Offset,
				rootPosition.Y.Scale,
				rootPosition.Y.Offset + math.floor(offsetY)
			)
		end)
		local textTransparencyBinding = self.alphaBinding:map(function(alpha: number)
			return withAlpha(titleTransparency, alpha)
		end)
		local textStrokeTransparencyBinding = self.alphaBinding:map(function(alpha: number)
			local strokeBaseTransparency = math.clamp(0.28 + titleTransparency * 0.72, 0, 1)
			return withAlpha(strokeBaseTransparency, alpha)
		end)

		local billboardProps: { [string]: any } = {
			Name = props.name or "DropsInfo",
			Enabled = props.enabled ~= false,
			Active = props.active == true,
			Adornee = props.adornee,
			AlwaysOnTop = props.alwaysOnTop ~= false,
			PlayerToHideFrom = props.playerToHideFrom,
			ResetOnSpawn = props.resetOnSpawn == true,
			ClipsDescendants = props.clipsDescendants == true,
			ZIndexBehavior = props.zIndexBehavior or Enum.ZIndexBehavior.Sibling,
			Size = props.billboardSize or DEFAULT_BILLBOARD_SIZE,
			MaxDistance = sanitizeNumber(props.maxDistance, DEFAULT_MAX_DISTANCE, 0, 20000),
			LightInfluence = sanitizeNumber(props.lightInfluence, DEFAULT_LIGHT_INFLUENCE, 0, 1),
			StudsOffset = sanitizeVector3(props.studsOffset, DEFAULT_STUDS_OFFSET),
			StudsOffsetWorldSpace = sanitizeVector3(props.studsOffsetWorldSpace, DEFAULT_STUDS_OFFSET_WORLD),
			ExtentsOffset = sanitizeVector3(props.extentsOffset, DEFAULT_EXTENTS_OFFSET),
		}
		applyNativeProps(billboardProps, props.nativeBillboard)

		local billboardElement = e("BillboardGui", billboardProps, {
			TextRoot = e("Frame", {
				Name = "TextRoot",
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				Position = textPositionBinding,
				AnchorPoint = rootAnchorPoint,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 1,
			}, {
				Scale = e("UIScale", {
					Scale = self.scaleBinding,
				}),
				Text = e("TextLabel", {
					Name = "Text",
					AutomaticSize = Enum.AutomaticSize.XY,
					Size = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = props.titleFont or Enum.Font.GothamBlack,
					Text = textValue,
					TextColor3 = titleColor,
					TextSize = sanitizeNumber(props.titleTextSize, 28, 8, 80),
					TextTransparency = textTransparencyBinding,
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					TextStrokeTransparency = textStrokeTransparencyBinding,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextWrapped = false,
					ZIndex = zIndex + 3,
				}),
			}),
		})

		local portalTarget = self:resolvePortalTarget()
		if portalTarget ~= nil then
			return ReactRoblox.createPortal(billboardElement, portalTarget)
		end

		return billboardElement
	end

	local cardPositionBinding = self.floatOffsetBinding:map(function(offsetY: number)
		return UDim2.new(
			rootPosition.X.Scale,
			rootPosition.X.Offset,
			rootPosition.Y.Scale,
			rootPosition.Y.Offset + math.floor(offsetY)
		)
	end)

	local cardBackgroundTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(backgroundTransparency, alpha)
	end)
	local cardStrokeTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(strokeTransparency, alpha)
	end)
	local titleTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(titleTransparency, alpha)
	end)
	local subtitleTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(subtitleTransparency, alpha)
	end)
	local descriptionTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(descriptionTransparency, alpha)
	end)
	local amountTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(amountTransparency, alpha)
	end)
	local iconTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(iconTransparency, alpha)
	end)
	local rarityPillTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(0.2, alpha)
	end)
	local rarityTextTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(0.02, alpha)
	end)
	local cardShadowTransparencyBinding = self.alphaBinding:map(function(alpha: number)
		return withAlpha(0.36, alpha)
	end)

	local cardProps: { [string]: any } = {
		Name = "Card",
		Size = props.cardSize or DEFAULT_CARD_SIZE,
		AutomaticSize = props.cardAutomaticSize or Enum.AutomaticSize.None,
		Position = cardPositionBinding,
		AnchorPoint = rootAnchorPoint,
		BackgroundColor3 = backgroundColor,
		BackgroundTransparency = cardBackgroundTransparencyBinding,
		BorderSizePixel = 0,
		ZIndex = zIndex + 1,
	}
	applyNativeProps(cardProps, props.nativeCard)

	local titleProps: { [string]: any } = {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 21),
		BackgroundTransparency = 1,
		Font = props.titleFont or Enum.Font.GothamBold,
		Text = props.title or "Picked Up",
		TextColor3 = titleColor,
		TextSize = sanitizeNumber(props.titleTextSize, 17, 8, 48),
		TextTransparency = titleTransparencyBinding,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = zIndex + 4,
	}
	applyNativeProps(titleProps, props.nativeTitle)

	local subtitleProps: { [string]: any } = {
		Name = "Subtitle",
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = props.subtitleFont or Enum.Font.GothamSemibold,
		Text = props.subtitle or "",
		TextColor3 = subtitleColor,
		TextSize = sanitizeNumber(props.subtitleTextSize, 14, 8, 38),
		TextTransparency = subtitleTransparencyBinding,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = zIndex + 4,
	}
	applyNativeProps(subtitleProps, props.nativeSubtitle)

	local descriptionProps: { [string]: any } = {
		Name = "Description",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = props.descriptionFont or Enum.Font.Gotham,
		Text = props.description or "",
		TextColor3 = descriptionColor,
		TextSize = sanitizeNumber(props.descriptionTextSize, 12, 8, 34),
		TextTransparency = descriptionTransparencyBinding,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = zIndex + 4,
	}
	applyNativeProps(descriptionProps, props.nativeDescription)

	local amountProps: { [string]: any } = {
		Name = "Amount",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = accentColor,
		BackgroundTransparency = amountTransparencyBinding,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -6, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		Font = props.amountFont or Enum.Font.GothamBlack,
		Text = amountText or "",
		TextColor3 = amountColor,
		TextSize = sanitizeNumber(props.amountTextSize, 14, 8, 36),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex + 5,
	}
	applyNativeProps(amountProps, props.nativeAmount)

	local iconProps: { [string]: any } = {
		Name = "Icon",
		Size = props.iconSize or UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Image = props.icon or "",
		ImageColor3 = iconColor,
		ImageTransparency = iconTransparencyBinding,
		ZIndex = zIndex + 4,
	}
	applyNativeProps(iconProps, props.nativeIcon)

	local cardChildren: { [string]: React.ReactNode } = {
		Scale = e("UIScale", {
			Scale = self.scaleBinding,
		}),
		Corner = e("UICorner", {
			CornerRadius = props.cardCornerRadius or DEFAULT_CORNER_RADIUS,
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
			Thickness = sanitizeNumber(props.strokeThickness, DEFAULT_STROKE_THICKNESS, 0, 8),
			Transparency = cardStrokeTransparencyBinding,
		}),
		Shadow = e("Frame", {
			Name = "Shadow",
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromOffset(0, 2),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = cardShadowTransparencyBinding,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = props.cardCornerRadius or DEFAULT_CORNER_RADIUS,
			}),
		}),
		Padding = e("UIPadding", {
			PaddingTop = props.cardPadding or DEFAULT_CARD_PADDING,
			PaddingBottom = props.cardPadding or DEFAULT_CARD_PADDING,
			PaddingLeft = props.cardPadding or DEFAULT_CARD_PADDING,
			PaddingRight = props.cardPadding or DEFAULT_CARD_PADDING,
		}),
		Content = e("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = zIndex + 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = props.contentPadding or DEFAULT_CONTENT_PADDING,
			}),
			Icon = if showIcon
				then e("Frame", {
					Name = "IconContainer",
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					ZIndex = zIndex + 3,
				}, {
					IconImage = e("ImageLabel", iconProps),
					IconGlow = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
						Color = glowColor,
						Thickness = 1.1,
						Transparency = self.glowTransparencyBinding,
					}),
				})
				else nil,
			TextStack = e("Frame", {
				Name = "TextStack",
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, if showIcon then -32 else 0, 0, 0),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				ZIndex = zIndex + 3,
			}, {
				List = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0, 1),
				}),
				Title = e("TextLabel", titleProps),
				Subtitle = if showSubtitle then e("TextLabel", subtitleProps) else nil,
				Description = if showDescription then e("TextLabel", descriptionProps) else nil,
			}),
		}),
	}

	if useGradient then
		cardChildren.Gradient = e("UIGradient", {
			Color = gradientColor,
			Transparency = gradientTransparency,
			Rotation = -8,
			Offset = self.gradientOffsetBinding,
		})
	end

	if showAmount then
		cardChildren.Amount = e("TextLabel", amountProps, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	end

	if showRarityPill and props.rarity ~= nil then
		cardChildren.Rarity = e("TextLabel", {
			Name = "Rarity",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = accentColor,
			BackgroundTransparency = rarityPillTransparencyBinding,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, -7),
			AnchorPoint = Vector2.new(0, 0),
			Font = Enum.Font.GothamSemibold,
			Text = props.rarity,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 12,
			TextTransparency = rarityTextTransparencyBinding,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 5,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingBottom = UDim.new(0, 2),
				PaddingLeft = UDim.new(0, 7),
				PaddingRight = UDim.new(0, 7),
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	end

	if props.children then
		for childName, childNode in props.children do
			cardChildren[childName] = childNode
		end
	end

	local billboardProps: { [string]: any } = {
		Name = props.name or "DropsInfo",
		Enabled = props.enabled ~= false,
		Active = props.active == true,
		Adornee = props.adornee,
		AlwaysOnTop = props.alwaysOnTop ~= false,
		PlayerToHideFrom = props.playerToHideFrom,
		ResetOnSpawn = props.resetOnSpawn == true,
		ClipsDescendants = props.clipsDescendants == true,
		ZIndexBehavior = props.zIndexBehavior or Enum.ZIndexBehavior.Sibling,
		Size = props.billboardSize or DEFAULT_BILLBOARD_SIZE,
		MaxDistance = sanitizeNumber(props.maxDistance, DEFAULT_MAX_DISTANCE, 0, 20000),
		LightInfluence = sanitizeNumber(props.lightInfluence, DEFAULT_LIGHT_INFLUENCE, 0, 1),
		StudsOffset = sanitizeVector3(props.studsOffset, DEFAULT_STUDS_OFFSET),
		StudsOffsetWorldSpace = sanitizeVector3(props.studsOffsetWorldSpace, DEFAULT_STUDS_OFFSET_WORLD),
		ExtentsOffset = sanitizeVector3(props.extentsOffset, DEFAULT_EXTENTS_OFFSET),
	}
	applyNativeProps(billboardProps, props.nativeBillboard)

	local billboardElement = e("BillboardGui", billboardProps, {
		Card = e("Frame", cardProps, cardChildren),
	})

	local portalTarget = self:resolvePortalTarget()
	if portalTarget ~= nil then
		return ReactRoblox.createPortal(billboardElement, portalTarget)
	end

	return billboardElement
end

DropsInfo.resetAnimation = DropsInfo.ResetAnimation
DropsInfo.stepAnimation = DropsInfo.StepAnimation
DropsInfo.resolvePortalTarget = DropsInfo.ResolvePortalTarget

return DropsInfo
