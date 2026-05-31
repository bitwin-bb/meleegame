--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ManaTopRightBar = require(script.Parent.hud.TopBar.ManaTopRightBar)
local React = require(ReplicatedStorage.Packages.React)

type ManaRootProps = {
	[string]: any,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ManaRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: ManaRootProps

	return e(React.Fragment, nil, {
		e(ManaTopRightBar, resolvedProps),
	})
end
