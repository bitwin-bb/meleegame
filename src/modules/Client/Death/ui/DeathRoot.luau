local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeathScreen = require("deathScreen")
local React = require(ReplicatedStorage.Packages.React)

type DeathRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: DeathRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: DeathRootProps

	return e(React.Fragment, nil, {
		e(DeathScreen, resolvedProps),
	})
end
