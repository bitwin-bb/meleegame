--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local CategoryTabs = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.CategoryTabs)
local CraftingButton = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.craftingButton)
local CraftingPanel = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.CraftingPanel)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local IngredientSlot = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.IngredientSlot)
local Layer = require(script:FindFirstAncestor("game").Client.UI.shared.Layer)
local React = require(ReplicatedStorage.Packages.React)
local RecipeDetails = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.RecipeDetails)
local RecipeGrid = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.RecipeGrid)
local RecipeSlot = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.RecipeSlot)
local Responsive = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useViewportScale)
local SearchBox = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.components.SearchBox)
local UiScaleUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.UiScaleUtils)
local UiSound = require(script:FindFirstAncestor("game").Client.UI.core.utils.UiSound)
local craftingSlice = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.state.craftingSlice)
local craftingThunks = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.state.craftingThunks)
local itemThunks = require(script:FindFirstAncestor("game").Shared.Features.item.ui.state.itemThunks)
local resolveImageId = require(script:FindFirstAncestor("game").Client.UI.core.utils.resolveImageId)
local useCraftMenuDrag = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.hooks.useCraftMenuDrag)
local useCraftSlide = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.hooks.useCraftSlide)
local useDebounceValue = require(script:FindFirstAncestor("game").Client.UI.shared.useDebounceValue)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type CraftingState = craftingSlice.CraftingState
type CraftingRecipeEntry = craftingSlice.CraftingRecipeEntry

type CraftingSlotsProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

local MISSING_ASSET_ERROR = "no asset found!"
local PANEL_OPEN_START_OFFSET = Vector2.new(0, 96)
local PANEL_MIN_SCALE = 0.2
local RECIPE_SLOT_PADDING = 8
local RECIPE_REQUIREMENT_SLOT_PADDING = 8
local SEARCH_DEBOUNCE_SECONDS = 0.15
local MENU_OPEN_SPRING = {
	frequency = 0.2,
	damping = 1,
}

local function playUiSound(soundAssetId: string?)
	UiSound.play(soundAssetId)
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

	visibleEntries = Sift.Array.sort(
		visibleEntries,
		function(lhs: CraftingRecipeEntry, rhs: CraftingRecipeEntry): boolean
			if lhs.sortOrder ~= rhs.sortOrder then
				return lhs.sortOrder < rhs.sortOrder
			end
			return lhs.recipeId < rhs.recipeId
		end
	)

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

local function buildIngredientRows(
	previewRaw: any,
	zIndex: number,
	requirementSlotSize: number,
	requirementIconSize: number
): { React.ReactNode }
	local rows: { React.ReactNode } = {}
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
		local isSufficient = ingredient.isSufficient == true

		local resolvedIcon = itemThunks.resolveItemIconByType(nil, itemId)
		if typeof(resolvedIcon) ~= "string" or resolvedIcon == "" then
			error(MISSING_ASSET_ERROR, 0)
		end

		rows[#rows + 1] = e(IngredientSlot, {
			layoutOrder = index,
			itemId = itemId,
			required = required,
			isSufficient = isSufficient,
			icon = resolvedIcon,
			size = UDim2.fromOffset(requirementSlotSize, requirementSlotSize),
			iconSize = UDim2.fromOffset(requirementIconSize, requirementIconSize),
			zIndex = zIndex,
		})
	end

	return rows
end

