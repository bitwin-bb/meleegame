local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blocks = require("Blocks")
local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local GetToolInstance = require("GetToolInstance")
local InstanceUtils = require("InstanceUtils")
local ItemRegistry = require("ItemRegistry")
local LootServiceData = require("Data")
local LootServiceUtils = require("LootServiceUtils")
local StringUtils = require("StringUtils")

local GetItem = {}

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
local GENERATED_EQUIPMENT_TOOL_TYPES = {
	axe = true,
	pickaxe = true,
	tool = true,
	weapon = true,
}
local GENERATED_EQUIPMENT_TOOL_COLORS = {
	axe = Color3.fromRGB(189, 128, 72),
	pickaxe = Color3.fromRGB(181, 142, 83),
	tool = Color3.fromRGB(159, 159, 159),
	weapon = Color3.fromRGB(177, 184, 194),
}
local ITEM_VARIANT_BRANCH_NAMES = {
	model = true,
	tool = true,
}
local TILE_BLOCK_KEY_BY_ITEM_ID = {
	Wood = "Wood",
	Dirt = "Dirt",
	DirtAutotileTest = "Dirt",
	Stone = "Stone",
	Snow = "Snow",
	Ice = "Ice",
	Mud = "Mud",
	RichMahogany = "RichMahogany",
	EbonStone = "EbonStone",
	CorruptStone = "EbonStone",
}
local MISSING_ASSET_ERROR = "no asset found!"

local function CoerceItemId(itemIdRaw: any): string?
	return StringUtils.Coerce(itemIdRaw, nil)
end

