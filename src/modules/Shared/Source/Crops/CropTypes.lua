local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuildServiceUtils = require("BuildServiceUtils")

local CropTypes = {}

CropTypes.Kind = Table.readonly({
	Grass = "Grass",
	Herb = "Herb",
	Crop = "Crop",
	Mushroom = "Mushroom",
	Vine = "Vine",
	Cactus = "Cactus",
	Pumpkin = "Pumpkin",
	Tree = "Tree",
	Decorative = "Decorative",
})

CropTypes.PlacementMode = Table.readonly({
	AboveSoil = "AboveSoil",
	ReplaceSoil = "ReplaceSoil",
})

CropTypes.Segment = Table.readonly({
	Trunk = "Trunk",
	Branch = "Branch",
	Foliage = "Foliage",
})

CropTypes.DeltaOperation = Table.readonly({
	Set = "set",
	Remove = "remove",
	Terrain = "terrain",
})

CropTypes.Network = Table.readonly({
	RequestPlant = "requestPlant",
	RequestHarvest = "requestHarvest",
	RequestSync = "requestSync",
	ApplyState = "applyState",
	OnChunkSnapshot = "onChunkSnapshot",
	OnChunkUnloaded = "onChunkUnloaded",
	OnCropDeltas = "onCropDeltas",
	OnActionResult = "onActionResult",
})

export type CropKind = "Grass" | "Herb" | "Crop" | "Mushroom" | "Vine" | "Cactus" | "Pumpkin" | "Tree" | "Decorative"
export type PlacementMode = "AboveSoil" | "ReplaceSoil"
export type TreeSegment = "Trunk" | "Branch" | "Foliage"
export type DeltaOperation = "set" | "remove" | "terrain"

export type TileOffset = {
	x: number,
	y: number,
}

export type EnvironmentRequirements = {
	soilTileIds: { number }?,
	biomeIds: { number }?,
	biomeTypes: { number }?,
	dayParts: { string }?,
	weatherTypes: { string }?,
	minClockTime: number?,
	maxClockTime: number?,
	minLight: number?,
	maxLight: number?,
	minWater: number?,
	maxWater: number?,
	minRain: number?,
	clearanceAbove: number?,
	clearanceLeft: number?,
	clearanceRight: number?,
}

export type GrowthStage = {
	id: string,
	growthChance: number?,
	requirements: EnvironmentRequirements?,
}

export type PlacementSettings = {
	mode: PlacementMode,
	soilOffsetY: number?,
	soilTileIds: { number }?,
	targetTileIds: { number }?,
	resultTileId: number?,
	requireOpenAbove: boolean?,
}

export type SpreadSettings = {
	chance: number,
	offsets: { TileOffset }?,
	targetTileIds: { number }?,
	resultTileId: number?,
	resultCropId: string?,
	matureOnly: boolean?,
	requireOpenAbove: boolean?,
	maxNearby: number?,
	nearbyRadius: number?,
	decorativeChance: number?,
	decorativeCropIds: { string }?,
	requirements: EnvironmentRequirements?,
}

export type TreeSettings = {
	growthChance: number,
	soilTileIds: { number }?,
	minHeight: number,
	maxHeight: number,
	verticalClearance: number,
	horizontalClearance: number,
	nearbyBlockerRadius: number,
	branchChance: number,
	minBranchHeight: number?,
	maxBranchLength: number,
	foliageRadius: number,
}

export type HarvestDrop = {
	itemId: string,
	minAmount: number,
	maxAmount: number,
	chance: number?,
}

export type CropDefinition = {
	id: string,
	kind: CropKind,
	seedItemId: string?,
	placement: PlacementSettings?,
	stages: { GrowthStage },
	growthRequirements: EnvironmentRequirements?,
	harvestRequirements: EnvironmentRequirements?,
	harvestDrops: { HarvestDrop }?,
	spread: SpreadSettings?,
	tree: TreeSettings?,
	randomUpdateTileIds: { number }?,
}

export type CropState = {
	cropId: string,
	tileX: number,
	tileY: number,
	stage: number,
	variant: number?,
	rootKey: string?,
	segment: TreeSegment?,
	ownerUserId: number?,
}

export type Environment = {
	targetTileId: number,
	soilTileId: number,
	biomeId: number,
	biomeType: number,
	clockTime: number,
	dayPart: string,
	weatherType: string,
	light: number,
	water: number,
	rain: number,
	targetOpen: boolean,
	openAbove: number,
	openLeft: number,
	openRight: number,
}

