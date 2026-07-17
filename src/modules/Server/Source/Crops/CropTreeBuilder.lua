local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CropRules = require("CropRules")
local CropTypes = require("CropTypes")
local Rand = require("Rand")

local CropTreeBuilder = {}

local function coerceInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function coerceChance(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return math.clamp(fallback, 0, 1)
	end
	return math.clamp(valueRaw, 0, 1)
end

local function addSegment(
	segmentsByKey: { [string]: any },
	rootState: any,
	tileX: number,
	tileY: number,
	segment: string,
	finalStage: number,
	variant: number
)
	local key = CropTypes.GetTileKey(tileX, tileY)
	local existing = segmentsByKey[key]
	if existing ~= nil and (existing :: any).segment == CropTypes.Segment.Trunk then
		return
	end
	segmentsByKey[key] = {
		cropId = rootState.cropId,
		tileX = tileX,
		tileY = tileY,
		stage = finalStage,
		variant = variant,
		rootKey = rootState.rootKey or CropTypes.GetTileKey(rootState.tileX, rootState.tileY),
		segment = segment,
		ownerUserId = rootState.ownerUserId,
	}
end

function CropTreeBuilder.GetClearanceBounds(definitionRaw: any): any?
	if typeof(definitionRaw) ~= "table" or typeof((definitionRaw :: any).tree) ~= "table" then
		return nil
	end
	local tree = (definitionRaw :: any).tree
	local horizontal = coerceInteger(tree.horizontalClearance, 2, 0, 32)
	local vertical = coerceInteger(tree.verticalClearance, 10, 1, 128)
	return {
		minX = -horizontal,
		maxX = horizontal,
		minY = 0,
		maxY = vertical,
	}
end

function CropTreeBuilder.Generate(definitionRaw: any, rootStateRaw: any, seedRaw: any): { any }
	local rootState = CropTypes.CloneState(rootStateRaw)
	if rootState == nil or typeof(definitionRaw) ~= "table" or typeof((definitionRaw :: any).tree) ~= "table" then
		return {}
	end

	local tree = (definitionRaw :: any).tree
	local minimumHeight = coerceInteger(tree.minHeight, 5, 2, 64)
	local maximumHeight = coerceInteger(tree.maxHeight, minimumHeight, minimumHeight, 64)
	local branchChance = coerceChance(tree.branchChance, 0.5)
	local minimumBranchHeight = coerceInteger(tree.minBranchHeight, 3, 1, maximumHeight)
	local maximumBranchLength = coerceInteger(tree.maxBranchLength, 2, 1, 8)
	local foliageRadius = coerceInteger(tree.foliageRadius, 2, 0, 8)
	local seed = if typeof(seedRaw) == "number"
		then Rand.Uint32(seedRaw)
		else Rand.Seed(rootState.rootKey or rootState.cropId)

	local height
	seed, height = Rand.Integer(seed, minimumHeight, maximumHeight)
	local variant = seed % 65536
	local finalStage = CropRules.GetFinalStage(definitionRaw)
	local segmentsByKey = {}

	for offsetY = 0, height - 1 do
		addSegment(
			segmentsByKey,
			rootState,
			rootState.tileX,
			rootState.tileY + offsetY,
			CropTypes.Segment.Trunk,
			finalStage,
			variant
		)
	end

	for offsetY = minimumBranchHeight, height - 2 do
		local shouldBranch
		seed, shouldBranch = Rand.Chance(seed, branchChance)
		if not shouldBranch then
			continue
		end

		local directionRoll
		seed, directionRoll = Rand.Integer(seed, 0, 1)
		local direction = if directionRoll == 0 then -1 else 1
		local branchLength
		seed, branchLength = Rand.Integer(seed, 1, maximumBranchLength)
		for offsetX = 1, branchLength do
			addSegment(
				segmentsByKey,
				rootState,
				rootState.tileX + direction * offsetX,
				rootState.tileY + offsetY,
				CropTypes.Segment.Branch,
				finalStage,
				variant
			)
		end
	end

	local canopyY = rootState.tileY + height - 1
	for offsetX = -foliageRadius, foliageRadius do
		for offsetY = -foliageRadius, foliageRadius do
			if math.abs(offsetX) + math.abs(offsetY) > foliageRadius + 1 then
				continue
			end
			addSegment(
				segmentsByKey,
				rootState,
				rootState.tileX + offsetX,
				canopyY + offsetY,
				CropTypes.Segment.Foliage,
				finalStage,
				variant
			)
		end
	end

	local keys = Table.keys(segmentsByKey)
	table.sort(keys)
	local segments = {}
	for _, key in keys do
		segments[#segments + 1] = segmentsByKey[key]
	end
	return segments
end

return Table.readonly(CropTreeBuilder)
