local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local WallAtlas = require("WallAtlas")
local WallAtlasAssets = require("WallAtlasAssets")
local WallServiceUtils = require("WallServiceUtils")

local WallAutotileRegistry = {}

local definitionsByWallId = {}
local definitionsById = {}

local function normalizeId(idRaw: any): string?
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return nil
	end
	return string.lower(idRaw)
end

local function normalizeImage(imageRaw: any): string?
	if typeof(imageRaw) == "number" and imageRaw == imageRaw and imageRaw > 0 then
		return `rbxassetid://{math.floor(imageRaw)}`
	end
	if typeof(imageRaw) ~= "string" then
		return nil
	end
	if string.match(imageRaw, "^%d+$") then
		return `rbxassetid://{imageRaw}`
	end
	if imageRaw == "" or string.match(imageRaw, "^rbxassetid://%d+$") ~= nil then
		return imageRaw
	end
	return nil
end

local function createDefinition(id: string, wallId: number, sourceAsset: string?): any
	return {
		Id = id,
		WallId = wallId,
		Image = normalizeImage(WallAtlasAssets[id]) or "",
		SourceAsset = sourceAsset,
		FrameSize = WallAtlas.FrameSize,
		Padding = 0,
		Spacing = WallAtlas.FrameSpacing,
		LogicalTilePixels = WallAtlas.LogicalTilePixels,
		FrameWorldScale = WallAtlas.FrameWorldScale,
		UseSurfaceGui = true,
		FrameRule = WallAtlas.Name,
		VariantSeed = wallId * 104729,
	}
end

function WallAutotileRegistry.RegisterDefinition(definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end
	local definition = definitionRaw :: any
	local wallId = WallServiceUtils.CoerceWallId(definition.WallId)
	local normalizedId = normalizeId(definition.Id)
	if wallId == nil or wallId == WallServiceUtils.WALL_ID.NONE or normalizedId == nil then
		return false
	end

	definitionsByWallId[wallId] = definition
	definitionsById[normalizedId] = definition
	return true
end

WallAutotileRegistry.RegisterDefinition(
	createDefinition("DirtWall", WallServiceUtils.WALL_ID.DIRT, "assets/walls/dirtWall.png")
)
WallAutotileRegistry.RegisterDefinition(
	createDefinition("StoneWall", WallServiceUtils.WALL_ID.STONE, "assets/walls/stoneWall.png")
)
WallAutotileRegistry.RegisterDefinition(createDefinition("SandstoneWall", WallServiceUtils.WALL_ID.SANDSTONE, nil))
WallAutotileRegistry.RegisterDefinition(createDefinition("SnowWall", WallServiceUtils.WALL_ID.SNOW, nil))
WallAutotileRegistry.RegisterDefinition(createDefinition("MudWall", WallServiceUtils.WALL_ID.MUD, nil))

function WallAutotileRegistry.GetDefinition(wallIdRaw: any): any?
	local wallId = WallServiceUtils.CoerceWallId(wallIdRaw)
	if wallId ~= nil then
		return definitionsByWallId[wallId]
	end

	local id = normalizeId(wallIdRaw)
	return if id ~= nil then definitionsById[id] else nil
end

function WallAutotileRegistry.ConfigureImage(wallIdRaw: any, imageRaw: any): boolean
	local definition = WallAutotileRegistry.GetDefinition(wallIdRaw)
	local image = normalizeImage(imageRaw)
	if definition == nil or image == nil then
		return false
	end
	(definition :: any).Image = image
	return true
end

function WallAutotileRegistry.HasRenderableDefinition(wallIdRaw: any): boolean
	local definition = WallAutotileRegistry.GetDefinition(wallIdRaw)
	return definition ~= nil and typeof((definition :: any).Image) == "string" and (definition :: any).Image ~= ""
end

function WallAutotileRegistry.GetDefinitions(): { [number]: any }
	return table.clone(definitionsByWallId)
end

function WallAutotileRegistry.GetMissingImageDefinitions(): { any }
	local missing = {}
	for _, definition in definitionsByWallId do
		if typeof((definition :: any).Image) ~= "string" or (definition :: any).Image == "" then
			missing[#missing + 1] = definition
		end
	end
	table.sort(missing, function(left: any, right: any): boolean
		return left.WallId < right.WallId
	end)
	return missing
end

return Table.readonly(WallAutotileRegistry)
