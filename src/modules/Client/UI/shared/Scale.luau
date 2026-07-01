local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")

export type ScaleProps = {
	scale: number?,
	multiplier: number?,
	minScale: number?,
	maxScale: number?,
	useViewportScale: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ScaleProps): React.ReactNode
	local shouldUseViewportScale = props.useViewportScale == true
	local viewportScale = Responsive.useResponsiveMetrics().scale

	local GotScale = if props.scale ~= nil then props.scale else 1
	GotScale *= props.multiplier or 1
	if shouldUseViewportScale then
		GotScale *= viewportScale
	end
	if props.minScale ~= nil or props.maxScale ~= nil then
		GotScale = math.clamp(GotScale, props.minScale or -math.huge, props.maxScale or math.huge)
	end

	return e("UIScale", {
		Scale = GotScale,
	})
end
