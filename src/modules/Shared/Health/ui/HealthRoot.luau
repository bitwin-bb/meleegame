local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HpTopRightBar = require("HpTopRightBar")
local React = require(ReplicatedStorage.Packages.React)

type HealthRootProps = {
	[string]: any,
}

local e: typeof(React.createElement) = React.createElement

return function(props: HealthRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: HealthRootProps

	return e(React.Fragment, nil, {
		e(HpTopRightBar, resolvedProps),
	})
end
