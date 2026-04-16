--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"

local function requireFromGameRoot(...: string): any
	local packageContainer = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	if packageContainer == nil then
		packageContainer = ReplicatedStorage:FindFirstChild(PACKAGE_NAME)
	end
	if packageContainer == nil then
		packageContainer = ReplicatedStorage:WaitForChild(PACKAGE_NAME, 5)
	end
	assert(packageContainer ~= nil, `Could not find the {PACKAGE_NAME} package container for Cmdr types.`)

	local current = packageContainer:FindFirstChild("game")
	assert(current ~= nil, `Could not find the "game" folder in {PACKAGE_NAME}.`)

	for index = 1, select("#", ...) do
		local segment = select(index, ...)
		current = current:FindFirstChild(segment)
		assert(current ~= nil, `Could not resolve Cmdr type dependency segment "{segment}".`)
	end

	return require(current)
end

local ItemRegistry = requireFromGameRoot("Shared", "Modules", "Items", "Registry")

type ItemAutocompleteEntry = {
	Name: string,
	ItemId: string,
}

local function getEntries(): { ItemAutocompleteEntry }
	local entries = {}
	local seen = {}
	local definitionsById = ItemRegistry.getDefinitionsById()

	for itemId, definition in definitionsById do
		if seen[itemId] == true then
			continue
		end

		seen[itemId] = true
		local displayName = if typeof(definition) == "table" and typeof((definition :: any).name) == "string"
			then (definition :: any).name
			else itemId
		entries[#entries + 1] = {
			Name = (`{displayName} [{itemId}]`),
			ItemId = itemId,
		}
	end

	table.sort(entries, function(a, b)
		return a.Name < b.Name
	end)

	return entries
end

return function(registry)
	local cmdrUtil = registry.Cmdr.Util

	registry:RegisterType("inventoryItem", {
		Transform = function(text: string)
			local entries = getEntries()
			local exactItemId = ItemRegistry.resolveCanonicalItemId(text)
			local findEntry = cmdrUtil.MakeFuzzyFinder(entries)
			local matches = findEntry(text)

			if exactItemId == nil then
				return matches
			end

			local exactEntry = nil :: ItemAutocompleteEntry?
			for _, entry in entries do
				if entry.ItemId == exactItemId then
					exactEntry = entry
					break
				end
			end

			if exactEntry == nil then
				return matches
			end

			local orderedMatches = { exactEntry }
			for _, entry in matches do
				if entry.ItemId ~= exactEntry.ItemId then
					orderedMatches[#orderedMatches + 1] = entry
				end
			end
			return orderedMatches
		end,

		Validate = function(items)
			return #items > 0, "No matching item was found."
		end,

		Autocomplete = function(items)
			return cmdrUtil.GetNames(items)
		end,

		Parse = function(items)
			return items[1].ItemId
		end,
	})
end
