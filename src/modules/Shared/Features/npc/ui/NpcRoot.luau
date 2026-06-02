--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EyeOfCthulhuScreen = require(gameRoot.Shared.Features.npc.ui.screens.EyeOfCthulhuScreen)
local EyeOfCthulhuServantScreen = require(gameRoot.Shared.Features.npc.ui.screens.EyeOfCthulhuServantScreen)
local QueenBeeScreen = require(gameRoot.Shared.Features.npc.ui.screens.QueenBeeScreen)
local React = require(ReplicatedStorage.Packages.React)
local SlimeScreen = require(gameRoot.Shared.Features.npc.ui.screens.SlimeScreen)

type NpcRootProps = {
	eyeOfCthulhuZIndex: number?,
	eyeOfCthulhuServantZIndex: number?,
	slimeZIndex: number?,
	queenBeeZIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: NpcRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: NpcRootProps

	return e(React.Fragment, nil, {
		e(EyeOfCthulhuScreen, {
			zIndex = resolvedProps.eyeOfCthulhuZIndex or 166,
		}),
		e(EyeOfCthulhuServantScreen, {
			zIndex = resolvedProps.eyeOfCthulhuServantZIndex or 167,
		}),
		e(SlimeScreen, {
			zIndex = resolvedProps.slimeZIndex or 168,
		}),
		e(QueenBeeScreen, {
			zIndex = resolvedProps.queenBeeZIndex or 169,
		}),
	})
end
