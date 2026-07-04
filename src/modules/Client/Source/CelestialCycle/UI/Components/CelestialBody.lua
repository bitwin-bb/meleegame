local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)
local Table: any = require("Table")

local CelestialCycleTypes = require("CelestialCycleTypes")

type CelestialBodyState = CelestialCycleTypes.CelestialBodyState

local e: typeof(React.createElement) = React.createElement

local CelestialBody = {}

function CelestialBody.Render(props: { body: CelestialBodyState }): React.ReactNode
	local body = props.body
	if not body.visible then
		return nil
	end

	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = body.image,
		ImageTransparency = 1 - body.alpha,
		Position = body.position,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		Rotation = body.rotation,
		ScaleType = Enum.ScaleType.Fit,
		Size = body.size,
		ZIndex = body.zIndex,
	})
end

local readonlyBody = Table.readonly(CelestialBody)

return function(props: { body: CelestialBodyState }): React.ReactNode
	return readonlyBody.Render(props)
end
