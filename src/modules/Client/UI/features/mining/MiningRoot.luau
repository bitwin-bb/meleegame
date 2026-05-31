--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningProgressScreen = require(script.Parent.screens.miningProgressScreen)
local React = require(ReplicatedStorage.Packages.React)

type MiningRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: MiningRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: MiningRootProps

	return e(React.Fragment, nil, {
		e(MiningProgressScreen, resolvedProps),
	})
end
