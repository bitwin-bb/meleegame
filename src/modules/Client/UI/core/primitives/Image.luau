local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type ImageProps = {
	image: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	imageColor3: Color3?,
	imageTransparency: number?,
	backgroundTransparency: number?,
	scaleType: Enum.ScaleType?,
	resampleMode: Enum.ResamplerMode?,
	children: { React.ReactNode }?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ImageProps): React.ReactNode
	local imageProps: { [any]: any } = {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		ZIndex = props.zIndex,
		BackgroundTransparency = if props.backgroundTransparency ~= nil then props.backgroundTransparency else 1,
		BorderSizePixel = 0,
		Image = props.image or "",
		ImageColor3 = props.imageColor3,
		ImageTransparency = props.imageTransparency,
		ScaleType = props.scaleType,
		ResampleMode = props.resampleMode,
	}

	if props.native ~= nil then
		for key, value in props.native do
			imageProps[key] = value
		end
	end

	return e("ImageLabel", imageProps, props.children)
end
