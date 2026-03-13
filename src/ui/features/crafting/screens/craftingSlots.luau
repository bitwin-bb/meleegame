--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local Gif = require(ReplicatedStorage.UI.shared.Gif)
local CraftingSlot = require(ReplicatedStorage.UI.features.crafting.components.craftingSlot)
local CraftingButton = require(ReplicatedStorage.UI.features.crafting.components.craftingButton)
local useCraftMenuDrag = require(ReplicatedStorage.UI.features.crafting.hooks.useCraftMenuDrag)
local useCraftSlide = require(ReplicatedStorage.UI.features.crafting.hooks.useCraftSlide)
local craftingSlice = require(ReplicatedStorage.UI.features.crafting.state.craftingSlice)
local craftingThunks = require(ReplicatedStorage.UI.features.crafting.state.craftingThunks)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)

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
local RECIPE_SLOT_SIZE = 80
local RECIPE_SLOT_PADDING = 8
local RECIPE_REQUIREMENT_SLOT_SIZE = 60
local RECIPE_REQUIREMENT_SLOT_PADDING = 8
local RECIPE_REQUIREMENT_ICON_SIZE = 30
local MENU_OPEN_SPRING = {
	frequency = 0.2,
	damping = 1,
}
local COIN_SPRITE_SHEET_KEY_BY_ITEM_ID = {
	CopperCoin = "copperCoin",
	SilverCoin = "silverCoin",
	GoldCoin = "goldCoin",
	PlatinumCoin = "platinumCoin",
}
local COIN_SHEET_SIZE = Vector2.new(1290, 774)
local COIN_FRAME_ROWS = 3
local COIN_FRAME_COLUMNS = 5
local COIN_FRAME_SIZE =
	Vector2.new(math.floor(COIN_SHEET_SIZE.X / COIN_FRAME_COLUMNS), math.floor(COIN_SHEET_SIZE.Y / COIN_FRAME_ROWS))
local COIN_FRAME_COUNT = COIN_FRAME_ROWS * COIN_FRAME_COLUMNS
local COIN_FPS = 12

