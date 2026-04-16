--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Noise = require(script:FindFirstAncestor("game").Shared.Modules.Math.Noise)
local Rand = require(script:FindFirstAncestor("game").Shared.Modules.Math.Rand)

local DeterministicRNG = {}
local RNG = {}
RNG.__index = RNG

export type WeightedEntry<T> = {
	value: T,
	weight: number,
}

export type RNG = {
	state: number,
	initialSeed: number,
	nextUInt32: (self: RNG) -> number,
	nextNumber: (self: RNG) -> number,
	nextInteger: (self: RNG, minValue: number, maxValue: number) -> number,
	nextRange: (self: RNG, minValue: number, maxValue: number) -> number,
	chance: (self: RNG, probability: number) -> boolean,
	pickWeighted: <T>(self: RNG, entries: { WeightedEntry<T> }) -> T?,
	shuffleInPlace: <T>(self: RNG, array: { T }) -> { T },
	fork: (self: RNG, saltRaw: any) -> RNG,
	reset: (self: RNG) -> (),
}

export type NoiseWrapper = {
	seed: number,
	sample2D: (self: NoiseWrapper, x: number, y: number, scale: number?) -> number,
	sample3D: (self: NoiseWrapper, x: number, y: number, z: number, scale: number?) -> number,
	fbm2D: (self: NoiseWrapper, x: number, y: number, octaves: number?, persistence: number?, lacunarity: number?) -> number,
	fbm3D: (self: NoiseWrapper, x: number, y: number, z: number, octaves: number?, persistence: number?, lacunarity: number?) -> number,
}

local UINT32_FLOAT_DENOMINATOR = 4294967296

