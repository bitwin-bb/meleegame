local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeNameScreen = require("BiomeNameScreen")
local React: any = require(ReplicatedStorage.Packages.React)

type BiomeRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BiomeRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: BiomeRootProps

	return e(React.Fragment, nil, {
		e(BiomeNameScreen, GotProps),
	})
end
