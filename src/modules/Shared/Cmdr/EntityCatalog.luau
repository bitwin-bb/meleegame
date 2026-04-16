--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossService.BossServiceUtils)
local NpcDefinitions = require(script:FindFirstAncestor("game").Shared.Modules.Items.Npcs)

export type EntityKind = "Boss" | "Npc"
export type EntityEntry = {
	Id: string,
	Kind: EntityKind,
	Name: string,
	Tokens: { string },
	CanonicalToken: string,
}

local EntityCatalog = {}

local function normalizeToken(valueRaw: any): string
	return BossServiceUtils.normalizeToken(valueRaw)
end

local function cloneTokens(tokens: { string }): { string }
	local copy = table.create(#tokens)
	for index, token in tokens do
		copy[index] = token
	end
	return copy
end

local function cloneEntry(entry: EntityEntry): EntityEntry
	return {
		Id = entry.Id,
		Kind = entry.Kind,
		Name = entry.Name,
		Tokens = cloneTokens(entry.Tokens),
		CanonicalToken = entry.CanonicalToken,
	}
end

local function addUniqueToken(target: { string }, seen: { [string]: boolean }, tokenRaw: any)
	local token = normalizeToken(tokenRaw)
	if token == "" or seen[token] == true then
		return
	end

	seen[token] = true
	target[#target + 1] = token
end

local function buildEntries(): { EntityEntry }
	local entries = {}

	for _, bossEntry in BossServiceUtils.getRegistryEntries() do
		local tokens = {}
		local seen = {}
		for _, token in bossEntry.manualSummonTokens do
			addUniqueToken(tokens, seen, token)
		end
		addUniqueToken(tokens, seen, bossEntry.id)
		addUniqueToken(tokens, seen, bossEntry.displayName)

		entries[#entries + 1] = {
			Id = bossEntry.id,
			Kind = "Boss",
			Name = bossEntry.displayName,
			Tokens = tokens,
			CanonicalToken = tokens[1] or normalizeToken(bossEntry.id),
		}
	end

	if typeof(NpcDefinitions) == "table" then
		for npcId, definition in NpcDefinitions do
			if typeof(npcId) ~= "string" then
				continue
			end

			local displayName = if typeof(definition) == "table" and typeof((definition :: any).name) == "string"
				then (definition :: any).name
				else npcId

			local tokens = {}
			local seen = {}
			addUniqueToken(tokens, seen, npcId)
			addUniqueToken(tokens, seen, displayName)

			entries[#entries + 1] = {
				Id = npcId,
				Kind = "Npc",
				Name = displayName,
				Tokens = tokens,
				CanonicalToken = tokens[1] or normalizeToken(npcId),
			}
		end
	end

	table.sort(entries, function(left, right)
		if left.Kind ~= right.Kind then
			return left.Kind < right.Kind
		end
		return left.Name < right.Name
	end)

	return entries
end

local ENTRIES = buildEntries()

function EntityCatalog.GetEntries(): { EntityEntry }
	local copy = table.create(#ENTRIES)
	for index, entry in ENTRIES do
		copy[index] = cloneEntry(entry)
	end
	return copy
end

function EntityCatalog.Resolve(tokenRaw: any): EntityEntry?
	local normalizedToken = normalizeToken(tokenRaw)
	if normalizedToken == "" then
		return nil
	end

	for _, entry in ENTRIES do
		for _, token in entry.Tokens do
			if token == normalizedToken then
				return cloneEntry(entry)
			end
		end
	end

	return nil
end

function EntityCatalog.GetAutocompleteEntries(): { { Name: string, Entity: EntityEntry } }
	local entries = table.create(#ENTRIES)
	for index, entry in ENTRIES do
		entries[index] = {
			Name = (`{entry.Name} [{string.lower(entry.Kind)}]`),
			Entity = cloneEntry(entry),
		}
	end
	return entries
end

EntityCatalog.getEntries = EntityCatalog.GetEntries
EntityCatalog.resolve = EntityCatalog.Resolve
EntityCatalog.getAutocompleteEntries = EntityCatalog.GetAutocompleteEntries

return EntityCatalog
