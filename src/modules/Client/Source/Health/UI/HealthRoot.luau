local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HpTopRightBar = require("HpTopRightBar")
local React: any = require(ReplicatedStorage.Packages.React)

type HealthRootProps = {
	[string]: any,
}

local e: typeof(React.createElement) = React.createElement

return function(props: HealthRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: HealthRootProps

	return e(React.Fragment, nil, {
		e(HpTopRightBar, GotProps),
	})
end
