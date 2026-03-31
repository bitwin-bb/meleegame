--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = {}

export type ItemDefinition = { [string]: any }

type RegistryData = {
	canonicalByAlias: { [string]: string },
	definitionsById: { [string]: ItemDefinition },
}

local cachedRegistry: RegistryData? = nil
local cachedItemsFolder: Folder? = nil
local cachedItemsFolderChildCount = -1
local NON_DEFINITION_MODULE_NAMES = {
	Animations = true,
	Audio = true,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeItemId(itemIdRaw: any): string?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return itemId
end

local function findItemsFolder(): Folder?
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if sharedFolder == nil or not sharedFolder:IsA("Folder") then
		return nil
	end

	local modulesFolder = sharedFolder:FindFirstChild("Modules")
	if modulesFolder == nil or not modulesFolder:IsA("Folder") then
		return nil
	end

	local itemsFolder = modulesFolder:FindFirstChild("Items")
	if itemsFolder == nil or not itemsFolder:IsA("Folder") then
		return nil
	end

	return itemsFolder
end

local function registerAlias(canonicalByAlias: { [string]: string }, aliasRaw: any, canonicalItemId: string)
	local alias = sanitizeItemId(aliasRaw)
	if alias == nil then
		return
	end

	canonicalByAlias[alias] = canonicalItemId
	local lowerAlias = string.lower(alias)
	if canonicalByAlias[lowerAlias] == nil then
		canonicalByAlias[lowerAlias] = canonicalItemId
	end

	local compactAlias = string.gsub(alias, "[%s_%-]+", "")
	if compactAlias ~= "" and canonicalByAlias[compactAlias] == nil then
		canonicalByAlias[compactAlias] = canonicalItemId
	end

	local lowerCompactAlias = string.lower(compactAlias)
	if lowerCompactAlias ~= "" and canonicalByAlias[lowerCompactAlias] == nil then
		canonicalByAlias[lowerCompactAlias] = canonicalItemId
	end
end

local function looksLikeDefinition(entry: { [any]: any }): boolean
	if entry.id ~= nil
		or entry.itemId ~= nil
		or entry.name ~= nil
		or entry.description ~= nil
		or entry.functionality ~= nil
		or entry.useCase ~= nil
		or entry.itemType ~= nil
		or entry.type ~= nil
		or entry.stats ~= nil
		or entry.value ~= nil
		or entry.damage ~= nil
		or entry.health ~= nil
		or entry.attack ~= nil
		or entry.defense ~= nil then
		return true
	end

	for _, value in entry do
		if typeof(value) ~= "table" then
			return true
		end
	end

	return false
end

local function collectDefinitions(sourceRaw: any, fallbackItemId: string?, registry: RegistryData)
	if typeof(sourceRaw) ~= "table" then
		return
	end

	local source = sourceRaw :: { [any]: any }
	local explicitItemId = sanitizeItemId(source.id) or sanitizeItemId(source.itemId)
	local canonicalItemId = explicitItemId or fallbackItemId
	if canonicalItemId ~= nil and looksLikeDefinition(source) then
		if registry.definitionsById[canonicalItemId] == nil then
			registry.definitionsById[canonicalItemId] = source
		end
		registerAlias(registry.canonicalByAlias, canonicalItemId, canonicalItemId)
		registerAlias(registry.canonicalByAlias, explicitItemId, canonicalItemId)
		registerAlias(registry.canonicalByAlias, source.id, canonicalItemId)
		registerAlias(registry.canonicalByAlias, source.itemId, canonicalItemId)
		registerAlias(registry.canonicalByAlias, source.name, canonicalItemId)
		return
	end

	for key, value in source do
		if typeof(key) ~= "string" or typeof(value) ~= "table" then
			continue
		end

		local nested = value :: { [any]: any }
		local nestedItemId = sanitizeItemId(nested.id) or sanitizeItemId(nested.itemId) or sanitizeItemId(key)
		collectDefinitions(nested, nestedItemId, registry)
	end
end

local function buildRegistry(): RegistryData
	local itemsFolder = findItemsFolder()
	if
		cachedRegistry ~= nil
		and itemsFolder ~= nil
		and cachedItemsFolder == itemsFolder
		and cachedItemsFolderChildCount == #itemsFolder:GetChildren()
	then
		return cachedRegistry
	end

	local registry: RegistryData = {
		canonicalByAlias = {},
		definitionsById = {},
	}
	local hadRequireFailure = false

	if itemsFolder ~= nil then
		cachedItemsFolder = itemsFolder
		cachedItemsFolderChildCount = #itemsFolder:GetChildren()

		for _, child in itemsFolder:GetChildren() do
			if not child:IsA("ModuleScript") or child == script or NON_DEFINITION_MODULE_NAMES[child.Name] == true then
				continue
			end

			local ok, moduleResult = pcall(require, child)
			if not ok then
				hadRequireFailure = true
				warn(("[ItemRegistry] Failed to require %s: %s"):format(child:GetFullName(), tostring(moduleResult)))
				continue
			end

			collectDefinitions(moduleResult, sanitizeItemId(child.Name), registry)
		end
	else
		cachedItemsFolder = nil
		cachedItemsFolderChildCount = -1
	end

	-- Published clients can hit this module before every dependency under
	-- ReplicatedStorage has fully replicated. If we cache a partial first scan,
	-- item definitions stay missing for the rest of the session. Only cache
	-- successful builds so later lookups can recover naturally.
	if hadRequireFailure then
		cachedRegistry = nil
	else
		cachedRegistry = registry
	end

	return registry
end

function Registry.resolveCanonicalItemId(itemIdRaw: any): string?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local registry = buildRegistry()
	return registry.canonicalByAlias[itemId] or registry.canonicalByAlias[string.lower(itemId)]
end

function Registry.resolveDefinition(itemIdRaw: any): ItemDefinition?
	local canonicalItemId = Registry.resolveCanonicalItemId(itemIdRaw)
	if canonicalItemId == nil then
		return nil
	end

	local registry = buildRegistry()
	return registry.definitionsById[canonicalItemId]
end

function Registry.getItemIdLookup(): { [string]: string }
	local lookup = {}
	for alias, canonicalItemId in buildRegistry().canonicalByAlias do
		lookup[alias] = canonicalItemId
	end
	return lookup
end

function Registry.getDefinitionsById(): { [string]: ItemDefinition }
	local definitions = {}
	for itemId, definition in buildRegistry().definitionsById do
		definitions[itemId] = definition
	end
	return definitions
end

function Registry.clearCache()
	cachedRegistry = nil
	cachedItemsFolder = nil
	cachedItemsFolderChildCount = -1
end

return Registry
