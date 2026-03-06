--!strict

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

local UINT32_MAX = 4294967295
local UINT32_FLOAT_DENOMINATOR = 4294967296
local DEFAULT_SEED = 1

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

local function normalizeUint32(valueRaw: any): number
	local value = if typeof(valueRaw) == "number" then valueRaw else DEFAULT_SEED
	value = math.floor(value)
	value = value % UINT32_FLOAT_DENOMINATOR
	if value < 0 then
		value += UINT32_FLOAT_DENOMINATOR
	end
	if value == 0 then
		value = DEFAULT_SEED
	end
	return value
end

local function fnv1aHashString(source: string): number
	local hash = 2166136261
	for index = 1, #source do
		hash = bit32.bxor(hash, string.byte(source, index))
		hash = (hash * 16777619) % UINT32_FLOAT_DENOMINATOR
	end
	return normalizeUint32(hash)
end

local function normalizeSeed(seedRaw: any): number
	local kind = typeof(seedRaw)
	if kind == "number" then
		return normalizeUint32(seedRaw)
	end
	if kind == "string" then
		return fnv1aHashString(seedRaw)
	end
	if kind == "boolean" then
		if seedRaw then
			return 1
		end
		return 2
	end
	if kind == "nil" then
		return DEFAULT_SEED
	end
	return fnv1aHashString(tostring(seedRaw))
end

