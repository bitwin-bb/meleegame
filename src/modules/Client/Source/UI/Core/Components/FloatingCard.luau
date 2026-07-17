local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React: any = require(ReplicatedStorage.Packages.React)

export type FloatingCardTheme = {
	backgroundColor: Color3?,
	backgroundTransparency: number?,
	strokeColor: Color3?,
	strokeTransparency: number?,
	strokeThickness: number?,
	titleColor: Color3?,
	subtitleColor: Color3?,
	bodyColor: Color3?,
	iconColor: Color3?,
}

export type FloatingCardProps = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	automaticSize: Enum.AutomaticSize?,
	visible: boolean?,
	active: boolean?,
	clipsDescendants: boolean?,
	zIndex: number?,
	backgroundColor: Color3?,
	backgroundTransparency: number?,
	strokeColor: Color3?,
	strokeTransparency: number?,
	strokeThickness: number?,
	cornerRadius: UDim?,
	padding: UDim?,
	paddingTop: UDim?,
	paddingBottom: UDim?,
	paddingLeft: UDim?,
	paddingRight: UDim?,
	scale: number?,
	title: string?,
	subtitle: string?,
	body: string?,
	icon: string?,
	iconSize: UDim2?,
	content: React.ReactNode?,
	theme: FloatingCardTheme?,
	native: { [any]: any }?,
	nativeTitle: { [any]: any }?,
	nativeSubtitle: { [any]: any }?,
	nativeBody: { [any]: any }?,
	nativeIcon: { [any]: any }?,
	children: { React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_BACKGROUND_COLOR = Color3.fromRGB(16, 20, 29)
local DEFAULT_STROKE_COLOR = Color3.fromRGB(100, 119, 148)
local DEFAULT_TEXT_COLOR = Color3.fromRGB(246, 249, 255)
local DEFAULT_SUBTLE_TEXT_COLOR = Color3.fromRGB(188, 203, 224)
local DEFAULT_BODY_COLOR = Color3.fromRGB(164, 179, 205)
local DEFAULT_PADDING = UDim.new(0, 10)
local DEFAULT_CORNER_RADIUS = UDim.new(0, 8)

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function coerceColor(valueRaw: any, fallback: Color3): Color3
	return if typeof(valueRaw) == "Color3" then valueRaw else fallback
end

local function applyNativeProps(target: { [any]: any }, nativeProps: { [any]: any }?)
	if nativeProps == nil then
		return
	end

	for key, value in nativeProps do
		target[key] = value
	end
end

local function addChildren(target: { [any]: React.ReactNode }, children: { React.ReactNode }?)
	if children == nil then
		return
	end

	for key, child in children do
		target[key] = child
	end
end

return function(props: FloatingCardProps): React.ReactNode
	local theme = props.theme or ({} :: any)
	local zIndex = props.zIndex or 1
	local backgroundColor = coerceColor(props.backgroundColor or theme.backgroundColor, DEFAULT_BACKGROUND_COLOR)
	local strokeColor = coerceColor(props.strokeColor or theme.strokeColor, DEFAULT_STROKE_COLOR)
	local titleColor = coerceColor(theme.titleColor, DEFAULT_TEXT_COLOR)
	local subtitleColor = coerceColor(theme.subtitleColor, DEFAULT_SUBTLE_TEXT_COLOR)
	local bodyColor = coerceColor(theme.bodyColor, DEFAULT_BODY_COLOR)
	local iconColor = coerceColor(theme.iconColor, DEFAULT_TEXT_COLOR)
	local padding = props.padding or DEFAULT_PADDING

	local frameProps: { [any]: any } = {
		Size = props.size or UDim2.fromOffset(220, 80),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		AutomaticSize = props.automaticSize,
		Visible = props.visible,
		Active = props.active,
		ClipsDescendants = props.clipsDescendants,
		BackgroundColor3 = backgroundColor,
		BackgroundTransparency = coerceNumber(
			props.backgroundTransparency or theme.backgroundTransparency,
			0.15,
			0,
			1
		),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}
	applyNativeProps(frameProps, props.native)

	local children: { [any]: React.ReactNode } = {
		UICorner = e("UICorner", {
			CornerRadius = props.cornerRadius or DEFAULT_CORNER_RADIUS,
		}),
		UIStroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
			Thickness = coerceNumber(props.strokeThickness or theme.strokeThickness, 1, 0, 8),
			Transparency = coerceNumber(props.strokeTransparency or theme.strokeTransparency, 0.22, 0, 1),
		}),
		UIPadding = e("UIPadding", {
			PaddingTop = props.paddingTop or padding,
			PaddingBottom = props.paddingBottom or padding,
			PaddingLeft = props.paddingLeft or padding,
			PaddingRight = props.paddingRight or padding,
		}),
	}

	if props.scale ~= nil then
		children.UIScale = e("UIScale", {
			Scale = coerceNumber(props.scale, 1, 0.05, 10),
		})
	end

	local hasText = props.title ~= nil or props.subtitle ~= nil or props.body ~= nil or props.content ~= nil
	if props.icon ~= nil and props.icon ~= "" then
		local iconProps: { [any]: any } = {
			Size = props.iconSize or UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.icon,
			ImageColor3 = iconColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 1,
		}
		applyNativeProps(iconProps, props.nativeIcon)
		children.Icon = e("ImageLabel", iconProps)
	end

	if hasText then
		local contentChildren: { [string]: React.ReactNode } = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		if props.title ~= nil then
			local titleProps: { [any]: any } = {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.PatrickHand,
				Text = props.title,
				TextColor3 = titleColor,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = zIndex + 1,
			}
			applyNativeProps(titleProps, props.nativeTitle)
			contentChildren.Title = e("TextLabel", titleProps)
		end

		if props.subtitle ~= nil then
			local subtitleProps: { [any]: any } = {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.PatrickHand,
				Text = props.subtitle,
				TextColor3 = subtitleColor,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = zIndex + 1,
			}
			applyNativeProps(subtitleProps, props.nativeSubtitle)
			contentChildren.Subtitle = e("TextLabel", subtitleProps)
		end

		if props.body ~= nil then
			local bodyProps: { [any]: any } = {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.PatrickHand,
				Text = props.body,
				TextColor3 = bodyColor,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = zIndex + 1,
			}
			applyNativeProps(bodyProps, props.nativeBody)
			contentChildren.Body = e("TextLabel", bodyProps)
		end

		if props.content ~= nil then
			contentChildren.Content = props.content
		end

		children.Content = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, contentChildren)
	end

	addChildren(children, props.children)

	return e("Frame", frameProps, children)
end
