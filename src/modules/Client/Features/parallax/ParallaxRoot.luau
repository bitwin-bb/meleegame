--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CloudScreen = require(script.Parent.ui.screens.CloudScreen)
local ParallaxScreen = require(script.Parent.ui.screens.ParallaxScreen)
local React = require(ReplicatedStorage.Packages.React)

type ParallaxRootProps = {
	cloudsVisible: boolean?,
	parallaxVisible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ParallaxRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: ParallaxRootProps
	local children: { React.ReactNode } = {}

	if resolvedProps.parallaxVisible ~= false then
		children[#children + 1] = e(ParallaxScreen)
	end

	if resolvedProps.cloudsVisible ~= false then
		children[#children + 1] = e(CloudScreen)
	end

	return e(React.Fragment, nil, children)
end