local function xorshift32(state: number): number
	local x = bit32.bxor(state, bit32.lshift(state, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	x = bit32.band(x, UINT32_MAX)
	if x == 0 then
		return DEFAULT_SEED
	end
	return x
end

local function floorToInteger(value: number): number
	if value >= 0 then
		return math.floor(value)
	end
	return math.ceil(value) - 1
end

local function hashCoordinatesInternal(xRaw: number, yRaw: number, zRaw: number, seedRaw: number): number
	local x = normalizeUint32(floorToInteger(xRaw))
	local y = normalizeUint32(floorToInteger(yRaw))
	local z = normalizeUint32(floorToInteger(zRaw))
	local seed = normalizeUint32(seedRaw)

	local hash = seed
	hash = bit32.bxor(hash, bit32.band(x * 374761393, UINT32_MAX))
	hash = bit32.bxor(hash, bit32.band(y * 668265263, UINT32_MAX))
	hash = bit32.bxor(hash, bit32.band(z * 2147483647, UINT32_MAX))
	hash = bit32.band(hash * 1274126177, UINT32_MAX)
	hash = bit32.bxor(hash, bit32.rshift(hash, 16))
	return normalizeUint32(hash)
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

function DeterministicRNG.new(seedRaw: any): RNG
	local seed = normalizeSeed(seedRaw)
	local self = setmetatable({
		state = seed,
		initialSeed = seed,
	}, RNG)
	return self
end

function RNG.nextUInt32(self: RNG): number
	self.state = xorshift32(self.state)
	return self.state
end

function RNG.nextNumber(self: RNG): number
	return self:nextUInt32() / UINT32_FLOAT_DENOMINATOR
end

function RNG.nextInteger(self: RNG, minValueRaw: any, maxValueRaw: any): number
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
	local value = self:nextUInt32() % span
	return minValue + value
end

function RNG.nextRange(self: RNG, minValueRaw: any, maxValueRaw: any): number
	local minValue = if typeof(minValueRaw) == "number" then minValueRaw else 0
	local maxValue = if typeof(maxValueRaw) == "number" then maxValueRaw else 1
	if maxValue < minValue then
		local tmp = maxValue
		maxValue = minValue
		minValue = tmp
	end
	return minValue + (maxValue - minValue) * self:nextNumber()
end

function RNG.chance(self: RNG, probabilityRaw: any): boolean
	local probability = if typeof(probabilityRaw) == "number" then math.clamp(probabilityRaw, 0, 1) else 0
	return self:nextNumber() <= probability
end

function RNG.pickWeighted<T>(self: RNG, entries: { WeightedEntry<T> }): T?
	if #entries == 0 then
		return nil
	end

	local totalWeight = 0
	for _, entry in entries do
		if typeof(entry.weight) == "number" and entry.weight > 0 then
			totalWeight += entry.weight
		end
	end
	if totalWeight <= 0 then
		return entries[1].value
	end

	local roll = self:nextNumber() * totalWeight
	local running = 0
	for _, entry in entries do
		local weight = if typeof(entry.weight) == "number" and entry.weight > 0 then entry.weight else 0
		running += weight
		if roll <= running then
			return entry.value
		end
	end
	return entries[#entries].value
end

function RNG.shuffleInPlace<T>(self: RNG, array: { T }): { T }
	for index = #array, 2, -1 do
		local swapIndex = self:nextInteger(1, index)
		array[index], array[swapIndex] = array[swapIndex], array[index]
	end
	return array
end

function RNG.fork(self: RNG, saltRaw: any): RNG
	local salt = normalizeSeed(saltRaw)
	local derived = hashCoordinatesInternal(self.state, salt, self.initialSeed, 0x9E3779B9)
	return DeterministicRNG.new(derived)
end

function RNG.reset(self: RNG)
	self.state = self.initialSeed
end

function DeterministicRNG.seedFrom(seedRaw: any): number
	return normalizeSeed(seedRaw)
end

function DeterministicRNG.hashString(value: string): number
	return fnv1aHashString(value)
end

function DeterministicRNG.hashCoordinates(x: number, y: number, z: number?, seedRaw: any): number
	local zValue = if typeof(z) == "number" then z else 0
	return hashCoordinatesInternal(x, y, zValue, normalizeSeed(seedRaw))
end

function DeterministicRNG.coordinateRandom01(x: number, y: number, z: number?, seedRaw: any): number
	return hashToUnitFloat(DeterministicRNG.hashCoordinates(x, y, z, seedRaw))
end

function DeterministicRNG.createNoise(seedRaw: any): NoiseWrapper
	local seed = normalizeSeed(seedRaw)
	local wrapper = {
		seed = seed,
	} :: NoiseWrapper

	function wrapper.sample2D(self: NoiseWrapper, x: number, y: number, scaleRaw: any): number
		local scale = if typeof(scaleRaw) == "number" and scaleRaw ~= 0 then scaleRaw else 1
		return sampleValueNoise2D(self.seed, x / scale, y / scale)
	end

	function wrapper.sample3D(self: NoiseWrapper, x: number, y: number, z: number, scaleRaw: any): number
		local scale = if typeof(scaleRaw) == "number" and scaleRaw ~= 0 then scaleRaw else 1
		return sampleValueNoise3D(self.seed, x / scale, y / scale, z / scale)
	end

	function wrapper.fbm2D(
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
		local amplitude = 1
		local frequency = 1
		local total = 0
		local normalizer = 0
		for _ = 1, octaves do
			total += sampleValueNoise2D(self.seed, x * frequency, y * frequency) * amplitude
			normalizer += amplitude
			amplitude *= persistence
			frequency *= lacunarity
		end
		if normalizer <= 0 then
			return 0
		end
		return total / normalizer
	end

	function wrapper.fbm3D(
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
		local amplitude = 1
		local frequency = 1
		local total = 0
		local normalizer = 0
		for _ = 1, octaves do
			total += sampleValueNoise3D(self.seed, x * frequency, y * frequency, z * frequency) * amplitude
			normalizer += amplitude
			amplitude *= persistence
			frequency *= lacunarity
		end
		if normalizer <= 0 then
			return 0
		end
		return total / normalizer
	end

	return wrapper
end

function DeterministicRNG.weightedPick<T>(seedRaw: any, entries: { WeightedEntry<T> }): T?
	local rng = DeterministicRNG.new(seedRaw)
	return rng:pickWeighted(entries)
end

return DeterministicRNG
