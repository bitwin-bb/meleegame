--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BindingHintScreen = require(gameRoot.Client.Features.binding.ui.screens.bindingHintScreen)
local React = require(ReplicatedStorage.Packages.React)

type BindingRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: BindingRootProps

	return e(React.Fragment, nil, {
		e(BindingHintScreen, resolvedProps),
	})
end
