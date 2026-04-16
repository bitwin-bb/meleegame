--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local BindingHintBottomBar = require(script:FindFirstAncestor("game").Client.UI.features.bindingHint.hud.BindingHintBottomBar)
local bindingSlice = require(script:FindFirstAncestor("game").Client.UI.features.bindingHint.state.bindingSlice)
local bindingThunks = require(script:FindFirstAncestor("game").Client.UI.features.bindingHint.state.bindingThunks)

type BindingHintState = bindingSlice.BindingHintState

type BindingHintScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingHintScreenProps?): React.ReactNode
	local resolvedProps: BindingHintScreenProps = if props ~= nil then props else {}
	local bindingState, setBindingState = React.useState(function(): BindingHintState
		return bindingSlice.getBindingState()
	end)

	React.useEffect(function()
		local stop = bindingThunks.start()
		local unsubscribe = Charm.subscribe(bindingSlice.bindingStateAtom, function(nextState: BindingHintState)
			setBindingState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
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