return function(props: CraftingSlotsProps): React.ReactNode
	local responsive = Responsive.useResponsiveMetrics()
	local craftingTokens = responsive.tokens.crafting
	local craftingState = (useStore(craftingSlice.craftingStateAtom) :: CraftingState?)
		or craftingSlice.getCraftingState()
	local searchText, setSearchText = React.useState(function(): string
		return craftingState.searchQuery
	end)
	local lastAppliedSearchQueryRef = React.useRef(craftingState.searchQuery)
	local searchQueryCommitInFlightRef = React.useRef(false)
	local debouncedSearchText = useDebounceValue(searchText, SEARCH_DEBOUNCE_SECONDS)

	local function commitSearchQuery(nextSearchText: string)
		if nextSearchText == lastAppliedSearchQueryRef.current then
			return
		end

		lastAppliedSearchQueryRef.current = nextSearchText
		searchQueryCommitInFlightRef.current = true
		craftingThunks.setSearchQuery(nextSearchText)
	end

	React.useEffect(function()
		local stop = craftingThunks.start()

		return function()
			craftingThunks.stopBulkCraft()
			stop()
		end
	end, {})

	React.useEffect(function()
		if debouncedSearchText ~= searchText then
			return
		end

		commitSearchQuery(debouncedSearchText)
	end, { debouncedSearchText, searchText })

	React.useEffect(function()
		if searchQueryCommitInFlightRef.current then
			if craftingState.searchQuery == lastAppliedSearchQueryRef.current then
				searchQueryCommitInFlightRef.current = false
			end
			return
		end

		if craftingState.searchQuery == lastAppliedSearchQueryRef.current then
			return
		end

		lastAppliedSearchQueryRef.current = craftingState.searchQuery
		setSearchText(craftingState.searchQuery)
	end, { craftingState.searchQuery })

	local isRequestedVisible = props.visible ~= false
	local isOpen = isRequestedVisible and craftingState.visible
	local craftMenuDrag = useCraftMenuDrag({
		enabled = isOpen,
		dragSmoothness = 16,
	})
	local lastCraftResultUpdatedAtRef = React.useRef(nil :: number?)
	local wasDraggingRef = React.useRef(false)
	local slideProgress = useCraftSlide({
		enabled = isOpen,
		spring = MENU_OPEN_SPRING,
	})

	React.useEffect(function()
		local lastCraftResult = craftingState.lastCraftResult
		if typeof(lastCraftResult) ~= "table" then
			return
		end

		local updatedAt = (lastCraftResult :: any).updatedAt
		if typeof(updatedAt) ~= "number" or updatedAt ~= updatedAt then
			return
		end
		if lastCraftResultUpdatedAtRef.current == updatedAt then
			return
		end

		lastCraftResultUpdatedAtRef.current = updatedAt
		if (lastCraftResult :: any).success == true then
			playUiSound(UiSound.craft)
		end
	end, { craftingState.lastCraftResult })

	React.useEffect(function()
		local wasDragging = wasDraggingRef.current
		wasDraggingRef.current = craftMenuDrag.isDragging
		if craftMenuDrag.isDragging and not wasDragging then
			playUiSound(UiSound.drag)
		end
	end, { craftMenuDrag.isDragging })

	if not isOpen and slideProgress <= 0.001 then
		return nil
	end

	local zIndex = props.zIndex or 180
	local responsivePanelScale = craftingTokens.panelScale
	local destinationOffset = UiScaleUtils.clampCenteredPanelOffset(
		craftMenuDrag.offset,
		Vector2.new(craftingTokens.panelWidth, craftingTokens.panelHeight),
		responsivePanelScale,
		responsive
	)
	local sourceOffset = destinationOffset + PANEL_OPEN_START_OFFSET * responsivePanelScale
	local animatedOffset = sourceOffset:Lerp(destinationOffset, slideProgress)
	local pathLength = (PANEL_OPEN_START_OFFSET * responsivePanelScale).Magnitude
	local remainingDistance = (destinationOffset - animatedOffset).Magnitude
	local panelTransparency = if pathLength > 0
		then math.clamp(remainingDistance / pathLength, 0, 1)
		else math.clamp(1 - slideProgress, 0, 1)
	local panelScale = responsivePanelScale * (PANEL_MIN_SCALE + (1 - PANEL_MIN_SCALE) * (1 - panelTransparency))
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

	local recipeChildren: { React.ReactNode } = {}
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
		recipeChildren[#recipeChildren + 1] = e(RecipeSlot, {
			layoutOrder = index,
			zIndex = zIndex + 4,
			size = UDim2.fromOffset(craftingTokens.recipeSlotSize, craftingTokens.recipeSlotSize),
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

	local ingredientRows = buildIngredientRows(
		if selectedRecipe ~= nil then selectedRecipe.preview else nil,
		zIndex + 4,
		craftingTokens.requirementSlotSize,
		craftingTokens.iconSize
	)

	return e(Layer, {
		layoutOrder = props.layoutOrder or 12,
		zIndex = zIndex,
		visible = isRequestedVisible,
		children = {
			e(CraftingPanel, {
				size = UDim2.fromOffset(craftingTokens.panelWidth, craftingTokens.panelHeight),
				position = UDim2.new(0.5, math.floor(animatedOffset.X), 0.5, math.floor(animatedOffset.Y)),
				anchorPoint = Vector2.new(0.5, 0.5),
				scale = panelScale,
				panelImage = CRAFTING_MENU_IMAGE_ID,
				panelTransparency = panelTransparency,
				zIndex = zIndex + 1,
				onDragInputBegan = function(rbx: GuiObject, inputObject: InputObject)
					craftMenuDrag.onDragInputBegan(rbx, inputObject)
				end,
				onDragInputEnded = function(rbx: GuiObject, inputObject: InputObject)
					craftMenuDrag.onDragInputEnded(rbx, inputObject)
				end,
				children = {
					e(SearchBox, {
						text = searchText,
						image = CRAFTING_MENU_TEXTBOX_IMAGE_ID,
						panelTransparency = panelTransparency,
						zIndex = zIndex + 3,
						position = UDim2.fromOffset(craftingTokens.panelPadding, craftingTokens.searchY),
						size = UDim2.new(1, -craftingTokens.panelPadding * 2, 0, 28),
						textSize = craftingTokens.textSize + 1,
						onTextChanged = setSearchText,
						onFocusLost = function()
							commitSearchQuery(searchText)
						end,
					}),
					e(CategoryTabs, {
						categories = categoryTabs,
						activeCategory = activeCategory,
						categoryImage = CRAFTING_MENU_CATEGORY_IMAGE_ID,
						panelTransparency = panelTransparency,
						zIndex = zIndex + 3,
						position = UDim2.fromOffset(craftingTokens.panelPadding, craftingTokens.categoryY),
						size = UDim2.new(1, -craftingTokens.panelPadding * 2, 0, 26),
						tabPadding = UDim.new(0, 4),
						textSize = craftingTokens.textSize,
						onActivated = function(categoryValue: string)
							craftingThunks.setCategoryFilter(categoryValue)
						end,
					}),
					e(RecipeGrid, {
						image = CRAFTING_MENU_INNER_IMAGE_ID,
						panelTransparency = panelTransparency,
						position = UDim2.fromOffset(craftingTokens.panelPadding, craftingTokens.recipeGridY),
						size = UDim2.new(1, -craftingTokens.panelPadding * 2, 0, 240),
						slotSize = craftingTokens.recipeSlotSize,
						slotPadding = RECIPE_SLOT_PADDING,
						zIndex = zIndex + 3,
						children = recipeChildren,
					}),
					e(RecipeDetails, {
						image = CRAFTING_MENU_INNER_IMAGE_ID,
						panelTransparency = panelTransparency,
						position = UDim2.fromOffset(craftingTokens.panelPadding, craftingTokens.recipeDetailsY),
						size = UDim2.new(1, -craftingTokens.panelPadding * 2, 0, 64),
						slotSize = craftingTokens.requirementSlotSize,
						slotPadding = RECIPE_REQUIREMENT_SLOT_PADDING,
						zIndex = zIndex + 3,
						children = ingredientRows,
					}),
					e(CraftingButton, {
						size = UDim2.new(1, -craftingTokens.panelPadding * 2, 0, craftingTokens.craftButtonHeight),
						position = UDim2.fromOffset(craftingTokens.panelPadding, craftingTokens.craftButtonY),
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
				},
			}),
		},
	})
end
