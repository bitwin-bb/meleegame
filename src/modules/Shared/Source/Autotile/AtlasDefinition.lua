local require = require(script.Parent.loader).load(script)

local Set = require("Set")
local Table = require("Table")

local AutotileTypes = require("AutotileTypes")
local BlendRule = require("BlendRule")

local AtlasDefinition = {}

AtlasDefinition.TileIds = Table.readonly({
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	SANDSTONE = 5,
	SNOW = 6,
	ICE = 7,
	MUD = 8,
	CLAY = 9,
	COPPER_ORE = 10,
	IRON_ORE = 11,
	SILVER_ORE = 12,
	GOLD_ORE = 13,
	CORRUPT_GRASS = 14,
	CORRUPT_SOIL = 15,
	CORRUPT_STONE = 16,
	JUNGLE_GRASS = 17,
	WOOD = 18,
})

local SOURCE_MERGE_PAIRS = Table.readonly({
	Table.readonly({ AtlasDefinition.TileIds.GRASS, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.STONE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.SAND, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.SANDSTONE, AtlasDefinition.TileIds.SAND }),
	Table.readonly({ AtlasDefinition.TileIds.ICE, AtlasDefinition.TileIds.SNOW }),
	Table.readonly({ AtlasDefinition.TileIds.MUD, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.MUD, AtlasDefinition.TileIds.STONE }),
	Table.readonly({ AtlasDefinition.TileIds.CLAY, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.COPPER_ORE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.IRON_ORE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.SILVER_ORE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.GOLD_ORE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.CORRUPT_GRASS, AtlasDefinition.TileIds.CORRUPT_SOIL }),
	Table.readonly({ AtlasDefinition.TileIds.CORRUPT_GRASS, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.CORRUPT_STONE, AtlasDefinition.TileIds.DIRT }),
	Table.readonly({ AtlasDefinition.TileIds.CORRUPT_STONE, AtlasDefinition.TileIds.CORRUPT_SOIL }),
	Table.readonly({ AtlasDefinition.TileIds.JUNGLE_GRASS, AtlasDefinition.TileIds.MUD }),
	Table.readonly({ AtlasDefinition.TileIds.WOOD, AtlasDefinition.TileIds.DIRT }),
})

local sourceMergeTargets = {}
for _, pair in SOURCE_MERGE_PAIRS do
	local targets = sourceMergeTargets[pair[1]]
	if targets == nil then
		targets = {}
		sourceMergeTargets[pair[1]] = targets
	end
	targets[pair[2]] = true
end
local SOURCE_MERGE_TARGETS = Table.deepReadonly(sourceMergeTargets)

local function createMutableTileIdSet(tileIdsRaw: any): { [number]: boolean }
	local tileIdList = {}
	if typeof(tileIdsRaw) ~= "table" then
		return Set.fromList(tileIdList)
	end

	for _, tileIdRaw in tileIdsRaw do
		if typeof(tileIdRaw) == "number" then
			table.insert(tileIdList, math.floor(tileIdRaw))
		end
	end
	return Set.fromList(tileIdList)
end

local function sourceMergesInto(sourceTileId: number, targetTileId: number): boolean
	local targets = rawget(SOURCE_MERGE_TARGETS, sourceTileId)
	return targets ~= nil and rawget(targets, targetTileId) == true
end

local function createTileRelationshipSets(
	tileIdRaw: any,
	mergeTileIdsRaw: any,
	connectTileIdsRaw: any
): ({ [number]: boolean }, { [number]: boolean })
	local mergeTileIds = createMutableTileIdSet(mergeTileIdsRaw)
	local connectTileIds = createMutableTileIdSet(connectTileIdsRaw)
	if typeof(tileIdRaw) ~= "number" then
		return Table.readonly(mergeTileIds), Table.readonly(connectTileIds)
	end

	local tileId = math.floor(tileIdRaw)
	for targetTileId = AtlasDefinition.TileIds.GRASS, AtlasDefinition.TileIds.WOOD do
		if targetTileId == tileId then
			continue
		end

		if rawget(mergeTileIds, targetTileId) == true or sourceMergesInto(tileId, targetTileId) then
			mergeTileIds[targetTileId] = true
			connectTileIds[targetTileId] = nil
		elseif rawget(connectTileIds, targetTileId) == true or sourceMergesInto(targetTileId, tileId) then
			connectTileIds[targetTileId] = true
			mergeTileIds[targetTileId] = nil
		else
			mergeTileIds[targetTileId] = nil
			connectTileIds[targetTileId] = nil
		end
	end

	mergeTileIds[tileId] = nil
	connectTileIds[tileId] = nil
	return Table.readonly(mergeTileIds), Table.readonly(connectTileIds)
end

function AtlasDefinition.Create(optionsRaw: any): any
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local strictness = if typeof(options.RuleStrictness) == "number"
		then math.floor(options.RuleStrictness)
		else BlendRule.Strictness.Base
	local entries = BlendRule.CreateEntries(strictness)
	local mergeTileIds, connectTileIds =
		createTileRelationshipSets(options.TileId, options.MergeTileIds, options.ConnectTileIds)

	return {
		Id = options.Id,
		TileId = options.TileId,
		Image = options.Image,
		SourceAsset = options.SourceAsset,
		TileSize = 16,
		Padding = 0,
		Spacing = 2,
		ImageRectScale = options.ImageRectScale,
		UseSurfaceGui = true,
		Mode = AutotileTypes.Modes.Full256,
		ConnectGroup = options.ConnectGroup,
		FrameRule = BlendRule.Name,
		RuleStrictness = strictness,
		MergeTileIds = mergeTileIds,
		ConnectTileIds = connectTileIds,
		Entries = entries,
		Fallback = entries[0],
	}
end

return Table.readonly(AtlasDefinition)
