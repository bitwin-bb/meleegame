--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MouseScreen = require(gameRoot.Client.Features.mouse.ui.screen.mouseScreen)
local React = require(ReplicatedStorage.Packages.React)

type MouseRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: MouseRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: MouseRootProps

	return e(React.Fragment, nil, {
		e(MouseScreen, resolvedProps),
	})
end
