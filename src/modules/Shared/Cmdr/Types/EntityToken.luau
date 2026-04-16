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

local EntityCatalog = requireFromGameRoot("Shared", "Cmdr", "EntityCatalog")

type EntityEntry = EntityCatalog.EntityEntry

return function(registry)
	local cmdrUtil = registry.Cmdr.Util

	registry:RegisterType("entityToken", {
		Transform = function(text: string)
			local entries = EntityCatalog.getAutocompleteEntries()
			local exactEntity = EntityCatalog.resolve(text)
			local fuzzyFinder = cmdrUtil.MakeFuzzyFinder(entries)
			local matches = fuzzyFinder(text)

			if exactEntity == nil then
				return matches
			end

			local exactEntry = nil :: { Name: string, Entity: EntityEntry }?
			for _, entry in entries do
				if entry.Entity.Id == exactEntity.Id and entry.Entity.Kind == exactEntity.Kind then
					exactEntry = entry
					break
				end
			end

			if exactEntry == nil then
				return matches
			end

			local orderedMatches = { exactEntry }
			for _, entry in matches do
				if entry.Entity.Id ~= exactEntry.Entity.Id or entry.Entity.Kind ~= exactEntry.Entity.Kind then
					orderedMatches[#orderedMatches + 1] = entry
				end
			end

			return orderedMatches
		end,

		Validate = function(items)
			return #items > 0, "No matching entity was found."
		end,

		Autocomplete = function(items)
			return cmdrUtil.GetNames(items)
		end,

		Parse = function(items)
			return items[1].Entity
		end,
	})
end
