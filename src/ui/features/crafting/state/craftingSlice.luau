--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type CraftingRecipeEntry = {
	recipeId: string,
	displayName: string,
	category: string,
	resultItemId: string?,
	canCraft: boolean,
	maxCraftableQuantity: number,
	groupId: string?,
	sortOrder: number,
	preview: { [string]: any }?,
}

export type CraftingState = {
	started: boolean,
	visible: boolean,
	searchQuery: string,
	categoryFilter: string,
	selectedRecipeId: string?,
	availableCategories: { string },
	recipes: { CraftingRecipeEntry },
	activeStations: { string },
	isBulkCrafting: boolean,
	lastCraftResult: { [string]: any }?,
	updatedAt: number,
}

local DEFAULT_STATE: CraftingState = {
	started = false,
	visible = false,
	searchQuery = "",
	categoryFilter = "",
	selectedRecipeId = nil,
	availableCategories = {},
	recipes = {},
	activeStations = {},
	isBulkCrafting = false,
	lastCraftResult = nil,
	updatedAt = os.clock(),
}

local craftingStateAtom: Charm.Atom<CraftingState> = Charm.atom(DEFAULT_STATE)

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function cloneStringArray(arrayRaw: any): { string }
	local output: { string } = {}
	if typeof(arrayRaw) ~= "table" then
		return output
	end
	for _, valueRaw in arrayRaw do
		local value = trim(valueRaw)
		if value ~= "" then
			output[#output + 1] = value
		end
	end
	return output
end

local function sanitizeRecipeEntries(entriesRaw: any): { CraftingRecipeEntry }
	local output: { CraftingRecipeEntry } = {}
	if typeof(entriesRaw) ~= "table" then
		return output
	end

	for index, entryRaw in entriesRaw do
		if typeof(entryRaw) ~= "table" then
			continue
		end
		local entry = entryRaw :: { [string]: any }
		local recipeId = trim(entry.recipeId)
		if recipeId == "" then
			continue
		end

		local displayName = trim(entry.displayName)
		if displayName == "" then
			displayName = recipeId
		end
		local category = trim(entry.category)
		if category == "" then
			category = "Misc"
		end

		output[#output + 1] = {
			recipeId = recipeId,
			displayName = displayName,
			category = category,
			resultItemId = if trim(entry.resultItemId) ~= "" then trim(entry.resultItemId) else nil,
			canCraft = entry.canCraft == true,
			maxCraftableQuantity = sanitizeInteger(entry.maxCraftableQuantity, 0, 0, 999_999),
			groupId = if trim(entry.groupId) ~= "" then trim(entry.groupId) else nil,
			sortOrder = sanitizeInteger(entry.sortOrder, index, -999_999, 999_999),
			preview = if typeof(entry.preview) == "table" then entry.preview else nil,
		}
	end

	return output
end

local function cloneRecipeEntries(entriesRaw: { CraftingRecipeEntry }): { CraftingRecipeEntry }
	local output: { CraftingRecipeEntry } = table.create(#entriesRaw)
	for index, entry in entriesRaw do
		output[index] = {
			recipeId = entry.recipeId,
			displayName = entry.displayName,
			category = entry.category,
			resultItemId = entry.resultItemId,
			canCraft = entry.canCraft,
			maxCraftableQuantity = entry.maxCraftableQuantity,
			groupId = entry.groupId,
			sortOrder = entry.sortOrder,
			preview = if typeof(entry.preview) == "table" then table.clone(entry.preview) else nil,
		}
	end
	return output
end

local function hasRecipeId(entries: { CraftingRecipeEntry }, recipeId: string): boolean
	for _, entry in entries do
		if entry.recipeId == recipeId then
			return true
		end
	end
	return false
end

local function normalizeSelectedRecipeId(
	entries: { CraftingRecipeEntry },
	selectedRecipeIdRaw: any,
	fallbackRecipeId: string?
): string?
	local selectedRecipeId = trim(selectedRecipeIdRaw)
	if selectedRecipeId ~= "" and hasRecipeId(entries, selectedRecipeId) then
		return selectedRecipeId
	end

	local fallback = trim(fallbackRecipeId)
	if fallback ~= "" and hasRecipeId(entries, fallback) then
		return fallback
	end

	if #entries <= 0 then
		return nil
	end
	return entries[1].recipeId
end

local function getCraftingState(): CraftingState
	return craftingStateAtom()
end

local function setCraftingState(stateRaw: any): CraftingState
	local current = craftingStateAtom()
	local source = if typeof(stateRaw) == "table" then (stateRaw :: { [string]: any }) else {}
	local nextRecipes = if source.recipes ~= nil then sanitizeRecipeEntries(source.recipes) else cloneRecipeEntries(current.recipes)
	local nextAvailableCategories = if source.availableCategories ~= nil
		then cloneStringArray(source.availableCategories)
		else cloneStringArray(current.availableCategories)
	local nextActiveStations = if source.activeStations ~= nil
		then cloneStringArray(source.activeStations)
		else cloneStringArray(current.activeStations)

	local nextSelectedRecipeId = normalizeSelectedRecipeId(
		nextRecipes,
		if source.selectedRecipeId ~= nil then source.selectedRecipeId else current.selectedRecipeId,
		current.selectedRecipeId
	)

	local nextState: CraftingState = {
		started = sanitizeBoolean(source.started, current.started),
		visible = sanitizeBoolean(source.visible, current.visible),
		searchQuery = if source.searchQuery ~= nil then trim(source.searchQuery) else current.searchQuery,
		categoryFilter = if source.categoryFilter ~= nil then trim(source.categoryFilter) else current.categoryFilter,
		selectedRecipeId = nextSelectedRecipeId,
		availableCategories = nextAvailableCategories,
		recipes = nextRecipes,
		activeStations = nextActiveStations,
		isBulkCrafting = sanitizeBoolean(source.isBulkCrafting, current.isBulkCrafting),
		lastCraftResult = if typeof(source.lastCraftResult) == "table"
			then source.lastCraftResult
			else if source.lastCraftResult == nil then current.lastCraftResult else nil,
		updatedAt = os.clock(),
	}
	craftingStateAtom(nextState)
	return nextState
end

local function applyServiceSnapshot(snapshotRaw: any): CraftingState
	return setCraftingState(snapshotRaw)
end

local function resetCraftingState(): CraftingState
	local nextState: CraftingState = {
		started = false,
		visible = false,
		searchQuery = "",
		categoryFilter = "",
		selectedRecipeId = nil,
		availableCategories = {},
		recipes = {},
		activeStations = {},
		isBulkCrafting = false,
		lastCraftResult = nil,
		updatedAt = os.clock(),
	}
	craftingStateAtom(nextState)
	return nextState
end

local function setVisible(visibleRaw: any): CraftingState
	return setCraftingState({
		visible = visibleRaw == true,
	})
end

local function toggleVisible(): CraftingState
	local current = craftingStateAtom()
	return setCraftingState({
		visible = not current.visible,
	})
end

local function setSearchQuery(searchQueryRaw: any): CraftingState
	return setCraftingState({
		searchQuery = searchQueryRaw,
	})
end

local function setCategoryFilter(categoryRaw: any): CraftingState
	return setCraftingState({
		categoryFilter = categoryRaw,
	})
end

local function setSelectedRecipeId(recipeIdRaw: any): CraftingState
	return setCraftingState({
		selectedRecipeId = recipeIdRaw,
	})
end

return {
	craftingStateAtom = craftingStateAtom,
	getCraftingState = getCraftingState,
	setCraftingState = setCraftingState,
	applyServiceSnapshot = applyServiceSnapshot,
	resetCraftingState = resetCraftingState,
	setVisible = setVisible,
	toggleVisible = toggleVisible,
	setSearchQuery = setSearchQuery,
	setCategoryFilter = setCategoryFilter,
	setSelectedRecipeId = setSelectedRecipeId,
}
