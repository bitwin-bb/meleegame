local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StringUtils = require(script:FindFirstAncestor("game").Shared.Modules.Core.StringUtils)
local InstanceUtils = require(script:FindFirstAncestor("game").Shared.Modules.Platform.InstanceUtils)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local ResolveToolInstance = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveToolInstance)
local LootServiceData = require(script:FindFirstAncestor("game").Shared.Services.LootService.Data)
local LootServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LootService.LootServiceUtils)

local ResolveItem = {}

export type ItemTemplateResolution = {
	primaryTemplate: Instance?,
	toolTemplate: Tool?,
}

type CachedResolution = {
	primaryTemplate: Instance | boolean,
	toolTemplate: Tool | boolean,
}

local assetSearchRootsCache = nil :: { Instance }?
local resolutionCacheByItemId = {} :: { [string]: CachedResolution }
local ITEM_VARIANT_BRANCH_NAMES = {
	model = true,
	tool = true,
}

local function sanitizeItemId(itemIdRaw: any): string?
	return StringUtils.sanitize(itemIdRaw, nil)
end

local function appendUniqueString(target: { string }, seen: { [string]: boolean }, valueRaw: any)
	local value = sanitizeItemId(valueRaw)
	if value == nil or seen[value] == true then
		return
	end

	seen[value] = true
	target[#target + 1] = value
end

local function resolveAssetSearchRoots(): { Instance }
	if assetSearchRootsCache ~= nil then
		return assetSearchRootsCache
	end

	local roots = {}
	local pathsRaw = if typeof(LootServiceData) == "table" then (LootServiceData :: { [string]: any }).assetSearchRoots else nil
	if typeof(pathsRaw) == "table" then
		for _, pathRaw in pathsRaw do
			if typeof(pathRaw) ~= "table" then
				continue
			end

			local segments = {}
			for _, segmentRaw in pathRaw do
				local segment = sanitizeItemId(segmentRaw)
				if segment ~= nil then
					segments[#segments + 1] = segment
				end
			end
			if #segments <= 0 then
				continue
			end

			local resolved = InstanceUtils.resolveChildPath(ReplicatedStorage, segments)
			if resolved ~= nil then
				roots[#roots + 1] = resolved
			end
		end
	end

	if #roots <= 0 then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets ~= nil then
			roots[#roots + 1] = assets
		end
	end

	assetSearchRootsCache = roots
	return roots
end

local function resolveItemNameCandidates(itemIdRaw: any): { string }
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return {}
	end

	local candidates = {}
	local seen = {} :: { [string]: boolean }

	local baseCandidates = LootServiceUtils.resolveItemNameCandidates(LootServiceData, itemId)
	for _, candidate in baseCandidates do
		appendUniqueString(candidates, seen, candidate)
	end

	local definition = ItemRegistry.resolveDefinition(itemId)
	if typeof(definition) == "table" then
		local definitionTable = definition :: { [string]: any }
		appendUniqueString(candidates, seen, definitionTable.name)
		appendUniqueString(candidates, seen, definitionTable.id)
		appendUniqueString(candidates, seen, definitionTable.itemId)
	end

	return candidates
end

local function isVariantBranchName(nameRaw: any): boolean
	local name = sanitizeItemId(nameRaw)
	if name == nil then
		return false
	end
	return ITEM_VARIANT_BRANCH_NAMES[string.lower(name)] == true
end

local function promoteMatchedTemplateRoot(match: Instance): Instance
	local promoted = match
	local parent = promoted.Parent
	while parent ~= nil and parent ~= ReplicatedStorage do
		if isVariantBranchName(parent.Name) and parent.Parent ~= nil then
			promoted = parent.Parent
			parent = promoted.Parent
		else
			break
		end
	end
	return promoted
end

local function resolveTemplatesFromRoot(root: Instance): ItemTemplateResolution
	local toolTemplate = ResolveToolInstance.resolveTool(root)
	local primaryTemplate = if root:IsA("Tool") then root else ResolveToolInstance.resolveVisualTemplate(root)
	if primaryTemplate == nil then
		primaryTemplate = toolTemplate
	end

	return {
		primaryTemplate = primaryTemplate,
		toolTemplate = toolTemplate,
	}
end

local function isCachedTemplateAlive(templateRaw: Instance | boolean): boolean
	if templateRaw == false then
		return true
	end
	return (templateRaw :: Instance).Parent ~= nil
end

local function readCachedResolution(itemId: string): ItemTemplateResolution?
	local cached = resolutionCacheByItemId[itemId]
	if cached == nil then
		return nil
	end

	if not isCachedTemplateAlive(cached.primaryTemplate) or not isCachedTemplateAlive(cached.toolTemplate) then
		resolutionCacheByItemId[itemId] = nil
		return nil
	end

	return {
		primaryTemplate = if cached.primaryTemplate == false then nil else (cached.primaryTemplate :: Instance),
		toolTemplate = if cached.toolTemplate == false then nil else (cached.toolTemplate :: Tool),
	}
end

local function cacheResolution(itemId: string, resolution: ItemTemplateResolution): ItemTemplateResolution
	resolutionCacheByItemId[itemId] = {
		primaryTemplate = if resolution.primaryTemplate ~= nil then resolution.primaryTemplate else false,
		toolTemplate = if resolution.toolTemplate ~= nil then resolution.toolTemplate else false,
	}
	return resolution
end

function ResolveItem.Resolve(itemIdRaw: any): ItemTemplateResolution
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return {
			primaryTemplate = nil,
			toolTemplate = nil,
		}
	end

	local cached = readCachedResolution(itemId)
	if cached ~= nil then
		return cached
	end

	local roots = resolveAssetSearchRoots()
	local candidates = resolveItemNameCandidates(itemId)
	local resolvedRoots = {} :: { [Instance]: boolean }

	local function tryResolveFromMatch(match: Instance): ItemTemplateResolution?
		local promotedRoot = promoteMatchedTemplateRoot(match)
		if resolvedRoots[promotedRoot] == true then
			return nil
		end
		resolvedRoots[promotedRoot] = true

		local resolution = resolveTemplatesFromRoot(promotedRoot)
		if resolution.primaryTemplate ~= nil or resolution.toolTemplate ~= nil then
			return resolution
		end
		return nil
	end

	for _, root in roots do
		for _, candidate in candidates do
			local direct = root:FindFirstChild(candidate)
			if direct ~= nil then
				local resolution = tryResolveFromMatch(direct)
				if resolution ~= nil then
					return cacheResolution(itemId, resolution)
				end
			end
		end
	end

	for _, root in roots do
		for _, candidate in candidates do
			for _, descendant in root:GetDescendants() do
				if descendant.Name ~= candidate then
					continue
				end

				local resolution = tryResolveFromMatch(descendant)
				if resolution ~= nil then
					return cacheResolution(itemId, resolution)
				end
			end
		end
	end

	return cacheResolution(itemId, {
		primaryTemplate = nil,
		toolTemplate = nil,
	})
end

function ResolveItem.ResolvePrimaryTemplate(itemIdRaw: any): Instance?
	return ResolveItem.Resolve(itemIdRaw).primaryTemplate
end

function ResolveItem.ResolveToolTemplate(itemIdRaw: any): Tool?
	return ResolveItem.Resolve(itemIdRaw).toolTemplate
end

function ResolveItem.CloneToolTemplate(itemIdRaw: any): Tool?
	local template = ResolveItem.ResolveToolTemplate(itemIdRaw)
	if template == nil then
		return nil
	end

	local clone = template:Clone()
	if not clone:IsA("Tool") then
		clone:Destroy()
		return nil
	end
	return clone
end

function ResolveItem.ClearCache()
	assetSearchRootsCache = nil
	table.clear(resolutionCacheByItemId)
end

ResolveItem.resolve = ResolveItem.Resolve
ResolveItem.resolvePrimaryTemplate = ResolveItem.ResolvePrimaryTemplate
ResolveItem.resolveToolTemplate = ResolveItem.ResolveToolTemplate
ResolveItem.cloneToolTemplate = ResolveItem.CloneToolTemplate
ResolveItem.clearCache = ResolveItem.ClearCache

return ResolveItem
