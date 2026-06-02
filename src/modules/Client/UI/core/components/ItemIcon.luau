--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type ItemIconProps = {
	icon: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	imageColor3: Color3?,
	imageTransparency: number?,
	scaleType: Enum.ScaleType?,
	resampleMode: Enum.ResamplerMode?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ItemIconProps): React.ReactNode
	local imageProps: { [any]: any } = {
		Size = props.size or UDim2.fromOffset(32, 32),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = props.icon or "",
		ImageColor3 = props.imageColor3 or Color3.fromRGB(255, 255, 255),
		ImageTransparency = props.imageTransparency or 0,
		ScaleType = props.scaleType,
		ResampleMode = props.resampleMode,
		ZIndex = props.zIndex,
	}

	if props.native ~= nil then
		for key, value in props.native do
			imageProps[key] = value
		end
	end

	return e("ImageLabel", imageProps)
end
