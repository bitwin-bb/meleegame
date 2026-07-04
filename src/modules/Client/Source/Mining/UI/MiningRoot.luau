local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningProgressScreen = require("MiningProgressScreen")
local React: any = require(ReplicatedStorage.Packages.React)

type MiningRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: MiningRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: MiningRootProps

	return e(React.Fragment, nil, {
		e(MiningProgressScreen, GotProps),
	})
end
