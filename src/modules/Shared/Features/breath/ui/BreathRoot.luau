--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BubblesScreen = require(gameRoot.Shared.Features.breath.ui.screens.bubblesScreen)
local React = require(ReplicatedStorage.Packages.React)

type BreathRootProps = {
	[string]: any,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BreathRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: BreathRootProps

	return e(React.Fragment, nil, {
		e(BubblesScreen, resolvedProps),
	})
end
