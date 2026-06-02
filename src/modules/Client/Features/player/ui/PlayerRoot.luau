--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InfoPlayerScreen = require(gameRoot.Client.Features.player.ui.screens.infoPlayerScreen)
local React = require(ReplicatedStorage.Packages.React)

type PlayerRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: PlayerRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: PlayerRootProps

	return e(React.Fragment, nil, {
		e(InfoPlayerScreen, resolvedProps),
	})
end
