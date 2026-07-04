local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CloudScreen = require("CloudScreen")
local ParallaxScreen = require("ParallaxScreen")
local React: any = require(ReplicatedStorage.Packages.React)

type ParallaxRootProps = {
	cloudsVisible: boolean?,
	parallaxVisible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ParallaxRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: ParallaxRootProps
	local children: { React.ReactNode } = {}

	if GotProps.parallaxVisible ~= false then
		children[#children + 1] = e(ParallaxScreen)
	end

	if GotProps.cloudsVisible ~= false then
		children[#children + 1] = e(CloudScreen)
	end

	return e(React.Fragment, nil, children)
end
