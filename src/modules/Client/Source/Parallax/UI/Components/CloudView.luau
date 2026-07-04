local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)

local CloudServiceUtils = require("CloudServiceUtils")
local useCloudAppear = require("useCloudAppear")

type CloudSurfaceState = CloudServiceUtils.CloudSurfaceState
type CloudView = CloudServiceUtils.CloudView

local e: typeof(React.createElement) = React.createElement

export type CloudProps = {
	state: CloudSurfaceState,
}

local function CloudImage(props: { cloud: CloudView }): React.ReactNode
	local cloud = props.cloud
	local imageTransparency = useCloudAppear({
		id = cloud.id,
		targetTransparency = cloud.imageTransparency,
	})

	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = cloud.position,
		Size = cloud.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = cloud.image,
		ImageColor3 = cloud.imageColor,
		ImageTransparency = imageTransparency,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = cloud.zIndex,
	})
end

return function(props: CloudProps): React.ReactNode
	local state = props.state
	if not state.visible then
		return nil
	end

	local children = {}
	for _, cloud in state.clouds do
		children[cloud.id] = e(CloudImage, {
			cloud = cloud,
		})
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
