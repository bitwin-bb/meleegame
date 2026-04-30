--!strict

local DeterministicRNG = require(script:FindFirstAncestor("game").Shared.Modules.Core.DeterministicRNG)

local TreeHeightVariation = {}

local HEIGHT_SCALE_MIN = 0.84
local HEIGHT_SCALE_MAX = 1.22
local HEIGHT_SCALE_SALT_X = 8231
local HEIGHT_SCALE_SALT_Y = 46027
local HEIGHT_SCALE_SEED_SALT = "ProceduralTreeHeight"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeAlpha(scale: number): number
	return math.clamp((scale - HEIGHT_SCALE_MIN) / (HEIGHT_SCALE_MAX - HEIGHT_SCALE_MIN), 0, 1)
end

function TreeHeightVariation.ResolveHeightScale(seedRaw: any): number
	local seed = DeterministicRNG.SeedFrom(seedRaw)
	local rngSeed =
		DeterministicRNG.HashCoordinates(seed, HEIGHT_SCALE_SALT_X, HEIGHT_SCALE_SALT_Y, HEIGHT_SCALE_SEED_SALT)
	local rng = DeterministicRNG.New(rngSeed)
	return rng:nextRange(HEIGHT_SCALE_MIN, HEIGHT_SCALE_MAX)
end

function TreeHeightVariation.ResolveHeightTiles(seedRaw: any, minimumRaw: any, maximumRaw: any): number
	local minimum = if isFiniteNumber(minimumRaw) then math.floor(minimumRaw :: number) else 1
	local maximum = if isFiniteNumber(maximumRaw) then math.floor(maximumRaw :: number) else minimum
	if maximum < minimum then
		local temporary = maximum
		maximum = minimum
		minimum = temporary
	end

	local alpha = normalizeAlpha(TreeHeightVariation.ResolveHeightScale(seedRaw))
	return math.clamp(minimum + math.floor(alpha * (maximum - minimum) + 0.5), minimum, maximum)
end

TreeHeightVariation.resolveHeightScale = TreeHeightVariation.ResolveHeightScale
TreeHeightVariation.resolveHeightTiles = TreeHeightVariation.ResolveHeightTiles

return TreeHeightVariation
