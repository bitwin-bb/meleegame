local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React: any = require(ReplicatedStorage.Packages.React)

export type SegmentIconProps = {
	icon: string,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	fillAlpha: number?,
	emptyColor: Color3?,
	fullColor: Color3?,
	tintColor: Color3?,
	emptyTransparency: number?,
	fullTransparency: number?,
	rotation: number?,
	scale: number?,
	clipFill: boolean?,
	resampleMode: Enum.ResamplerMode?,
	nativeFrame: { [any]: any }?,
	nativeEmpty: { [any]: any }?,
	nativeFull: { [any]: any }?,
	children: { React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function applyNativeProps(target: { [any]: any }, nativeProps: { [any]: any }?)
	if nativeProps == nil then
		return
	end

	for key, value in nativeProps do
		target[key] = value
	end
end

return function(props: SegmentIconProps): React.ReactNode
	local zIndex = props.zIndex or 1
	local fillAlpha = CoerceNumber(props.fillAlpha, 1, 0, 1)
	local emptyColor = props.emptyColor or props.tintColor or Color3.fromRGB(255, 255, 255)
	local fullColor = props.fullColor or props.tintColor or Color3.fromRGB(255, 255, 255)
	local rotation = props.rotation or 0

	local frameProps: { [any]: any } = {
		Size = props.size or UDim2.fromOffset(30, 30),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}
	applyNativeProps(frameProps, props.nativeFrame)

	local emptyProps: { [any]: any } = {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = props.icon,
		ImageColor3 = emptyColor,
		ImageTransparency = CoerceNumber(props.emptyTransparency, 0, 0, 1),
		Rotation = rotation,
		ScaleType = Enum.ScaleType.Fit,
		ResampleMode = props.resampleMode,
		ZIndex = zIndex + 1,
	}
	applyNativeProps(emptyProps, props.nativeEmpty)

	local children: { [any]: React.ReactNode } = {
		Empty = e("ImageLabel", emptyProps),
	}

	if props.scale ~= nil then
		children.Scale = e("UIScale", {
			Scale = CoerceNumber(props.scale, 1, 0.05, 10),
		})
	end

	local fullProps: { [any]: any } = {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = props.icon,
		ImageColor3 = fullColor,
		ImageTransparency = CoerceNumber(props.fullTransparency, 1 - fillAlpha, 0, 1),
		Rotation = rotation,
		ScaleType = Enum.ScaleType.Fit,
		ResampleMode = props.resampleMode,
		ZIndex = zIndex + 2,
	}
	applyNativeProps(fullProps, props.nativeFull)

	if props.clipFill == true and fillAlpha < 1 then
		if fillAlpha > 0 then
			children.FillClip = e("Frame", {
				Size = UDim2.fromScale(fillAlpha, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = zIndex + 2,
			}, {
				Full = e("ImageLabel", {
					Size = UDim2.fromScale(1 / fillAlpha, 1),
					BackgroundTransparency = fullProps.BackgroundTransparency,
					BorderSizePixel = fullProps.BorderSizePixel,
					Image = fullProps.Image,
					ImageColor3 = fullProps.ImageColor3,
					ImageTransparency = CoerceNumber(props.fullTransparency, 0, 0, 1),
					Rotation = fullProps.Rotation,
					ScaleType = fullProps.ScaleType,
					ResampleMode = fullProps.ResampleMode,
					ZIndex = fullProps.ZIndex,
				}),
			})
		end
	else
		children.Full = e("ImageLabel", fullProps)
	end

	if props.children ~= nil then
		for key, child in props.children do
			children[key] = child
		end
	end

	return e("Frame", frameProps, children)
end
