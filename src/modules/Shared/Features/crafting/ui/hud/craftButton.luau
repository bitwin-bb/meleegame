--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local CraftingButton = require(gameRoot.Shared.Features.crafting.ui.components.craftingButton)
local React = require(ReplicatedStorage.Packages.React)
local craftingSlice = require(gameRoot.Shared.Features.crafting.ui.state.craftingSlice)
local craftingThunks = require(gameRoot.Shared.Features.crafting.ui.state.craftingThunks)
local useStore = require(gameRoot.Client.UI.core.hooks.useStore)

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
	local craftingState = (useStore(craftingSlice.craftingStateAtom) :: CraftingState?)
		or craftingSlice.getCraftingState()

	React.useEffect(function()
		local stop = craftingThunks.start()

		return function()
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
