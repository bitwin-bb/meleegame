--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local CraftingSlot = require(ReplicatedStorage.UI.features.crafting.components.craftingSlot)
local CraftingButton = require(ReplicatedStorage.UI.features.crafting.components.craftingButton)
local useCraftMenuDrag = require(ReplicatedStorage.UI.features.crafting.hooks.useCraftMenuDrag)
local useCraftSlide = require(ReplicatedStorage.UI.features.crafting.hooks.useCraftSlide)
local craftingSlice = require(ReplicatedStorage.UI.features.crafting.state.craftingSlice)
local craftingThunks = require(ReplicatedStorage.UI.features.crafting.state.craftingThunks)

type CraftingState = craftingSlice.CraftingState
type CraftingRecipeEntry = craftingSlice.CraftingRecipeEntry

type CraftingSlotsProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

local PANEL_WIDTH = 336
local PANEL_HEIGHT = 458
local PANEL_OPEN_START_OFFSET = Vector2.new(0, 96)
local PANEL_MIN_SCALE = 0.2
local CATEGORY_TAB_HEIGHT = 26
local RECIPE_SLOT_HEIGHT = 48
local MENU_OPEN_SPRING = {
	frequency = 0.2,
	damping = 1,
}
local function resolveImageId(valueRaw: any, fallbackRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	if typeof(fallbackRaw) == "string" and fallbackRaw ~= "" then
		return fallbackRaw
	end
	return ""
end

local CRAFTING_MENU_IMAGE_ID = resolveImageId(ImageIds.craftingMenu, "")
local CRAFTING_MENU_INNER_IMAGE_ID = resolveImageId(ImageIds.craftingMenuInner, CRAFTING_MENU_IMAGE_ID)
local CRAFTING_MENU_TEXTBOX_IMAGE_ID = resolveImageId(ImageIds.craftingMenuTextBox, CRAFTING_MENU_INNER_IMAGE_ID)
local CRAFTING_MENU_CATEGORY_IMAGE_ID = resolveImageId(ImageIds.craftingMenuCategory, CRAFTING_MENU_INNER_IMAGE_ID)

local function resolveSelectedRecipe(state: CraftingState): CraftingRecipeEntry?
	local selectedRecipeId = state.selectedRecipeId
	if selectedRecipeId == nil then
		return nil
	end

	for _, entry in state.recipes do
		if entry.recipeId == selectedRecipeId then
			return entry
		end
	end
	return nil
end

local function resolveRecipeStatusText(recipe: CraftingRecipeEntry?): string
	if recipe == nil then
		return "Select a recipe."
	end
	if recipe.canCraft then
		return ("Craftable: %d"):format(math.max(1, recipe.maxCraftableQuantity))
	end
	return "Missing ingredients or station."
end

local function buildIngredientRows(previewRaw: any, zIndex: number): { [string]: React.ReactNode }
	local rows: { [string]: React.ReactNode } = {}
	if typeof(previewRaw) ~= "table" then
		return rows
	end

	local ingredientsRaw = (previewRaw :: any).ingredients
	if typeof(ingredientsRaw) ~= "table" then
		return rows
	end

	for index, ingredientRaw in ingredientsRaw do
		if typeof(ingredientRaw) ~= "table" then
			continue
		end
		local ingredient = ingredientRaw :: { [string]: any }
		local itemId = if typeof(ingredient.itemId) == "string" then ingredient.itemId else "Item"
		local required = if typeof(ingredient.required) == "number" and ingredient.required == ingredient.required
			then math.max(0, math.floor(ingredient.required))
			else 0
		local available = if typeof(ingredient.available) == "number" and ingredient.available == ingredient.available
			then math.max(0, math.floor(ingredient.available))
			else 0
		local isSufficient = ingredient.isSufficient == true

		rows["Ingredient_" .. tostring(index)] = e("TextLabel", {
			Name = "Ingredient_" .. tostring(index),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Text = ("%s  %d/%d"):format(itemId, available, required),
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if isSufficient then Color3.fromRGB(157, 239, 182) else Color3.fromRGB(248, 172, 172),
			TextStrokeTransparency = 0.65,
			ZIndex = zIndex,
		})
	end

	return rows
end

return function(props: CraftingSlotsProps): React.ReactNode
	local craftingState, setCraftingState = React.useState(function(): CraftingState
		return craftingSlice.getCraftingState()
	end)
	local searchText, setSearchText = React.useState(function(): string
		return craftingState.searchQuery
	end)

	React.useEffect(function()
		local stop = craftingThunks.start()
		local unsubscribe = Charm.subscribe(craftingSlice.craftingStateAtom, function(nextState: CraftingState)
			setCraftingState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			craftingThunks.stopBulkCraft()
			unsubscribe()
			stop()
		end
	end, {})

	React.useEffect(function()
		setSearchText(craftingState.searchQuery)
	end, { craftingState.searchQuery })

	local isRequestedVisible = props.visible ~= false
	local isOpen = isRequestedVisible and craftingState.visible
	local craftMenuDrag = useCraftMenuDrag({
		enabled = isOpen,
		dragSmoothness = 16,
	})
	local slideProgress = useCraftSlide({
		enabled = isOpen,
		spring = MENU_OPEN_SPRING,
	})
	if not isOpen and slideProgress <= 0.001 then
		return nil
	end

	local zIndex = props.zIndex or 180
	local destinationOffset = craftMenuDrag.offset
	local sourceOffset = destinationOffset + PANEL_OPEN_START_OFFSET
	local animatedOffset = sourceOffset:Lerp(destinationOffset, slideProgress)
	local pathLength = PANEL_OPEN_START_OFFSET.Magnitude
	local remainingDistance = (destinationOffset - animatedOffset).Magnitude
	local panelTransparency = if pathLength > 0
		then math.clamp(remainingDistance / pathLength, 0, 1)
		else math.clamp(1 - slideProgress, 0, 1)
	local panelScale = PANEL_MIN_SCALE + (1 - PANEL_MIN_SCALE) * (1 - panelTransparency)
	local activeCategory = craftingState.categoryFilter
	local selectedRecipe = resolveSelectedRecipe(craftingState)
	local canCraftSelected = selectedRecipe ~= nil and selectedRecipe.canCraft
	local categoryTabs = { "All" }
	for _, category in craftingState.availableCategories do
		categoryTabs[#categoryTabs + 1] = category
	end

	local recipeChildren: { [string]: React.ReactNode } = {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, entry in craftingState.recipes do
		recipeChildren["Recipe_" .. entry.recipeId] = e(CraftingSlot, {
			layoutOrder = index,
			zIndex = zIndex + 4,
			size = UDim2.new(1, -8, 0, RECIPE_SLOT_HEIGHT),
			recipe = entry,
			selected = craftingState.selectedRecipeId == entry.recipeId,
			onActivated = function(recipeId: string)
				craftingThunks.selectRecipe(recipeId)
			end,
		})
	end

	local categoryChildren: { [string]: React.ReactNode } = {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, category in categoryTabs do
		local isAll = category == "All"
		local categoryValue = if isAll then "" else category
		local isSelected = activeCategory == categoryValue
		local hasCategoryAsset = CRAFTING_MENU_CATEGORY_IMAGE_ID ~= ""
		categoryChildren["Category_" .. tostring(index)] = e("ImageButton", {
			Name = "Category_" .. tostring(index),
			Size = UDim2.fromOffset(74, CATEGORY_TAB_HEIGHT),
			LayoutOrder = index,
			AutoButtonColor = false,
			BackgroundColor3 = if isSelected then Color3.fromRGB(76, 142, 185) else Color3.fromRGB(38, 47, 60),
			BackgroundTransparency = if hasCategoryAsset then 1 else panelTransparency * 0.35,
			BorderSizePixel = 0,
			Image = CRAFTING_MENU_CATEGORY_IMAGE_ID,
			ImageColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(229, 240, 252),
			ImageTransparency = panelTransparency * 0.25,
			ZIndex = zIndex + 3,
			[React.Event.Activated] = function()
				craftingThunks.setCategoryFilter(categoryValue)
			end,
		}, {
			Label = e("TextLabel", {
				Name = "Label",
				Size = UDim2.new(1, -8, 1, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = category,
				Font = Enum.Font.GothamSemibold,
				TextSize = 12,
				TextColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(212, 223, 236),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.55,
				ZIndex = zIndex + 4,
			}),
		})
	end

	local ingredientRows = buildIngredientRows(if selectedRecipe ~= nil then selectedRecipe.preview else nil, zIndex + 4)

	return e("Frame", {
		Name = "CraftingSlotsScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 12,
		ZIndex = zIndex,
		Visible = isRequestedVisible,
	}, {
		Panel = e("CanvasGroup", {
			Name = "CraftingPanel",
			Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
			Position = UDim2.new(0.5, math.floor(animatedOffset.X), 0.5, math.floor(animatedOffset.Y)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(24, 33, 43),
			BackgroundTransparency = if CRAFTING_MENU_IMAGE_ID ~= "" then 1 else panelTransparency * 0.15,
			BorderSizePixel = 0,
			GroupTransparency = panelTransparency,
			ZIndex = zIndex + 1,
		}, {
			Scale = e("UIScale", {
				Scale = panelScale,
			}),
			BackgroundImage = if CRAFTING_MENU_IMAGE_ID ~= ""
				then e("ImageLabel", {
					Name = "BackgroundImage",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = CRAFTING_MENU_IMAGE_ID,
					ImageColor3 = Color3.fromRGB(255, 255, 255),
					ImageTransparency = panelTransparency,
					ZIndex = zIndex + 1,
				})
				else nil,
			Header = e("TextLabel", {
				Name = "Header",
				Size = UDim2.new(1, -20, 0, 24),
				Position = UDim2.fromOffset(10, 10),
				BackgroundTransparency = 1,
				Text = "Crafting",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(246, 251, 255),
				TextStrokeTransparency = 0.45,
				ZIndex = zIndex + 2,
			}),
			DragHandle = e("TextButton", {
				Name = "DragHandle",
				Size = UDim2.new(1, 0, 0, 32),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				ZIndex = zIndex + 6,
				[React.Event.InputBegan] = function(rbx: GuiObject, inputObject: InputObject)
					craftMenuDrag.onDragInputBegan(rbx, inputObject)
				end,
				[React.Event.InputEnded] = function(rbx: GuiObject, inputObject: InputObject)
					craftMenuDrag.onDragInputEnded(rbx, inputObject)
				end,
			}),
			SearchContainer = e("ImageLabel", {
				Name = "SearchContainer",
				Size = UDim2.new(1, -20, 0, 28),
				Position = UDim2.fromOffset(10, 38),
				BackgroundColor3 = Color3.fromRGB(16, 23, 32),
				BackgroundTransparency = if CRAFTING_MENU_TEXTBOX_IMAGE_ID ~= "" then 1 else panelTransparency * 0.2,
				BorderSizePixel = 0,
				Image = CRAFTING_MENU_TEXTBOX_IMAGE_ID,
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				ImageTransparency = panelTransparency * 0.2,
				ZIndex = zIndex + 3,
			}, {
				Search = e("TextBox", {
					Name = "Search",
					Size = UDim2.new(1, -14, 1, -6),
					Position = UDim2.fromOffset(7, 3),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = searchText,
					PlaceholderText = "Search recipes...",
					Font = Enum.Font.Gotham,
					TextSize = 13,
					TextColor3 = Color3.fromRGB(235, 242, 250),
					PlaceholderColor3 = Color3.fromRGB(134, 152, 171),
					ClearTextOnFocus = false,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = zIndex + 4,
					[React.Change.Text] = function(rbx: TextBox)
						setSearchText(rbx.Text)
					end,
					[React.Event.FocusLost] = function()
						craftingThunks.setSearchQuery(searchText)
					end,
				}),
			}),
			Categories = e("Frame", {
				Name = "Categories",
				Size = UDim2.new(1, -20, 0, CATEGORY_TAB_HEIGHT),
				Position = UDim2.fromOffset(10, 72),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 3,
			}, {
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 2),
					PaddingRight = UDim.new(0, 2),
				}),
				CategoriesList = e(React.Fragment, nil, categoryChildren),
			}),
			RecipesContainer = e("ImageLabel", {
				Name = "RecipesContainer",
				Size = UDim2.new(1, -20, 0, 240),
				Position = UDim2.fromOffset(10, 104),
				BackgroundColor3 = Color3.fromRGB(19, 27, 36),
				BackgroundTransparency = if CRAFTING_MENU_INNER_IMAGE_ID ~= "" then 1 else panelTransparency * 0.2,
				BorderSizePixel = 0,
				Image = CRAFTING_MENU_INNER_IMAGE_ID,
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				ImageTransparency = panelTransparency * 0.2,
				ZIndex = zIndex + 3,
			}, {
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
				Recipes = e("ScrollingFrame", {
					Name = "Recipes",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarThickness = 5,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					ZIndex = zIndex + 4,
				}, recipeChildren),
			}),
			SelectionDetails = e("ImageLabel", {
				Name = "SelectionDetails",
				Size = UDim2.new(1, -20, 0, 64),
				Position = UDim2.fromOffset(10, 348),
				BackgroundColor3 = Color3.fromRGB(19, 27, 36),
				BackgroundTransparency = if CRAFTING_MENU_INNER_IMAGE_ID ~= "" then 1 else panelTransparency * 0.2,
				BorderSizePixel = 0,
				Image = CRAFTING_MENU_INNER_IMAGE_ID,
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				ImageTransparency = panelTransparency * 0.2,
				ZIndex = zIndex + 3,
			}, {
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 4),
				}),
				Status = e("TextLabel", {
					Name = "Status",
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					Text = resolveRecipeStatusText(selectedRecipe),
					Font = Enum.Font.GothamSemibold,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = if canCraftSelected then Color3.fromRGB(153, 243, 184) else Color3.fromRGB(239, 189, 189),
					TextStrokeTransparency = 0.55,
					ZIndex = zIndex + 4,
				}),
				Ingredients = e("Frame", {
					Name = "Ingredients",
					Size = UDim2.new(1, 0, 0, 44),
					Position = UDim2.fromOffset(0, 20),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = zIndex + 4,
				}, {
					ListLayout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						VerticalAlignment = Enum.VerticalAlignment.Top,
						Padding = UDim.new(0, 1),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Rows = e(React.Fragment, nil, ingredientRows),
				}),
			}),
			ActionButton = e(CraftingButton, {
				size = UDim2.new(1, -20, 0, 36),
				position = UDim2.fromOffset(10, 416),
				zIndex = zIndex + 4,
				disabled = not canCraftSelected,
				icon = ImageIds.finalCraftButton,
				iconPressed = ImageIds.finalCraftButtonPressed,
				text = if craftingState.isBulkCrafting then "Crafting..." else "Craft",
				onActivated = function()
					if canCraftSelected then
						craftingThunks.craftSelected(1)
					end
				end,
			}),
			LastResult = if craftingState.lastCraftResult ~= nil
				then e("TextLabel", {
					Name = "LastResult",
					Size = UDim2.new(1, -20, 0, 16),
					Position = UDim2.fromOffset(10, PANEL_HEIGHT - 18),
					BackgroundTransparency = 1,
					Text = if craftingState.lastCraftResult.success == true
						then "Craft complete"
						else ("Craft failed: " .. tostring(craftingState.lastCraftResult.reason or "unknown")),
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = if craftingState.lastCraftResult.success == true
						then Color3.fromRGB(164, 235, 168)
						else Color3.fromRGB(243, 168, 168),
					TextStrokeTransparency = 0.7,
					ZIndex = zIndex + 3,
				})
				else nil,
		}),
	})
end
