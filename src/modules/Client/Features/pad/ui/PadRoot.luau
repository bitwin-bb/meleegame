--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PadScreen = require(script.Parent.screens.pad)
local React = require(ReplicatedStorage.Packages.React)

type PadRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: PadRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: PadRootProps

	return e(React.Fragment, nil, {
		e(PadScreen, resolvedProps),
	})
end
