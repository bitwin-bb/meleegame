local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BindingHintScreen = require(script.Parent:WaitForChild("Screens"):WaitForChild("BindingHintScreen"))
local React: any = require(ReplicatedStorage.Packages.React)

type BindingRootProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: BindingRootProps

	return e(React.Fragment, nil, {
		e(BindingHintScreen, GotProps),
	})
end
