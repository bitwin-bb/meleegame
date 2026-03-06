--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local craftingSlice = require(ReplicatedStorage.UI.features.crafting.state.craftingSlice)

type CraftingRecipeEntry = craftingSlice.CraftingRecipeEntry

type CraftingSlotProps = {
	layoutOrder: number?,
	zIndex: number?,
	size: UDim2?,
	recipe: CraftingRecipeEntry,
	selected: boolean?,
	onActivated: ((recipeId: string) -> ())?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: CraftingSlotProps): React.ReactNode
	local recipe = props.recipe
	local canCraft = recipe.canCraft == true
	local selected = props.selected == true
	local zIndex = props.zIndex or 30
	local maxCraftText = if canCraft
		then ("x%d"):format(math.max(1, recipe.maxCraftableQuantity))
		else "Missing"

	return e("ImageButton", {
		Name = "CraftingSlot_" .. recipe.recipeId,
		Size = props.size or UDim2.fromOffset(296, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = ImageIds.craftItemSlot,
		ImageTransparency = if canCraft then 0 else 0.2,
		ImageColor3 = if selected
			then Color3.fromRGB(178, 226, 255)
			else if canCraft then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(190, 190, 190),
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
		AutoButtonColor = false,
		[React.Event.Activated] = function()
			if props.onActivated ~= nil then
				props.onActivated(recipe.recipeId)
			end
		end,
	}, {
		Name = e("TextLabel", {
			Name = "RecipeName",
			Size = UDim2.new(1, -84, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Text = recipe.displayName,
			Font = Enum.Font.GothamSemibold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if canCraft then Color3.fromRGB(246, 250, 255) else Color3.fromRGB(232, 166, 166),
			TextStrokeTransparency = 0.5,
			ZIndex = zIndex + 1,
		}),
		MaxCraft = e("TextLabel", {
			Name = "MaxCraft",
			Size = UDim2.fromOffset(70, 22),
			Position = UDim2.new(1, -74, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Text = maxCraftText,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if canCraft then Color3.fromRGB(153, 243, 184) else Color3.fromRGB(245, 171, 171),
			TextStrokeTransparency = 0.45,
			ZIndex = zIndex + 1,
		}),
		SelectedStroke = if selected
			then e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(124, 211, 255),
				Transparency = 0.15,
				Thickness = 1.3,
			})
			else nil,
	})
end
