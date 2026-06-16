local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityInfoScreen = require("entityInfoScreen")
local React = require(ReplicatedStorage.Packages.React)

type EntityRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: EntityRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: EntityRootProps

	return e(React.Fragment, nil, {
		e(EntityInfoScreen, resolvedProps),
	})
end
