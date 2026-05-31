--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingSlotsScreen = require(script.Parent.screens.craftingSlots)
local React = require(ReplicatedStorage.Packages.React)

type CraftingRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: CraftingRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: CraftingRootProps

	return e(React.Fragment, nil, {
		e(CraftingSlotsScreen, resolvedProps),
	})
end
