local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingSlot = require("CraftingSlot")
local React: any = require(ReplicatedStorage.Packages.React)
local craftingSlice = require("CraftingSlice")

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
