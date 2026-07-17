local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local WallAutotileRegistry = require("WallAutotileRegistry")
local WallAutotileResolver = require("WallAutotileResolver")
local WallServiceUtils = require("WallServiceUtils")

local WallChunkRender = {}

local function getWallData(renderService: any, tileX: number, tileY: number): any?
	if typeof(renderService) ~= "table" then
		return nil
	end
	local getWallDataMethod = (renderService :: any).GetWallData
	return if typeof(getWallDataMethod) == "function" then getWallDataMethod(renderService, tileX, tileY) else nil
end

function WallChunkRender.Resolve(renderService: any, tileXRaw: any, tileYRaw: any): any?
	if typeof(tileXRaw) ~= "number" or typeof(tileYRaw) ~= "number" then
		return nil
	end

	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local wallData = getWallData(renderService, tileX, tileY)
	if typeof(wallData) ~= "table" then
		return nil
	end

	local wallId = WallServiceUtils.CoerceWallId((wallData :: any).WallId or (wallData :: any).wallId)
	if wallId == nil or wallId == WallServiceUtils.WALL_ID.NONE then
		return nil
	end
	local definition = WallAutotileRegistry.GetDefinition(wallId)
	if
		definition == nil
		or (definition :: any).UseSurfaceGui ~= true
		or typeof((definition :: any).Image) ~= "string"
		or (definition :: any).Image == ""
	then
		return nil
	end

	local function getNeighborWall(scanX: number, scanY: number): any?
		return getWallData(renderService, scanX, scanY)
	end
	local variantSeed = (definition :: any).VariantSeed
	local getVariantSeedMethod = if typeof(renderService) == "table"
		then (renderService :: any).GetWallVariantSeed
		else nil
	if typeof(getVariantSeedMethod) == "function" then
		variantSeed = getVariantSeedMethod(renderService, wallId)
	end

	local atlasResult =
		WallAutotileResolver.Resolve(definition, getNeighborWall, Vector2.new(tileX, tileY), variantSeed)
	if atlasResult == nil then
		return nil
	end

	local layout = nil
	local getLayoutMethod = if typeof(renderService) == "table"
		then (renderService :: any).GetWallSurfaceLayout
		else nil
	if typeof(getLayoutMethod) == "function" then
		layout = getLayoutMethod(renderService, tileX, tileY, definition, atlasResult)
	end

	return {
		definition = definition,
		atlasResult = atlasResult,
		layout = layout,
	}
end

return Table.readonly(WallChunkRender)
