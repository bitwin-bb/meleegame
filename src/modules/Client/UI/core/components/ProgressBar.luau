--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type ProgressBarProps = {
	progress: number,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	trackImage: string?,
	fillImage: string?,
	trackColor3: Color3?,
	fillColor3: Color3?,
	trackTransparency: number?,
	fillTransparency: number?,
	fillInset: Vector2?,
	fillSize: UDim2?,
	fillClipsDescendants: boolean?,
	children: { React.ReactNode }?,
	nativeTrack: { [any]: any }?,
	nativeFillClip: { [any]: any }?,
	nativeFill: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ProgressBarProps): React.ReactNode
	local zIndex = props.zIndex or 1
	local progress = math.clamp(props.progress, 0, 1)
	local fillInset = props.fillInset or Vector2.zero
	local fillSize = props.fillSize or UDim2.fromScale(progress, 1)

	local trackProps: { [any]: any } = {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		BackgroundTransparency = if props.trackImage ~= nil then 1 else (props.trackTransparency or 0),
		BackgroundColor3 = props.trackColor3,
		BorderSizePixel = 0,
		Image = props.trackImage or "",
		ImageTransparency = props.trackTransparency,
		ZIndex = zIndex,
	}
	if props.nativeTrack ~= nil then
		for key, value in props.nativeTrack do
			trackProps[key] = value
		end
	end

	local fillClipProps: { [any]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = props.fillClipsDescendants ~= false,
		Position = UDim2.fromOffset(math.floor(fillInset.X), math.floor(fillInset.Y)),
		Size = fillSize,
		ZIndex = zIndex + 1,
	}
	if props.nativeFillClip ~= nil then
		for key, value in props.nativeFillClip do
			fillClipProps[key] = value
		end
	end

	local fillProps: { [any]: any } = {
		BackgroundTransparency = if props.fillImage ~= nil then 1 else (props.fillTransparency or 0),
		BackgroundColor3 = props.fillColor3,
		BorderSizePixel = 0,
		Image = props.fillImage or "",
		ImageTransparency = props.fillTransparency,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex + 1,
	}
	if props.nativeFill ~= nil then
		for key, value in props.nativeFill do
			fillProps[key] = value
		end
	end

	return e("ImageLabel", trackProps, {
		e("Frame", fillClipProps, {
			e("ImageLabel", fillProps),
		}),
		props.children,
	})
end
