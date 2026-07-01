local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EyeOfCthulhuScreen = require("EyeOfCthulhuScreen")
local EyeOfCthulhuServantScreen = require("EyeOfCthulhuServantScreen")
local QueenBeeScreen = require("QueenBeeScreen")
local React = require(ReplicatedStorage.Packages.React)
local SlimeScreen = require("SlimeScreen")

type NpcRootProps = {
	eyeOfCthulhuZIndex: number?,
	eyeOfCthulhuServantZIndex: number?,
	slimeZIndex: number?,
	queenBeeZIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: NpcRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: NpcRootProps

	return e(React.Fragment, nil, {
		e(EyeOfCthulhuScreen, {
			zIndex = GotProps.eyeOfCthulhuZIndex or 166,
		}),
		e(EyeOfCthulhuServantScreen, {
			zIndex = GotProps.eyeOfCthulhuServantZIndex or 167,
		}),
		e(SlimeScreen, {
			zIndex = GotProps.slimeZIndex or 168,
		}),
		e(QueenBeeScreen, {
			zIndex = GotProps.queenBeeZIndex or 169,
		}),
	})
end