local function appendUniqueString(target: { string }, seen: { [string]: boolean }, valueRaw: any)
	local value = CoerceItemId(valueRaw)
	if value == nil or seen[value] == true then
		return
	end

	seen[value] = true
	target[#target + 1] = value
end

local function GetAssetSearchRoots(): { Instance }
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
				local segment = CoerceItemId(segmentRaw)
				if segment ~= nil then
					segments[#segments + 1] = segment
				end
			end
			if #segments <= 0 then
				continue
			end

			local Got = InstanceUtils.GetChildPath(ReplicatedStorage, segments)
			if Got ~= nil then
				roots[#roots + 1] = Got
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

local function GetItemNameCandidates(itemIdRaw: any): { string }
	local itemId = CoerceItemId(itemIdRaw)
	if itemId == nil then
		return {}
	end

	local candidates = {}
	local seen = {} :: { [string]: boolean }

	local baseCandidates = LootServiceUtils.GetItemNameCandidates(LootServiceData, itemId)
	for _, candidate in baseCandidates do
		appendUniqueString(candidates, seen, candidate)
	end

	local definition = ItemRegistry.GetDefinition(itemId)
	if typeof(definition) == "table" then
		local definitionTable = definition :: { [string]: any }
		appendUniqueString(candidates, seen, definitionTable.name)
		appendUniqueString(candidates, seen, definitionTable.id)
		appendUniqueString(candidates, seen, definitionTable.itemId)
	end

	return candidates
end

local function isVariantBranchName(nameRaw: any): boolean
	local name = CoerceItemId(nameRaw)
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

local function GetTemplatesFromRoot(root: Instance): ItemTemplateResolution
	local toolTemplate = GetToolInstance.GetTool(root)
	local primaryTemplate = if root:IsA("Tool") then root else GetToolInstance.GetVisualTemplate(root)
	if primaryTemplate == nil then
		primaryTemplate = toolTemplate
	end

	return {
		primaryTemplate = primaryTemplate,
		toolTemplate = toolTemplate,
	}
end

local function GetGeneratedTileToolFolder(): Folder
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

local function GetTileBlockBuilder(itemIdRaw: any): (string?, any?)
	local itemId = CoerceItemId(itemIdRaw)
	if itemId == nil then
		return nil, nil
	end

	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemId) or itemId
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

local GetToolPrimaryTemplate

local function GetDefinitionText(definition: { [string]: any }, key: string): string?
	return StringUtils.Coerce(definition[key], nil)
end

local function GetGeneratedEquipmentItemType(definition: { [string]: any }): string?
	local itemType = GetDefinitionText(definition, "itemType") or GetDefinitionText(definition, "type")
	local functionality = GetDefinitionText(definition, "functionality")
	local candidate = itemType or functionality
	if candidate == nil then
		return nil
	end

	local normalized = string.lower(candidate)
	if GENERATED_EQUIPMENT_TOOL_TYPES[normalized] == true then
		return normalized
	end
	return nil
end

local function GetGeneratedEquipmentHandleSize(itemType: string): Vector3
	if itemType == "weapon" then
		return Vector3.new(0.25, 3, 0.25)
	elseif itemType == "pickaxe" then
		return Vector3.new(1.85, 0.35, 0.35)
	elseif itemType == "axe" then
		return Vector3.new(1.4, 0.45, 0.35)
	end
	return Vector3.new(0.5, 1.6, 0.5)
end

local function GetGeneratedEquipmentGrip(itemType: string): CFrame
	if itemType == "weapon" then
		return CFrame.new(0, -1.1, 0)
	elseif itemType == "pickaxe" or itemType == "axe" then
		return CFrame.new(0, -0.35, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	return CFrame.new(0, -0.5, 0)
end

local function GetTemplatesFromItemDefinition(itemIdRaw: any): ItemTemplateResolution?
	local itemId = CoerceItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemId) or itemId
	local definition = ItemRegistry.GetDefinition(canonicalItemId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local definitionTable = definition :: { [string]: any }
	local itemType = GetGeneratedEquipmentItemType(definitionTable)
	if itemType == nil then
		return nil
	end

	local displayName = GetDefinitionText(definitionTable, "name") or canonicalItemId
	local scope = Fusion.scoped(Fusion)
	local handleColor = GENERATED_EQUIPMENT_TOOL_COLORS[itemType] or GENERATED_EQUIPMENT_TOOL_COLORS.tool
	local tool = scope:New "Tool" {
		Name = displayName,
		RequiresHandle = true,
		CanBeDropped = false,
		Grip = GetGeneratedEquipmentGrip(itemType),
		Parent = GetGeneratedTileToolFolder(),
		[Fusion.Attribute("itemId")] = canonicalItemId,
		[Fusion.Attribute("ItemId")] = canonicalItemId,
		[Fusion.Attribute("itemType")] = itemType,
		[Fusion.Attribute("ItemType")] = itemType,
		[Fusion.Children] = {
			scope:New "Part" {
				Name = "Handle",
				Anchored = false,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Massless = true,
				Material = Enum.Material.Metal,
				Color = handleColor,
				Size = GetGeneratedEquipmentHandleSize(itemType),
			},
		},
	}
	tileToolScopes[#tileToolScopes + 1] = scope

	return {
		primaryTemplate = GetToolPrimaryTemplate(tool),
		toolTemplate = tool,
	}
end

function GetToolPrimaryTemplate(tool: Tool): Instance?
	local contents = tool:FindFirstChild("Contents")
	if contents ~= nil then
		local visual = GetToolInstance.GetVisualTemplate(contents)
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

local function GetTemplatesFromTileBlock(itemIdRaw: any): ItemTemplateResolution?
	local canonicalItemId, builder = GetTileBlockBuilder(itemIdRaw)
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
		Parent = GetGeneratedTileToolFolder(),
		[Fusion.Attribute("itemId")] = canonicalItemId,
		[Fusion.Attribute("ItemId")] = canonicalItemId,
		[Fusion.Attribute("itemType")] = "Tile",
		[Fusion.Attribute("ItemType")] = "Tile",
	}
	tileToolScopes[#tileToolScopes + 1] = scope

	return {
		primaryTemplate = GetToolPrimaryTemplate(tool),
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

	local componentResolution = GetTemplatesFromTileBlock(itemId)
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

function GetItem.Get(itemIdRaw: any): ItemTemplateResolution
	local itemId = CoerceItemId(itemIdRaw)
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

	local roots = GetAssetSearchRoots()
	local candidates = GetItemNameCandidates(itemId)
	local GotRoots = {} :: { [Instance]: boolean }

	local function tryGetFromMatch(match: Instance): ItemTemplateResolution?
		local promotedRoot = promoteMatchedTemplateRoot(match)
		if GotRoots[promotedRoot] == true then
			return nil
		end
		GotRoots[promotedRoot] = true

		local resolution = GetTemplatesFromRoot(promotedRoot)
		if resolution.primaryTemplate ~= nil or resolution.toolTemplate ~= nil then
			return resolution
		end
		return nil
	end

	for _, root in roots do
		for _, candidate in candidates do
			local direct = root:FindFirstChild(candidate)
			if direct ~= nil then
				local resolution = tryGetFromMatch(direct)
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

				local resolution = tryGetFromMatch(descendant)
				if resolution ~= nil then
					return cacheResolution(itemId, mergeTileComponentToolTemplate(itemId, resolution))
				end
			end
		end
	end

	local componentResolution = GetTemplatesFromTileBlock(itemId)
	if componentResolution ~= nil then
		return cacheResolution(itemId, componentResolution)
	end

	local definitionResolution = GetTemplatesFromItemDefinition(itemId)
	if definitionResolution ~= nil then
		return cacheResolution(itemId, definitionResolution)
	end

	error(MISSING_ASSET_ERROR, 0)
end

function GetItem.GetPrimaryTemplate(itemIdRaw: any): Instance?
	return GetItem.Get(itemIdRaw).primaryTemplate
end

function GetItem.GetToolTemplate(itemIdRaw: any): Tool?
	return GetItem.Get(itemIdRaw).toolTemplate
end

function GetItem.CloneToolTemplate(itemIdRaw: any): Tool?
	local template = GetItem.GetToolTemplate(itemIdRaw)
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

function GetItem.ClearCache()
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

return GetItem