export type CropDelta = {
	op: DeltaOperation,
	key: string,
	chunkKey: string,
	tileX: number,
	tileY: number,
	crop: CropState?,
	tileId: number?,
	reason: string?,
	revision: number,
}

export type CropSnapshot = {
	revision: number,
	crops: { CropState },
}

export type CropSystemConfig = {
	randomUpdateInterval: number,
	samplesPerChunk: number,
	maxChunksPerTick: number,
	maxRandomUpdatesPerTick: number,
	maxTerrainMutationsPerFlush: number,
	deltaBatchMax: number,
	lightScanHeight: number,
	waterScanRadius: number,
	requestInterval: number,
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function CropTypes.CoerceCropId(cropIdRaw: any): string?
	if typeof(cropIdRaw) ~= "string" then
		return nil
	end

	local cropId = string.match(cropIdRaw, "^%s*(.-)%s*$") or ""
	if cropId == "" then
		return nil
	end
	return cropId
end

function CropTypes.CloneState(stateRaw: any): CropState?
	if typeof(stateRaw) ~= "table" then
		return nil
	end

	local cropId = CropTypes.CoerceCropId((stateRaw :: any).cropId)
	local tileX = BuildServiceUtils.CoerceTileCoordinate((stateRaw :: any).tileX)
	local tileY = BuildServiceUtils.CoerceTileCoordinate((stateRaw :: any).tileY)
	if cropId == nil or tileX == nil or tileY == nil then
		return nil
	end

	local stageRaw = (stateRaw :: any).stage
	local stage = if isFiniteNumber(stageRaw) then math.max(0, math.floor(stageRaw)) else 0
	local variantRaw = (stateRaw :: any).variant
	local ownerUserIdRaw = (stateRaw :: any).ownerUserId
	local rootKeyRaw = (stateRaw :: any).rootKey
	local segmentRaw = (stateRaw :: any).segment

	return {
		cropId = cropId,
		tileX = tileX,
		tileY = tileY,
		stage = stage,
		variant = if isFiniteNumber(variantRaw) then math.floor(variantRaw) else nil,
		rootKey = if typeof(rootKeyRaw) == "string" and rootKeyRaw ~= "" then rootKeyRaw else nil,
		segment = if segmentRaw == CropTypes.Segment.Trunk
				or segmentRaw == CropTypes.Segment.Branch
				or segmentRaw == CropTypes.Segment.Foliage
			then segmentRaw
			else nil,
		ownerUserId = if isFiniteNumber(ownerUserIdRaw) then math.floor(ownerUserIdRaw) else nil,
	}
end

function CropTypes.CloneDelta(deltaRaw: any): CropDelta?
	if typeof(deltaRaw) ~= "table" then
		return nil
	end

	local tileX = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileX)
	local tileY = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileY)
	local keyRaw = (deltaRaw :: any).key
	local chunkKeyRaw = (deltaRaw :: any).chunkKey
	local opRaw = (deltaRaw :: any).op
	if tileX == nil or tileY == nil or typeof(keyRaw) ~= "string" or typeof(chunkKeyRaw) ~= "string" then
		return nil
	end
	if
		opRaw ~= CropTypes.DeltaOperation.Set
		and opRaw ~= CropTypes.DeltaOperation.Remove
		and opRaw ~= CropTypes.DeltaOperation.Terrain
	then
		return nil
	end

	local revisionRaw = (deltaRaw :: any).revision
	local tileIdRaw = (deltaRaw :: any).tileId
	return {
		op = opRaw,
		key = keyRaw,
		chunkKey = chunkKeyRaw,
		tileX = tileX,
		tileY = tileY,
		crop = CropTypes.CloneState((deltaRaw :: any).crop),
		tileId = if isFiniteNumber(tileIdRaw) then math.floor(tileIdRaw) else nil,
		reason = if typeof((deltaRaw :: any).reason) == "string" then (deltaRaw :: any).reason else nil,
		revision = if isFiniteNumber(revisionRaw) then math.max(0, math.floor(revisionRaw)) else 0,
	}
end

function CropTypes.GetTileKey(tileX: number, tileY: number): string
	return BuildServiceUtils.PackTileKey(tileX, tileY)
end

function CropTypes.GetChunkKey(tileX: number, tileY: number, chunkSizeRaw: any): string
	local chunkSize = if isFiniteNumber(chunkSizeRaw) then math.max(1, math.floor(chunkSizeRaw)) else 32
	return BuildServiceUtils.PackChunkKey(math.floor(tileX / chunkSize), math.floor(tileY / chunkSize))
end

return Table.readonly(CropTypes)
