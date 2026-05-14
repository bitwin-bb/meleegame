--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ParallaxSlice = require(script:FindFirstAncestor("parallax").ParallaxSlice)

type ParallaxSurfaceState = ParallaxSlice.ParallaxSurfaceState
type ParallaxLayerView = ParallaxSlice.ParallaxLayerView

local e: typeof(React.createElement) = React.createElement

export type ParallaxProps = {
	state: ParallaxSurfaceState,
}

local function renderLayer(layer: ParallaxLayerView): React.ReactNode
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = layer.framePosition,
		Size = layer.frameSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = layer.zIndex,
	}, {
		e("ImageLabel", {
			AnchorPoint = Vector2.zero,
			Position = layer.imagePosition,
			Size = layer.imageSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = layer.image,
			ImageColor3 = layer.imageColor,
			ImageTransparency = layer.imageTransparency,
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = layer.tileSize,
			ZIndex = layer.zIndex,
		}),
	})
end

return function(props: ParallaxProps): React.ReactNode
	local state = props.state
	if not state.visible then
		return nil
	end

	local children = {}
	for _, layer in state.layers do
		table.insert(children, renderLayer(layer))
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, children)
end
