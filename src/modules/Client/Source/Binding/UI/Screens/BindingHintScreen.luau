local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BindingHintBottomBar = require("BindingHintBottomBar")
local React: any = require(ReplicatedStorage.Packages.React)
local bindingSlice = require("BindingSlice")
local bindingThunks = require("BindingThunks")
local useStore = require("useCoreStore")

type BindingHintState = bindingSlice.BindingHintState

type BindingHintScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingHintScreenProps?): React.ReactNode
	local GotProps: BindingHintScreenProps = if props ~= nil then props else {} :: any
	local bindingState = (useStore(bindingSlice.bindingStateAtom) :: BindingHintState?)
		or bindingSlice.getBindingState()

	React.useEffect(function()
		local stop = bindingThunks.Start()

		return function()
			stop()
		end
	end, {})

	if GotProps.visible == false or bindingState.visible ~= true or #bindingState.hints <= 0 then
		return nil
	end

	local zIndex = GotProps.zIndex or 180
	return e(BindingHintBottomBar, {
		layoutOrder = GotProps.layoutOrder or 1,
		zIndex = zIndex + 1,
		visible = true,
		hints = bindingState.hints,
		deviceClass = bindingState.deviceClass,
	})
end
