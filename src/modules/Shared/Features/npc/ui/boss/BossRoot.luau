--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MarkerScreen = require(gameRoot.Shared.Features.npc.ui.boss.screens.markerScreen)
local React = require(ReplicatedStorage.Packages.React)

type BossRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BossRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: BossRootProps

	return e(React.Fragment, nil, {
		e(MarkerScreen, resolvedProps),
	})
end
