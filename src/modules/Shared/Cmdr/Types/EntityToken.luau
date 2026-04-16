--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"

local function resolveGameRoot(): Instance
	local directGameRoot = script:FindFirstAncestor("game")
	if directGameRoot ~= nil then
		return directGameRoot
	end

	local serverPackage = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	if serverPackage ~= nil then
		local serverGameRoot = serverPackage:FindFirstChild("game")
		if serverGameRoot ~= nil then
			return serverGameRoot
		end
	end

	local replicatedPackage = ReplicatedStorage:FindFirstChild(PACKAGE_NAME) or ReplicatedStorage:WaitForChild(PACKAGE_NAME, 5)
	if replicatedPackage ~= nil then
		local replicatedGameRoot = replicatedPackage:FindFirstChild("game")
		if replicatedGameRoot ~= nil then
			return replicatedGameRoot
		end
	end

	error("Missing Nevermore game root for EntityToken.")
end

local gameRoot = resolveGameRoot()

local EntityCatalog = require(gameRoot.Shared.Cmdr.EntityCatalog)

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
