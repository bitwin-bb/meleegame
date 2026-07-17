local require = require(script.Parent.loader).load(script)

local EntityCatalog = require("EntityCatalog")

type EntityEntry = {
	Id: string,
	Kind: string,
	Name: string,
}

return function(registry)
	local cmdrUtil = registry.Cmdr.Util

	registry:RegisterType("entityToken", {
		Transform = function(text: string)
			local entries = EntityCatalog.GetAutocompleteEntries()
			local exactEntity = EntityCatalog.Get(text)
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
