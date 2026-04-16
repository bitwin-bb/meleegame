--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local CraftingButton = require(script:FindFirstAncestor("game").Client.UI.features.crafting.components.craftingButton)
local craftingSlice = require(script:FindFirstAncestor("game").Client.UI.features.crafting.state.craftingSlice)
local craftingThunks = require(script:FindFirstAncestor("game").Client.UI.features.crafting.state.craftingThunks)

type CraftingState = craftingSlice.CraftingState

type CraftButtonProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: CraftButtonProps): React.ReactNode
	local craftingState, setCraftingState = React.useState(function(): CraftingState
		return craftingSlice.getCraftingState()
	end)

	React.useEffect(function()
		local stop = craftingThunks.start()
		local unsubscribe = Charm.subscribe(craftingSlice.craftingStateAtom, function(nextState: CraftingState)
			setCraftingState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			stop()
		end
	end, {})

	return e(CraftingButton, {
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		zIndex = props.zIndex,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		selected = craftingState.visible,
		onActivated = function()
			craftingThunks.toggleVisible()
		end,
	})
end
