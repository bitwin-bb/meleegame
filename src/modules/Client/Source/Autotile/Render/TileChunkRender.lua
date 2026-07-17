local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasResolver = require("AtlasResolver")
local AutotileRegistry = require("AutotileRegistry")
local AutotileTypes = require("AutotileTypes")
local BlendRule = require("BlendRule")
local DirectionBits = require("DirectionBits")
local EightWayBlobRule = require("EightWayBlobRule")
local FourWay16Rule = require("FourWay16Rule")
local Full256Rule = require("Full256Rule")
local MaskResolver = require("MaskResolver")

local TileChunkRender = {}

local function getTileData(renderService: any, tileX: number, tileY: number): any?
	if typeof(renderService) ~= "table" then
		return nil
	end

	local getTileDataMethod = (renderService :: any).GetTileData
	if typeof(getTileDataMethod) ~= "function" then
		return nil
	end

	return getTileDataMethod(renderService, tileX, tileY)
end

local function getTileSurfaceLayout(
	renderService: any,
	tileX: number,
	tileY: number,
	definition: any,
	atlasResult: any
): any?
	if typeof(renderService) ~= "table" then
		return nil
	end

	local getLayoutMethod = (renderService :: any).GetTileSurfaceLayout
	if typeof(getLayoutMethod) ~= "function" then
		return nil
	end

	return getLayoutMethod(renderService, tileX, tileY, definition, atlasResult)
end

function TileChunkRender.GetRuleForDefinition(definitionRaw: any): any
	local mode = AutotileTypes.CoerceMode(if typeof(definitionRaw) == "table" then (definitionRaw :: any).Mode else nil)
	if mode == AutotileTypes.Modes.FourWay16 then
		return FourWay16Rule
	end
	if mode == AutotileTypes.Modes.Full256 then
		return Full256Rule
	end
	return EightWayBlobRule
end

function TileChunkRender.Resolve(renderService: any, tileXRaw: any, tileYRaw: any): any?
	if typeof(tileXRaw) ~= "number" or typeof(tileYRaw) ~= "number" then
		return nil
	end

	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local tileData = getTileData(renderService, tileX, tileY)
	if typeof(tileData) ~= "table" then
		return nil
	end

	local tileId = (tileData :: any).TileId or (tileData :: any).tileId
	local definition = AutotileRegistry.GetDefinition(tileId)
	if not AutotileTypes.UsesSurfaceGui(definition) then
		return nil
	end

	local function getNeighborTile(scanX: number, scanY: number): any?
		return getTileData(renderService, scanX, scanY)
	end

	local sameMask
	local mergeMask = 0
	if BlendRule.IsDefinition(definition) then
		sameMask, mergeMask = MaskResolver.ResolveTileMasks(
			getNeighborTile,
			Vector2.new(tileX, tileY),
			tileId,
			rawget(definition, "MergeTileIds"),
			rawget(definition, "ConnectTileIds")
		)
	else
		sameMask = MaskResolver.Resolve(
			getNeighborTile,
			Vector2.new(tileX, tileY),
			TileChunkRender.GetRuleForDefinition(definition)
		)
	end

	local atlasMask = DirectionBits.MirrorHorizontal(sameMask)
	local atlasMergeMask = DirectionBits.MirrorHorizontal(mergeMask)
	local atlasResult = AtlasResolver.ResolveMerged(
		definition,
		atlasMask,
		atlasMergeMask,
		Vector2.new(tileX, tileY),
		rawget(definition, "VariantSeed")
	)
	if atlasResult == nil then
		return nil
	end

	return {
		definition = definition,
		atlasResult = atlasResult,
		layout = getTileSurfaceLayout(renderService, tileX, tileY, definition, atlasResult),
	}
end

return Table.readonly(TileChunkRender)
