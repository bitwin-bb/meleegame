local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeNameScreen = require("biomeNameScreen")
local React = require(ReplicatedStorage.Packages.React)

type BiomeRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BiomeRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: BiomeRootProps

	return e(React.Fragment, nil, {
		e(BiomeNameScreen, resolvedProps),
	})
end
