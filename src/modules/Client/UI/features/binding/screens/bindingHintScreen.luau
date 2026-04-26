--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BindingHintBottomBar =
	require(script:FindFirstAncestor("game").Client.UI.features.binding.hud.BindingHintBottomBar)
local React = require(ReplicatedStorage.Packages.React)
local bindingSlice = require(script:FindFirstAncestor("game").Client.UI.features.binding.state.bindingSlice)
local bindingThunks = require(script:FindFirstAncestor("game").Client.UI.features.binding.state.bindingThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type BindingHintState = bindingSlice.BindingHintState

type BindingHintScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingHintScreenProps?): React.ReactNode
	local resolvedProps: BindingHintScreenProps = if props ~= nil then props else {}
	local bindingState = (useStore(bindingSlice.bindingStateAtom) :: BindingHintState?)
		or bindingSlice.getBindingState()

	React.useEffect(function()
		local stop = bindingThunks.start()

		return function()
			stop()
		end
	end, {})

	if resolvedProps.visible == false or bindingState.visible ~= true or #bindingState.hints <= 0 then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 180
	return e(BindingHintBottomBar, {
		layoutOrder = resolvedProps.layoutOrder or 1,
		zIndex = zIndex + 1,
		visible = true,
		hints = bindingState.hints,
		deviceClass = bindingState.deviceClass,
	})
end
