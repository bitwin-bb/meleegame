--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InfoScreen = require(gameRoot.Client.Features.info.ui.screens.infoScreen)
local React = require(ReplicatedStorage.Packages.React)

type InfoRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: InfoRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: InfoRootProps

	return e(React.Fragment, nil, {
		e(InfoScreen, resolvedProps),
	})
end
