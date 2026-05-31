--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingSlot = require(script.Parent.craftingSlot)
local React = require(ReplicatedStorage.Packages.React)
local craftingSlice = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.state.craftingSlice)

type CraftingRecipeEntry = craftingSlice.CraftingRecipeEntry

export type RecipeSlotProps = {
	layoutOrder: number?,
	zIndex: number?,
	size: UDim2?,
	recipe: CraftingRecipeEntry,
	selected: boolean?,
	onActivated: ((recipeId: string) -> ())?,
}

return function(props: RecipeSlotProps): React.ReactNode
	return React.createElement(CraftingSlot, {
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		size = props.size,
		recipe = props.recipe,
		selected = props.selected,
		onActivated = props.onActivated,
	})
end
