local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemScreen = require("itemScreen")
local React = require(ReplicatedStorage.Packages.React)

type ItemRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ItemRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: ItemRootProps

	return e(React.Fragment, nil, {
		e(ItemScreen, resolvedProps),
	})
end
