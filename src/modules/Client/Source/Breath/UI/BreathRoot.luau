local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BubblesScreen = require("BubblesScreen")
local React = require(ReplicatedStorage.Packages.React)

type BreathRootProps = {
	[string]: any,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BreathRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: BreathRootProps

	return e(React.Fragment, nil, {
		e(BubblesScreen, GotProps),
	})
end
