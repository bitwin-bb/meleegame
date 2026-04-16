--!strict
-- Stateless deterministic random helpers built around explicit seeds.

local Num = require(script.Parent.Num)

local Rand = {}

export type SeedInput = number | string | boolean

export type WeightedEntry<T> = {
	value: T,
	weight: number,
}

local UINT32_MAX = 4294967295
local UINT32_MOD = 4294967296
local DEFAULT_SEED = 1

local function normalizeUint32(value: number): number
	local integer = math.floor(value) % UINT32_MOD
	if integer < 0 then
		integer = integer + UINT32_MOD
	end
	if integer == 0 then
		integer = DEFAULT_SEED
	end
	return integer
end

function Rand.Uint32(value: number): number
	return normalizeUint32(value)
end

function Rand.HashString(source: string): number
	local hash = 2166136261
	for index = 1, #source do
		hash = bit32.bxor(hash, string.byte(source, index))
		hash = (hash * 16777619) % UINT32_MOD
	end
	return normalizeUint32(hash)
end

function Rand.HashCoordinates(seed: number, x: number, y: number, z: number?): number
	local xi = normalizeUint32(x)
	local yi = normalizeUint32(y)
	local zi = normalizeUint32(z or 0)

	local hash = normalizeUint32(seed)
	hash = bit32.bxor(hash, bit32.band(xi * 374761393, UINT32_MAX))
	hash = bit32.bxor(hash, bit32.band(yi * 668265263, UINT32_MAX))
	hash = bit32.bxor(hash, bit32.band(zi * 2147483647, UINT32_MAX))
	hash = bit32.band(hash * 1274126177, UINT32_MAX)
	hash = bit32.bxor(hash, bit32.rshift(hash, 16))
	return normalizeUint32(hash)
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

function Rand.Seed(seedRaw: SeedInput?): number
	local kind = typeof(seedRaw)
	if kind == "nil" then
		return DEFAULT_SEED
	end
	if kind == "number" then
		return normalizeUint32(seedRaw :: number)
	end
	if kind == "string" then
		return Rand.HashString(seedRaw :: string)
	end
	if kind == "boolean" then
		return if seedRaw == true then 1 else 2
	end
	return Rand.HashString(tostring(seedRaw))
end

function Rand.Step(seed: number): (number, number)
	local nextSeed = xorshift32(normalizeUint32(seed))
	return nextSeed, nextSeed
end

function Rand.Number(seed: number, minValue: number?, maxValue: number?): (number, number)
	local nextSeed, raw = Rand.Step(seed)
	local unit = raw / UINT32_MOD

	if minValue == nil and maxValue == nil then
		return nextSeed, unit
	end

	local minResolved = if minValue ~= nil then minValue else 0
	local maxResolved = if maxValue ~= nil then maxValue else 1
	if maxResolved < minResolved then
		local temporary = maxResolved
		maxResolved = minResolved
		minResolved = temporary
	end

	return nextSeed, minResolved + (maxResolved - minResolved) * unit
end

function Rand.Integer(seed: number, minValue: number, maxValue: number): (number, number)
	local low = math.floor(minValue)
	local high = math.floor(maxValue)
	if high < low then
		local temporary = high
		high = low
		low = temporary
	end

	local span = high - low + 1
	if span <= 1 then
		return normalizeUint32(seed), low
	end

	local nextSeed, raw = Rand.Step(seed)
	return nextSeed, low + (raw % span)
end

function Rand.Chance(seed: number, probability: number): (number, boolean)
	local nextSeed, value = Rand.Number(seed)
	return nextSeed, value <= Num.saturate(probability)
end

function Rand.pick<T>(seed: number, values: { T }): (number, T?)
	if #values == 0 then
		return normalizeUint32(seed), nil
	end

	local nextSeed, index = Rand.Integer(seed, 1, #values)
	return nextSeed, values[index]
end

function Rand.weighted<T>(seed: number, entries: { WeightedEntry<T> }): (number, T?)
	if #entries == 0 then
		return normalizeUint32(seed), nil
	end

	local totalWeight = 0
	for _, entry in entries do
		if entry.weight > 0 then
			totalWeight = totalWeight + entry.weight
		end
	end

	if totalWeight <= 0 then
		return normalizeUint32(seed), entries[1].value
	end

	local nextSeed, roll = Rand.Number(seed, 0, totalWeight)
	local running = 0
	for _, entry in entries do
		local weight = if entry.weight > 0 then entry.weight else 0
		running = running + weight
		if roll <= running then
			return nextSeed, entry.value
		end
	end

	return nextSeed, entries[#entries].value
end

function Rand.shuffle<T>(seed: number, values: { T }): (number, { T })
	local result = table.clone(values)

	local currentSeed = normalizeUint32(seed)
	for index = #result, 2, -1 do
		local swapIndex
		currentSeed, swapIndex = Rand.Integer(currentSeed, 1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end

	return currentSeed, result
end

function Rand.Fork(seed: number, salt: SeedInput?): number
	local mixed = bit32.bxor(normalizeUint32(seed), Rand.Seed(salt))
	return xorshift32(normalizeUint32(mixed))
end

Rand.uint32 = Rand.Uint32
Rand.hashString = Rand.HashString
Rand.hashCoordinates = Rand.HashCoordinates
Rand.seed = Rand.Seed
Rand.step = Rand.Step
Rand.number = Rand.Number
Rand.integer = Rand.Integer
Rand.chance = Rand.Chance
Rand.fork = Rand.Fork

return Rand
