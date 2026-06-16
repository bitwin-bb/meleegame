local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BindingHintScreen = require(script.Parent:WaitForChild("screens"):WaitForChild("bindingHintScreen"))
local React = require(ReplicatedStorage.Packages.React)

type BindingRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: BindingRootProps

	return e(React.Fragment, nil, {
		e(BindingHintScreen, resolvedProps),
	})
end
