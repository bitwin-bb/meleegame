--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BindingHintBottomBar = require(gameRoot.Client.Features.binding.ui.hud.BindingHintBottomBar)
local React = require(ReplicatedStorage.Packages.React)
local bindingSlice = require(gameRoot.Client.Features.binding.ui.state.bindingSlice)
local bindingThunks = require(gameRoot.Client.Features.binding.ui.state.bindingThunks)
local useStore = require(gameRoot.Client.UI.core.hooks.useStore)

type BindingHintState = bindingSlice.BindingHintState

type BindingHintScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: BindingHintScreenProps?): React.ReactNode
	local resolvedProps: BindingHintScreenProps = if props ~= nil then props else {} :: any
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
