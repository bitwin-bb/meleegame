--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakScreen = require(gameRoot.Client.Features.tile.ui.screen.Break)
local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

return function(): React.ReactNode
	return e(React.Fragment, nil, {
		e(BreakScreen),
	})
end