local function clampInteger(valueRaw: any, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else minValue
	value = math.floor(value)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function normalizeSeed(seedRaw: any): number
	return Rand.seed(seedRaw)
end

local function xorshift32(state: number): number
	local nextSeed = Rand.step(state)
	return nextSeed
end

local function floorToInteger(value: number): number
	if value >= 0 then
		return math.floor(value)
	end
	return math.ceil(value) - 1
end

local function hashCoordinatesInternal(xRaw: number, yRaw: number, zRaw: number, seedRaw: number): number
	return Rand.hashCoordinates(
		Rand.uint32(seedRaw),
		floorToInteger(xRaw),
		floorToInteger(yRaw),
		floorToInteger(zRaw)
	)
end

local function hashToUnitFloat(hashValue: number): number
	return (hashValue % UINT32_FLOAT_DENOMINATOR) / UINT32_FLOAT_DENOMINATOR
end

local function smoothStep(value: number): number
	return value * value * (3 - 2 * value)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function sampleValueNoise2D(seed: number, x: number, y: number): number
	local x0 = floorToInteger(x)
	local y0 = floorToInteger(y)
	local x1 = x0 + 1
	local y1 = y0 + 1

	local tx = smoothStep(x - x0)
	local ty = smoothStep(y - y0)

	local v00 = hashToUnitFloat(hashCoordinatesInternal(x0, y0, 0, seed))
	local v10 = hashToUnitFloat(hashCoordinatesInternal(x1, y0, 0, seed))
	local v01 = hashToUnitFloat(hashCoordinatesInternal(x0, y1, 0, seed))
	local v11 = hashToUnitFloat(hashCoordinatesInternal(x1, y1, 0, seed))

	local top = lerp(v00, v10, tx)
	local bottom = lerp(v01, v11, tx)
	return lerp(top, bottom, ty)
end

local function sampleValueNoise3D(seed: number, x: number, y: number, z: number): number
	local x0 = floorToInteger(x)
	local y0 = floorToInteger(y)
	local z0 = floorToInteger(z)
	local x1 = x0 + 1
	local y1 = y0 + 1
	local z1 = z0 + 1

	local tx = smoothStep(x - x0)
	local ty = smoothStep(y - y0)
	local tz = smoothStep(z - z0)

	local c000 = hashToUnitFloat(hashCoordinatesInternal(x0, y0, z0, seed))
	local c100 = hashToUnitFloat(hashCoordinatesInternal(x1, y0, z0, seed))
	local c010 = hashToUnitFloat(hashCoordinatesInternal(x0, y1, z0, seed))
	local c110 = hashToUnitFloat(hashCoordinatesInternal(x1, y1, z0, seed))
	local c001 = hashToUnitFloat(hashCoordinatesInternal(x0, y0, z1, seed))
	local c101 = hashToUnitFloat(hashCoordinatesInternal(x1, y0, z1, seed))
	local c011 = hashToUnitFloat(hashCoordinatesInternal(x0, y1, z1, seed))
	local c111 = hashToUnitFloat(hashCoordinatesInternal(x1, y1, z1, seed))

	local x00 = lerp(c000, c100, tx)
	local x10 = lerp(c010, c110, tx)
	local x01 = lerp(c001, c101, tx)
	local x11 = lerp(c011, c111, tx)

	local y0v = lerp(x00, x10, ty)
	local y1v = lerp(x01, x11, ty)
	return lerp(y0v, y1v, tz)
end

function DeterministicRNG.New(seedRaw: any): RNG
	local seed = normalizeSeed(seedRaw)
	local self = setmetatable({
		state = seed,
		initialSeed = seed,
	}, RNG)
	return self
end

function RNG.NextUInt32(self: RNG): number
	self.state = xorshift32(self.state)
	return self.state
end

function RNG.NextNumber(self: RNG): number
	local nextSeed, value = Rand.number(self.state)
	self.state = nextSeed
	return value
end

function RNG.NextInteger(self: RNG, minValueRaw: any, maxValueRaw: any): number
	local minValue = if typeof(minValueRaw) == "number" then math.floor(minValueRaw) else 0
	local maxValue = if typeof(maxValueRaw) == "number" then math.floor(maxValueRaw) else minValue
	if maxValue < minValue then
		local tmp = maxValue
		maxValue = minValue
		minValue = tmp
	end
	local span = maxValue - minValue + 1
	if span <= 1 then
		return minValue
	end

	local nextSeed, value = Rand.integer(self.state, minValue, maxValue)
	self.state = nextSeed
	return value
end

function RNG.NextRange(self: RNG, minValueRaw: any, maxValueRaw: any): number
	local minValue = if typeof(minValueRaw) == "number" then minValueRaw else 0
	local maxValue = if typeof(maxValueRaw) == "number" then maxValueRaw else 1
	if maxValue < minValue then
		local tmp = maxValue
		maxValue = minValue
		minValue = tmp
	end

	local nextSeed, value = Rand.number(self.state, minValue, maxValue)
	self.state = nextSeed
	return value
end

function RNG.Chance(self: RNG, probabilityRaw: any): boolean
	local probability = if typeof(probabilityRaw) == "number" then probabilityRaw else 0
	local nextSeed, value = Rand.chance(self.state, probability)
	self.state = nextSeed
	return value
end

function RNG.pickWeighted<T>(self: RNG, entries: { WeightedEntry<T> }): T?
	local nextSeed, picked = Rand.weighted(self.state, entries)
	self.state = nextSeed
	return picked
end

function RNG.shuffleInPlace<T>(self: RNG, array: { T }): { T }
	for index = #array, 2, -1 do
		local swapIndex = self:nextInteger(1, index)
		array[index], array[swapIndex] = array[swapIndex], array[index]
	end
	return array
end

function RNG.Fork(self: RNG, saltRaw: any): RNG
	local salt = normalizeSeed(saltRaw)
	local derived = hashCoordinatesInternal(self.state, salt, self.initialSeed, 0x9E3779B9)
	return DeterministicRNG.New(derived)
end

function RNG.Reset(self: RNG)
	self.state = self.initialSeed
end

function DeterministicRNG.SeedFrom(seedRaw: any): number
	return normalizeSeed(seedRaw)
end

function DeterministicRNG.HashString(value: string): number
	return Rand.hashString(value)
end

function DeterministicRNG.HashCoordinates(x: number, y: number, z: number?, seedRaw: any): number
	local zValue = if typeof(z) == "number" then z else 0
	return hashCoordinatesInternal(x, y, zValue, normalizeSeed(seedRaw))
end

function DeterministicRNG.CoordinateRandom01(x: number, y: number, z: number?, seedRaw: any): number
	return hashToUnitFloat(DeterministicRNG.HashCoordinates(x, y, z, seedRaw))
end

function DeterministicRNG.CreateNoise(seedRaw: any): NoiseWrapper
	local seed = normalizeSeed(seedRaw)
	local wrapper = {
		seed = seed,
	} :: NoiseWrapper

	function wrapper.Sample2D(self: NoiseWrapper, x: number, y: number, scaleRaw: any): number
		local scale = if typeof(scaleRaw) == "number" and scaleRaw ~= 0 then scaleRaw else 1
		return sampleValueNoise2D(self.seed, x / scale, y / scale)
	end

	function wrapper.Sample3D(self: NoiseWrapper, x: number, y: number, z: number, scaleRaw: any): number
		local scale = if typeof(scaleRaw) == "number" and scaleRaw ~= 0 then scaleRaw else 1
		return sampleValueNoise3D(self.seed, x / scale, y / scale, z / scale)
	end

	function wrapper.Fbm2D(
		self: NoiseWrapper,
		x: number,
		y: number,
		octavesRaw: any,
		persistenceRaw: any,
		lacunarityRaw: any
	): number
		local octaves = clampInteger(octavesRaw, 1, 12)
		local persistence = if typeof(persistenceRaw) == "number" then persistenceRaw else 0.5
		local lacunarity = if typeof(lacunarityRaw) == "number" then lacunarityRaw else 2

		return Noise.fbmOctaves(octaves, persistence, lacunarity, function(_, frequency)
			return sampleValueNoise2D(self.seed, x * frequency, y * frequency)
		end)
	end

	function wrapper.Fbm3D(
		self: NoiseWrapper,
		x: number,
		y: number,
		z: number,
		octavesRaw: any,
		persistenceRaw: any,
		lacunarityRaw: any
	): number
		local octaves = clampInteger(octavesRaw, 1, 12)
		local persistence = if typeof(persistenceRaw) == "number" then persistenceRaw else 0.5
		local lacunarity = if typeof(lacunarityRaw) == "number" then lacunarityRaw else 2

		return Noise.fbmOctaves(octaves, persistence, lacunarity, function(_, frequency)
			return sampleValueNoise3D(self.seed, x * frequency, y * frequency, z * frequency)
		end)
	end

	wrapper.sample2D = wrapper.Sample2D
	wrapper.sample3D = wrapper.Sample3D
	wrapper.fbm2D = wrapper.Fbm2D
	wrapper.fbm3D = wrapper.Fbm3D

	return wrapper
end

function DeterministicRNG.weightedPick<T>(seedRaw: any, entries: { WeightedEntry<T> }): T?
	local rng = DeterministicRNG.New(seedRaw)
	return rng:pickWeighted(entries)
end

DeterministicRNG.new = DeterministicRNG.New
RNG.nextUInt32 = RNG.NextUInt32
RNG.nextNumber = RNG.NextNumber
RNG.nextInteger = RNG.NextInteger
RNG.nextRange = RNG.NextRange
RNG.chance = RNG.Chance
RNG.fork = RNG.Fork
RNG.reset = RNG.Reset
DeterministicRNG.seedFrom = DeterministicRNG.SeedFrom
DeterministicRNG.hashString = DeterministicRNG.HashString
DeterministicRNG.hashCoordinates = DeterministicRNG.HashCoordinates
DeterministicRNG.coordinateRandom01 = DeterministicRNG.CoordinateRandom01
DeterministicRNG.createNoise = DeterministicRNG.CreateNoise

return DeterministicRNG