local function resolveImageId(valueRaw: any, fallbackRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	if typeof(fallbackRaw) == "string" and fallbackRaw ~= "" then
		return fallbackRaw
	end
	return ""
end

local function resolveCoinSpriteSheet(itemIdRaw: any): string?
	local itemId = if typeof(itemIdRaw) == "string" then itemIdRaw else nil
	if itemId == nil then
		return nil
	end
	local spriteSheetKey = COIN_SPRITE_SHEET_KEY_BY_ITEM_ID[itemId]
	if spriteSheetKey == nil then
		return nil
	end
	local spriteSheets = if typeof(ImageIds.spriteSheets) == "table"
		then ImageIds.spriteSheets :: { [string]: any }
		else nil
	if spriteSheets == nil then
		return nil
	end
	local spriteSheet = spriteSheets[spriteSheetKey]
	if typeof(spriteSheet) ~= "string" or spriteSheet == "" then
		return nil
	end
	return spriteSheet
end

local CRAFTING_MENU_IMAGE_ID = resolveImageId(ImageIds.craftingMenu, "")
local CRAFTING_MENU_INNER_IMAGE_ID = resolveImageId(ImageIds.craftingMenuInner, CRAFTING_MENU_IMAGE_ID)
local CRAFTING_MENU_TEXTBOX_IMAGE_ID = resolveImageId(ImageIds.craftingMenuTextBox, CRAFTING_MENU_INNER_IMAGE_ID)
local CRAFTING_MENU_CATEGORY_IMAGE_ID = resolveImageId(ImageIds.craftingMenuCategory, CRAFTING_MENU_INNER_IMAGE_ID)
local resolveSelectedRecipeFromEntries: (entries: { CraftingRecipeEntry }, selectedRecipeIdRaw: any) -> CraftingRecipeEntry?

resolveSelectedRecipeFromEntries = function(
	entries: { CraftingRecipeEntry },
	selectedRecipeIdRaw: any
): CraftingRecipeEntry?
	local selectedRecipeId = if typeof(selectedRecipeIdRaw) == "string" and selectedRecipeIdRaw ~= ""
		then selectedRecipeIdRaw
		else nil
	if selectedRecipeId == nil then
		return nil
	end

	for _, entry in entries do
		if entry.recipeId == selectedRecipeId then
			return entry
		end
	end
	return nil
end

local function resolveBestRecipeEntry(entries: { CraftingRecipeEntry }): CraftingRecipeEntry?
	local preferred = nil :: CraftingRecipeEntry?
	for _, entry in entries do
		if preferred == nil then
			preferred = entry
			continue
		end
		if entry.canCraft ~= preferred.canCraft then
			if entry.canCraft then
				preferred = entry
			end
			continue
		end
		if entry.maxCraftableQuantity ~= preferred.maxCraftableQuantity then
			if entry.maxCraftableQuantity > preferred.maxCraftableQuantity then
				preferred = entry
			end
			continue
		end
		if entry.sortOrder ~= preferred.sortOrder then
			if entry.sortOrder < preferred.sortOrder then
				preferred = entry
			end
			continue
		end
		if entry.recipeId < preferred.recipeId then
			preferred = entry
		end
	end
	return preferred
end

local function pickPreferredRecipeEntry(
	entries: { CraftingRecipeEntry },
	selectedRecipeIdRaw: any
): CraftingRecipeEntry?
	local selectedRecipe = resolveSelectedRecipeFromEntries(entries, selectedRecipeIdRaw)
	if selectedRecipe ~= nil and selectedRecipe.canCraft then
		return selectedRecipe
	end

	local preferred = resolveBestRecipeEntry(entries)
	if preferred ~= nil then
		return preferred
	end

	return selectedRecipe
end

local function resolveDisplayRecipeGroups(
	entries: { CraftingRecipeEntry },
	categoryRaw: any,
	selectedRecipeIdRaw: any
): ({ CraftingRecipeEntry }, { [string]: { CraftingRecipeEntry } })
	local category = if typeof(categoryRaw) == "string" then categoryRaw else ""
	local shouldCollapseCurrencyResults = category == "" or category == "Currency"
	if not shouldCollapseCurrencyResults then
		local passthroughGroups = {} :: { [string]: { CraftingRecipeEntry } }
		for _, entry in entries do
			passthroughGroups[entry.recipeId] = { entry }
		end
		return entries, passthroughGroups
	end

	local groupedByResult = {} :: { [string]: { CraftingRecipeEntry } }
	local resultOrder = {} :: { string }
	for _, entry in entries do
		local isCurrencyRecipe = entry.category == "Currency"
		local groupKey = if isCurrencyRecipe
				and typeof(entry.resultItemId) == "string"
				and entry.resultItemId ~= ""
			then entry.resultItemId
			else entry.recipeId
		local group = groupedByResult[groupKey]
		if group == nil then
			group = {}
			groupedByResult[groupKey] = group
			resultOrder[#resultOrder + 1] = groupKey
		end
		group[#group + 1] = entry
	end

	local visibleEntries = {} :: { CraftingRecipeEntry }
	local groupsByVisibleRecipeId = {} :: { [string]: { CraftingRecipeEntry } }
	for _, groupKey in resultOrder do
		local group = groupedByResult[groupKey]
		if group ~= nil then
			local visibleEntry = pickPreferredRecipeEntry(group, selectedRecipeIdRaw)
			if visibleEntry ~= nil then
				visibleEntries[#visibleEntries + 1] = visibleEntry
				groupsByVisibleRecipeId[visibleEntry.recipeId] = group
			end
		end
	end

	table.sort(visibleEntries, function(lhs: CraftingRecipeEntry, rhs: CraftingRecipeEntry): boolean
		if lhs.sortOrder ~= rhs.sortOrder then
			return lhs.sortOrder < rhs.sortOrder
		end
		return lhs.recipeId < rhs.recipeId
	end)

	return visibleEntries, groupsByVisibleRecipeId
end

local function resolveDisplayedSelectedRecipe(
	displayedRecipes: { CraftingRecipeEntry },
	displayRecipeGroups: { [string]: { CraftingRecipeEntry } },
	selectedRecipeIdRaw: any
): CraftingRecipeEntry?
	local selectedRecipeId = if typeof(selectedRecipeIdRaw) == "string" and selectedRecipeIdRaw ~= ""
		then selectedRecipeIdRaw
		else nil
	if selectedRecipeId ~= nil then
		for _, visibleEntry in displayedRecipes do
			local visibleGroup = displayRecipeGroups[visibleEntry.recipeId]
			if visibleGroup ~= nil then
				for _, groupedEntry in visibleGroup do
					if groupedEntry.recipeId == selectedRecipeId then
						return visibleEntry
					end
				end
			elseif visibleEntry.recipeId == selectedRecipeId then
				return visibleEntry
			end
		end
	end

	return displayedRecipes[1]
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
		local required = if typeof(ingredient.required) == "number"
				and ingredient.required == ingredient.required
			then math.max(0, math.floor(ingredient.required))
			else 0
		local available = if typeof(ingredient.available) == "number"
				and ingredient.available == ingredient.available
			then math.max(0, math.floor(ingredient.available))
			else 0
		local isSufficient = ingredient.isSufficient == true

		local resolvedIcon = itemThunks.resolveItemIconByType(nil, itemId)
		local icon = if typeof(resolvedIcon) == "string" and resolvedIcon ~= ""
			then resolvedIcon
			else ImageIds.questionMark
		local coinSpriteSheet = resolveCoinSpriteSheet(itemId)

		rows["Ingredient_" .. tostring(index)] = e("ImageLabel", {
			Name = "Ingredient_" .. tostring(index),
			Size = UDim2.fromOffset(RECIPE_REQUIREMENT_SLOT_SIZE, RECIPE_REQUIREMENT_SLOT_SIZE),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Image = ImageIds.recipeIcon,
			ImageColor3 = if isSufficient then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(255, 207, 207),
			ZIndex = zIndex,
		}, {
			Icon = if coinSpriteSheet ~= nil
				then e(Gif, {
					name = "Icon",
					image = coinSpriteSheet,
					frameSize = COIN_FRAME_SIZE,
					frameCount = COIN_FRAME_COUNT,
					columns = COIN_FRAME_COLUMNS,
					startFrameIndex = 0,
					fps = COIN_FPS,
					size = UDim2.fromOffset(RECIPE_REQUIREMENT_ICON_SIZE, RECIPE_REQUIREMENT_ICON_SIZE),
					position = UDim2.fromScale(0.5, 0.5),
					anchorPoint = Vector2.new(0.5, 0.5),
					backgroundTransparency = 1,
					imageTransparency = 0,
					zIndex = zIndex + 1,
					resampleMode = Enum.ResamplerMode.Pixelated,
				})
				else e("ImageLabel", {
					Name = "Icon",
					Size = UDim2.fromOffset(RECIPE_REQUIREMENT_ICON_SIZE, RECIPE_REQUIREMENT_ICON_SIZE),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = icon,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = zIndex + 1,
				}),
			Amount = e("TextLabel", {
				Name = "Amount",
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 10),
				Position = UDim2.new(1, -2, 1, -2),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundTransparency = 1,
				Text = tostring(required),
				Font = Enum.Font.GothamBold,
				TextSize = 9,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = if isSufficient then Color3.fromRGB(157, 239, 182) else Color3.fromRGB(248, 172, 172),
				TextStrokeTransparency = 0.55,
				ZIndex = zIndex + 2,
			}),
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
	local displayedRecipes, displayRecipeGroups =
		resolveDisplayRecipeGroups(craftingState.recipes, activeCategory, craftingState.selectedRecipeId)
	local selectedRecipe =
		resolveDisplayedSelectedRecipe(displayedRecipes, displayRecipeGroups, craftingState.selectedRecipeId)
	local canCraftSelected = selectedRecipe ~= nil and selectedRecipe.canCraft
	local categoryTabs = { "All" }
	for _, category in craftingState.availableCategories do
		categoryTabs[#categoryTabs + 1] = category
	end

	local recipeChildren: { [string]: React.ReactNode } = {}
	for index, entry in displayedRecipes do
		local entryGroup = displayRecipeGroups[entry.recipeId]
		local isSelected = false
		if entryGroup ~= nil and craftingState.selectedRecipeId ~= nil then
			for _, groupedEntry in entryGroup do
				if groupedEntry.recipeId == craftingState.selectedRecipeId then
					isSelected = true
					break
				end
			end
		end
		recipeChildren["Recipe_" .. entry.recipeId] = e(CraftingSlot, {
			layoutOrder = index,
			zIndex = zIndex + 4,
			size = UDim2.fromOffset(RECIPE_SLOT_SIZE, RECIPE_SLOT_SIZE),
			recipe = entry,
			selected = isSelected,
			onActivated = function(recipeId: string)
				local nextRecipeId = recipeId
				local group = displayRecipeGroups[recipeId]
				if group ~= nil and #group > 1 and craftingState.selectedRecipeId ~= nil then
					local currentIndex = nil :: number?
					for groupedIndex, groupedEntry in group do
						if groupedEntry.recipeId == craftingState.selectedRecipeId then
							currentIndex = groupedIndex
							break
						end
					end
					if currentIndex ~= nil then
						local nextIndex = currentIndex + 1
						if nextIndex > #group then
							nextIndex = 1
						end
						nextRecipeId = group[nextIndex].recipeId
					end
				end
				craftingThunks.selectRecipe(nextRecipeId)
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

	local ingredientRows =
		buildIngredientRows(if selectedRecipe ~= nil then selectedRecipe.preview else nil, zIndex + 4)

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
					ScrollBarThickness = 10,
					ScrollBarImageColor3 = Color3.fromRGB(152, 158, 168),
					ScrollBarImageTransparency = 0.05,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					ScrollingDirection = Enum.ScrollingDirection.Y,
					VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
					ZIndex = zIndex + 4,
				}, {
					GridLayout = e("UIGridLayout", {
						CellSize = UDim2.fromOffset(RECIPE_SLOT_SIZE, RECIPE_SLOT_SIZE),
						CellPadding = UDim2.fromOffset(RECIPE_SLOT_PADDING, RECIPE_SLOT_PADDING),
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirectionMaxCells = 4,
					}),
					GridPadding = e("UIPadding", {
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 10),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
					}),
					Items = e(React.Fragment, nil, recipeChildren),
				}),
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
					PaddingTop = UDim.new(0, 6),
					PaddingBottom = UDim.new(0, 6),
				}),
				Ingredients = e("Frame", {
					Name = "Ingredients",
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = zIndex + 4,
				}, {
					GridLayout = e("UIGridLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						CellSize = UDim2.fromOffset(RECIPE_REQUIREMENT_SLOT_SIZE, RECIPE_REQUIREMENT_SLOT_SIZE),
						CellPadding = UDim2.fromOffset(
							RECIPE_REQUIREMENT_SLOT_PADDING,
							RECIPE_REQUIREMENT_SLOT_PADDING
						),
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
					if canCraftSelected and selectedRecipe ~= nil then
						craftingThunks.requestCraft(selectedRecipe.recipeId, 1)
					end
				end,
			}),
		}),
	})
end
