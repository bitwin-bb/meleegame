local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MouseScreen = require("MouseScreen")
local React = require(ReplicatedStorage.Packages.React)

type MouseRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: MouseRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: MouseRootProps

	return e(React.Fragment, nil, {
		e(MouseScreen, GotProps),
	})
end
