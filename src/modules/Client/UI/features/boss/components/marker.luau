--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)

export type MarkerProps = {
	icon: string,
	position: Vector2,
	rotation: number,
	size: UDim2?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_SIZE = UDim2.fromOffset(72, 72)
local MARKER_COLOR = Color3.fromRGB(255, 247, 250)
local ICON_GAP = 4

return function(props: MarkerProps): React.ReactNode
	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 200
	local markerSize = props.size or DEFAULT_SIZE
	local markerWidth = if markerSize.X.Offset > 0 then markerSize.X.Offset else DEFAULT_SIZE.X.Offset
	local markerHeight = if markerSize.Y.Offset > 0 then markerSize.Y.Offset else DEFAULT_SIZE.Y.Offset
	local markerRadius = math.min(markerWidth, markerHeight) * 0.5
	local rotationRadians = math.rad(props.rotation)
	local baseDirection = Vector2.new(-math.sin(rotationRadians), math.cos(rotationRadians))
	local iconSize = math.max(16, math.floor(markerRadius * 0.58 + 0.5))
	local baseOffset = math.floor(markerRadius + ICON_GAP + iconSize * 0.5 + 0.5)
	local iconPosition = Vector2.new(markerWidth * 0.5, markerHeight * 0.5) + baseDirection * baseOffset

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(props.position.X + 0.5), math.floor(props.position.Y + 0.5)),
		Size = markerSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = zIndex,
	}, {
		Marker = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.marker,
			ImageColor3 = MARKER_COLOR,
			Rotation = props.rotation,
			ZIndex = zIndex + 1,
		}),
		Icon = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.floor(iconPosition.X + 0.5), math.floor(iconPosition.Y + 0.5)),
			Size = UDim2.fromOffset(iconSize, iconSize),
			BackgroundTransparency = 1,
			Image = props.icon,
			ZIndex = zIndex + 2,
		}),
	})
end
