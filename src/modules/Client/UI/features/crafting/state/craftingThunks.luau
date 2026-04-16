--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local craftingSlice = require(script:FindFirstAncestor("game").Client.UI.features.crafting.state.craftingSlice)
local CraftingServiceClient = require(script:FindFirstAncestor("game").Client.Services.CraftingService.CraftingServiceClient)

type CraftingState = craftingSlice.CraftingState

local craftingThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeQuantity(quantityRaw: any): number
	local quantity = 1
	if typeof(quantityRaw) == "number" and quantityRaw == quantityRaw then
		quantity = math.floor(quantityRaw)
	elseif typeof(quantityRaw) == "string" then
		local parsed = tonumber(trim(quantityRaw))
		if parsed ~= nil and parsed == parsed then
			quantity = math.floor(parsed)
		end
	end
	return math.clamp(quantity, 1, 99)
end

local function toStringArrayFromSet(setRaw: any): { string }
	local output: { string } = {}
	if typeof(setRaw) ~= "table" then
		return output
	end
	for key, value in setRaw do
		if typeof(key) == "string" and value == true then
			output[#output + 1] = key
		end
	end
	return Sift.Array.sort(output)
end

local function applyFromService(): CraftingState
	local currentState = craftingSlice.getCraftingState()

	local serviceState: { [string]: any } = {}
	local didReadState = pcall(function()
		serviceState = CraftingServiceClient:getState()
	end)
	if not didReadState then
		serviceState = {}
	end

	local searchQuery = currentState.searchQuery
	local categoryFilter = currentState.categoryFilter
	if typeof(serviceState.searchQuery) == "string" then
		searchQuery = serviceState.searchQuery
	end
	if typeof(serviceState.categoryFilter) == "string" then
		categoryFilter = serviceState.categoryFilter
	end

	local recipes: { [string]: any } = {}
	local didReadRecipes = pcall(function()
		recipes = CraftingServiceClient:getRecipes({
			category = categoryFilter,
			searchText = searchQuery,
		})
	end)
	if not didReadRecipes then
		recipes = {}
	end

	local availableCategories = if typeof(serviceState.availableCategories) == "table" then serviceState.availableCategories else {}
	local activeStations = toStringArrayFromSet(serviceState.activeStations)
	local selectedRecipeId = currentState.selectedRecipeId
	if typeof(selectedRecipeId) ~= "string" or selectedRecipeId == "" then
		selectedRecipeId = nil
	end
	if selectedRecipeId == nil and #recipes > 0 then
		selectedRecipeId = recipes[1].recipeId
	end

	return craftingSlice.applyServiceSnapshot({
		started = true,
		searchQuery = searchQuery,
		categoryFilter = categoryFilter,
		selectedRecipeId = selectedRecipeId,
		availableCategories = availableCategories,
		recipes = recipes,
		activeStations = activeStations,
		isBulkCrafting = serviceState.isBulkCrafting == true,
		lastCraftResult = if typeof(serviceState.lastCraftResult) == "table" then serviceState.lastCraftResult else nil,
	})
end

local function ensureStarted()
	if runtime.started then
		return
	end
	craftingThunks.Start()
end

function craftingThunks.Start(): () -> ()
	if runtime.started then
		return craftingThunks.Stop
	end

	runtime.started = true
	applyFromService()

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(CraftingServiceClient, function()
		applyFromService()
	end)
	ServiceSync.requestSync(CraftingServiceClient)

	return craftingThunks.Stop
end

function craftingThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
	craftingSlice.setCraftingState({
		started = false,
		isBulkCrafting = false,
	})
end

function craftingThunks.Refresh(): CraftingState
	ensureStarted()
	return applyFromService()
end

function craftingThunks.ToggleVisible(): CraftingState
	ensureStarted()
	return craftingSlice.toggleVisible()
end

function craftingThunks.SetVisible(visibleRaw: any): CraftingState
	ensureStarted()
	return craftingSlice.setVisible(visibleRaw)
end

function craftingThunks.SetSearchQuery(searchQueryRaw: any): CraftingState
	ensureStarted()
	local nextState = craftingSlice.setSearchQuery(searchQueryRaw)
	pcall(function()
		CraftingServiceClient:setSearchQuery(nextState.searchQuery)
	end)
	return applyFromService()
end

function craftingThunks.SetCategoryFilter(categoryRaw: any): CraftingState
	ensureStarted()
	local nextState = craftingSlice.setCategoryFilter(categoryRaw)
	pcall(function()
		CraftingServiceClient:setCategoryFilter(nextState.categoryFilter)
	end)
	return applyFromService()
end

function craftingThunks.SelectRecipe(recipeIdRaw: any): CraftingState
	ensureStarted()
	return craftingSlice.setSelectedRecipeId(recipeIdRaw)
end

function craftingThunks.RequestCraft(recipeIdRaw: any, quantityRaw: any): boolean
	ensureStarted()
	local recipeId = trim(recipeIdRaw)
	if recipeId == "" then
		return false
	end

	local quantity = sanitizeQuantity(quantityRaw)
	local didSend = false
	pcall(function()
		didSend = CraftingServiceClient:requestCraft(recipeId, quantity) == true
	end)
	task.defer(applyFromService)
	return didSend
end

function craftingThunks.CraftSelected(quantityRaw: any): boolean
	ensureStarted()
	local currentState = craftingSlice.getCraftingState()
	local selectedRecipeId = currentState.selectedRecipeId
	if selectedRecipeId == nil or selectedRecipeId == "" then
		return false
	end
	return craftingThunks.RequestCraft(selectedRecipeId, quantityRaw)
end

function craftingThunks.StartBulkCraftSelected(quantityRaw: any): boolean
	ensureStarted()
	local currentState = craftingSlice.getCraftingState()
	local selectedRecipeId = currentState.selectedRecipeId
	if selectedRecipeId == nil or selectedRecipeId == "" then
		return false
	end

	local quantity = sanitizeQuantity(quantityRaw)
	local didStart = false
	pcall(function()
		didStart = CraftingServiceClient:startBulkCraft(selectedRecipeId, quantity) == true
	end)
	task.defer(applyFromService)
	return didStart
end

function craftingThunks.StopBulkCraft(): boolean
	ensureStarted()
	local didStop = false
	pcall(function()
		didStop = CraftingServiceClient:stopBulkCraft() == true
	end)
	task.defer(applyFromService)
	return didStop
end

function craftingThunks.GetCraftingState(): CraftingState
	return craftingSlice.getCraftingState()
end

craftingThunks.start = craftingThunks.Start
craftingThunks.stop = craftingThunks.Stop
craftingThunks.refresh = craftingThunks.Refresh
craftingThunks.toggleVisible = craftingThunks.ToggleVisible
craftingThunks.setVisible = craftingThunks.SetVisible
craftingThunks.setSearchQuery = craftingThunks.SetSearchQuery
craftingThunks.setCategoryFilter = craftingThunks.SetCategoryFilter
craftingThunks.selectRecipe = craftingThunks.SelectRecipe
craftingThunks.requestCraft = craftingThunks.RequestCraft
craftingThunks.craftSelected = craftingThunks.CraftSelected
craftingThunks.startBulkCraftSelected = craftingThunks.StartBulkCraftSelected
craftingThunks.stopBulkCraft = craftingThunks.StopBulkCraft
craftingThunks.getCraftingState = craftingThunks.GetCraftingState

return craftingThunks
