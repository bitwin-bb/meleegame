
local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Blocks = require("Blocks")
local InstanceUtils = require("InstanceUtils")
local ItemRegistry = require("ItemRegistry")
local LootServiceData = require("Data")
local LootServiceUtils = require("LootServiceUtils")
local ResolveToolInstance = require("ResolveToolInstance")
local StringUtils = require("StringUtils")

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
local tileToolScopes = {} :: { any }
local generatedTileToolScope = nil :: any
local generatedTileToolFolder = nil :: Folder?
local ITEM_VARIANT_BRANCH_NAMES = {
	model = true,
	tool = true,
}
local TILE_BLOCK_KEY_BY_ITEM_ID = {
	Wood = "Wood",
	Dirt = "Dirt",
	Stone = "Stone",
	Snow = "Snow",
	Ice = "Ice",
	Mud = "Mud",
	RichMahogany = "RichMahogany",
	EbonStone = "EbonStone",
	CorruptStone = "EbonStone",
}
local MISSING_ASSET_ERROR = "no asset found!"

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
	local pathsRaw = if typeof(LootServiceData) == "table"
		then (LootServiceData :: { [string]: any }).assetSearchRoots
		else nil
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

local function resolveGeneratedTileToolFolder(): Folder
	if generatedTileToolFolder ~= nil and generatedTileToolFolder.Parent ~= nil then
		return generatedTileToolFolder
	end

	local folder = script:FindFirstChild("GeneratedTileToolTemplates")
	if folder ~= nil and folder:IsA("Folder") then
		generatedTileToolFolder = folder
		return folder
	end

	local scope = Fusion.scoped(Fusion)
	folder = scope:New "Folder" {
		Name = "GeneratedTileToolTemplates",
		Parent = script,
	}
	generatedTileToolScope = scope
	generatedTileToolFolder = folder
	return folder
end

local function resolveTileBlockBuilder(itemIdRaw: any): (string?, any?)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil, nil
	end

	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemId) or itemId
	local blockKey = TILE_BLOCK_KEY_BY_ITEM_ID[canonicalItemId] or TILE_BLOCK_KEY_BY_ITEM_ID[itemId]
	if blockKey == nil then
		return nil, nil
	end

	local builder = Blocks[blockKey]
	if typeof(builder) ~= "function" then
		return nil, nil
	end

	return canonicalItemId, builder
end

local function resolveToolPrimaryTemplate(tool: Tool): Instance?
	local contents = tool:FindFirstChild("Contents")
	if contents ~= nil then
		local visual = ResolveToolInstance.resolveVisualTemplate(contents)
		if visual ~= nil then
			return visual
		end
	end

	local handle = tool:FindFirstChild("Handle")
	if handle ~= nil and handle:IsA("BasePart") then
		return handle
	end
	return tool
end

local function resolveTemplatesFromTileBlock(itemIdRaw: any): ItemTemplateResolution?
	local canonicalItemId, builder = resolveTileBlockBuilder(itemIdRaw)
	if canonicalItemId == nil or builder == nil then
		return nil
	end

	local scope = Fusion.scoped(Fusion)
	local buildOk, toolRaw = pcall(builder, scope)
	if not buildOk or typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		Fusion.doCleanup(scope)
		return nil
	end

	local tool = toolRaw :: Tool
	scope:Hydrate(tool) {
		Name = tool.Name ~= "" and tool.Name or canonicalItemId,
		Parent = resolveGeneratedTileToolFolder(),
		[Fusion.Attribute("itemId")] = canonicalItemId,
		[Fusion.Attribute("ItemId")] = canonicalItemId,
		[Fusion.Attribute("itemType")] = "Tile",
		[Fusion.Attribute("ItemType")] = "Tile",
	}
	tileToolScopes[#tileToolScopes + 1] = scope

	return {
		primaryTemplate = resolveToolPrimaryTemplate(tool),
		toolTemplate = tool,
	}
end

local function mergeTileComponentToolTemplate(
	itemId: string,
	resolution: ItemTemplateResolution
): ItemTemplateResolution
	if resolution.toolTemplate ~= nil then
		return resolution
	end

	local componentResolution = resolveTemplatesFromTileBlock(itemId)
	if componentResolution == nil then
		return resolution
	end

	return {
		primaryTemplate = resolution.primaryTemplate or componentResolution.primaryTemplate,
		toolTemplate = componentResolution.toolTemplate,
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
		primaryTemplate = if cached.primaryTemplate == false then nil else cached.primaryTemplate :: Instance,
		toolTemplate = if cached.toolTemplate == false then nil else cached.toolTemplate :: Tool,
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
					return cacheResolution(itemId, mergeTileComponentToolTemplate(itemId, resolution))
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
					return cacheResolution(itemId, mergeTileComponentToolTemplate(itemId, resolution))
				end
			end
		end
	end

	local componentResolution = resolveTemplatesFromTileBlock(itemId)
	if componentResolution ~= nil then
		return cacheResolution(itemId, componentResolution)
	end

	error(MISSING_ASSET_ERROR, 0)
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
		error(MISSING_ASSET_ERROR, 0)
	end

	local clone = template:Clone()
	if not clone:IsA("Tool") then
		clone:Destroy()
		error(MISSING_ASSET_ERROR, 0)
	end
	return clone
end

function ResolveItem.ClearCache()
	assetSearchRootsCache = nil
	table.clear(resolutionCacheByItemId)
	for _, scope in tileToolScopes do
		Fusion.doCleanup(scope)
	end
	table.clear(tileToolScopes)
	if generatedTileToolScope ~= nil then
		Fusion.doCleanup(generatedTileToolScope)
	elseif generatedTileToolFolder ~= nil then
		generatedTileToolFolder:Destroy()
	end
	generatedTileToolScope = nil
	generatedTileToolFolder = nil
end

ResolveItem.resolve = ResolveItem.Resolve
ResolveItem.resolvePrimaryTemplate = ResolveItem.ResolvePrimaryTemplate
ResolveItem.resolveToolTemplate = ResolveItem.ResolveToolTemplate
ResolveItem.cloneToolTemplate = ResolveItem.CloneToolTemplate
ResolveItem.clearCache = ResolveItem.ClearCache

return ResolveItem
