--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeathScreen = require(gameRoot.Client.Features.death.ui.screens.deathScreen)
local React = require(ReplicatedStorage.Packages.React)

type DeathRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: DeathRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: DeathRootProps

	return e(React.Fragment, nil, {
		e(DeathScreen, resolvedProps),
	})
end
