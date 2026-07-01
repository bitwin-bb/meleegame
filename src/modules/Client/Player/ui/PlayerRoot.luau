local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InfoPlayerScreen = require("infoPlayerScreen")
local React = require(ReplicatedStorage.Packages.React)

type PlayerRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: PlayerRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: PlayerRootProps

	return e(React.Fragment, nil, {
		e(InfoPlayerScreen, GotProps),
	})
end
