--!strict
-- Seeded deterministic value-noise sampling helpers.

local Rand = require(script.Parent.Rand)
local Num = require(script.Parent.Num)

local Noise = {}

export type SeedInput = number | string | boolean

local UINT32_MOD = 4294967296

local function hashToUnit(hash: number): number
	return (hash % UINT32_MOD) / UINT32_MOD
end

local function fade(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function resolveScale(scale: number?): number
	local resolved = math.abs(scale or 1)
	if resolved == 0 then
		return 1
	end
	return resolved
end

local function unit1(seed: number, x: number): number
	local x0 = math.floor(x)
	local x1 = x0 + 1
	local tx = fade(x - x0)
	local v0 = hashToUnit(Rand.hashCoordinates(seed, x0, 0, 0))
	local v1 = hashToUnit(Rand.hashCoordinates(seed, x1, 0, 0))
	return lerp(v0, v1, tx)
end

local function unit2(seed: number, x: number, y: number): number
	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local x1 = x0 + 1
	local y1 = y0 + 1
	local tx = fade(x - x0)
	local ty = fade(y - y0)

	local v00 = hashToUnit(Rand.hashCoordinates(seed, x0, y0, 0))
	local v10 = hashToUnit(Rand.hashCoordinates(seed, x1, y0, 0))
	local v01 = hashToUnit(Rand.hashCoordinates(seed, x0, y1, 0))
	local v11 = hashToUnit(Rand.hashCoordinates(seed, x1, y1, 0))

	local top = lerp(v00, v10, tx)
	local bottom = lerp(v01, v11, tx)
	return lerp(top, bottom, ty)
end

local function unit3(seed: number, x: number, y: number, z: number): number
	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local z0 = math.floor(z)
	local x1 = x0 + 1
	local y1 = y0 + 1
	local z1 = z0 + 1
	local tx = fade(x - x0)
	local ty = fade(y - y0)
	local tz = fade(z - z0)

	local c000 = hashToUnit(Rand.hashCoordinates(seed, x0, y0, z0))
	local c100 = hashToUnit(Rand.hashCoordinates(seed, x1, y0, z0))
	local c010 = hashToUnit(Rand.hashCoordinates(seed, x0, y1, z0))
	local c110 = hashToUnit(Rand.hashCoordinates(seed, x1, y1, z0))
	local c001 = hashToUnit(Rand.hashCoordinates(seed, x0, y0, z1))
	local c101 = hashToUnit(Rand.hashCoordinates(seed, x1, y0, z1))
	local c011 = hashToUnit(Rand.hashCoordinates(seed, x0, y1, z1))
	local c111 = hashToUnit(Rand.hashCoordinates(seed, x1, y1, z1))

	local x00 = lerp(c000, c100, tx)
	local x10 = lerp(c010, c110, tx)
	local x01 = lerp(c001, c101, tx)
	local x11 = lerp(c011, c111, tx)
	local y00 = lerp(x00, x10, ty)
	local y11 = lerp(x01, x11, ty)
	return lerp(y00, y11, tz)
end

function Noise.ToUnit(value: number): number
	return Num.saturate(value * 0.5 + 0.5)
end

function Noise.ToSigned(value: number): number
	return Num.saturate(value) * 2 - 1
end

function Noise.FbmOctaves(
	octaves: number?,
	persistence: number?,
	lacunarity: number?,
	sampleOctave: (number, number) -> number
): number
	local count = math.max(1, math.floor(octaves or 1))
	local persistenceValue = persistence or 0.5
	local lacunarityValue = lacunarity or 2
	local amplitude = 1
	local frequency = 1
	local total = 0
	local weightTotal = 0

	for octave = 1, count do
		total = total + sampleOctave(octave, frequency) * amplitude
		weightTotal = weightTotal + amplitude
		amplitude = amplitude * persistenceValue
		frequency = frequency * lacunarityValue
	end

	if weightTotal == 0 then
		return 0
	end
	return total / weightTotal
end

function Noise.Sample1(x: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local scaledX = x / resolveScale(scale)
	return Noise.ToSigned(unit1(seed, scaledX))
end

function Noise.Sample2(x: number, y: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return Noise.ToSigned(unit2(seed, x / resolvedScale, y / resolvedScale))
end

function Noise.Sample3(x: number, y: number, z: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return Noise.ToSigned(unit3(seed, x / resolvedScale, y / resolvedScale, z / resolvedScale))
end

function Noise.SampleUnit1(x: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local scaledX = x / resolveScale(scale)
	return unit1(seed, scaledX)
end

function Noise.SampleUnit2(x: number, y: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return unit2(seed, x / resolvedScale, y / resolvedScale)
end

function Noise.SampleUnit3(x: number, y: number, z: number, scale: number?, seedRaw: SeedInput?): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return unit3(seed, x / resolvedScale, y / resolvedScale, z / resolvedScale)
end

function Noise.Fbm1(x: number, scale: number?, seedRaw: SeedInput?, octaves: number?, persistence: number?, lacunarity: number?): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return Noise.FbmOctaves(octaves or 4, persistence or 0.5, lacunarity or 2, function(octave, frequency)
		local octaveSeed = Rand.fork(seed, octave)
		return Noise.ToSigned(unit1(octaveSeed, x / resolvedScale * frequency))
	end)
end

function Noise.Fbm2(
	x: number,
	y: number,
	scale: number?,
	seedRaw: SeedInput?,
	octaves: number?,
	persistence: number?,
	lacunarity: number?
): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return Noise.FbmOctaves(octaves or 4, persistence or 0.5, lacunarity or 2, function(octave, frequency)
		local octaveSeed = Rand.fork(seed, octave)
		return Noise.ToSigned(unit2(octaveSeed, x / resolvedScale * frequency, y / resolvedScale * frequency))
	end)
end

function Noise.Fbm3(
	x: number,
	y: number,
	z: number,
	scale: number?,
	seedRaw: SeedInput?,
	octaves: number?,
	persistence: number?,
	lacunarity: number?
): number
	local seed = Rand.seed(seedRaw)
	local resolvedScale = resolveScale(scale)
	return Noise.FbmOctaves(octaves or 4, persistence or 0.5, lacunarity or 2, function(octave, frequency)
		local octaveSeed = Rand.fork(seed, octave)
		return Noise.ToSigned(unit3(
			octaveSeed,
			x / resolvedScale * frequency,
			y / resolvedScale * frequency,
			z / resolvedScale * frequency
		))
	end)
end

function Noise.FbmUnit1(
	x: number,
	scale: number?,
	seedRaw: SeedInput?,
	octaves: number?,
	persistence: number?,
	lacunarity: number?
): number
	return Noise.ToUnit(Noise.Fbm1(x, scale, seedRaw, octaves, persistence, lacunarity))
end

function Noise.FbmUnit2(
	x: number,
	y: number,
	scale: number?,
	seedRaw: SeedInput?,
	octaves: number?,
	persistence: number?,
	lacunarity: number?
): number
	return Noise.ToUnit(Noise.Fbm2(x, y, scale, seedRaw, octaves, persistence, lacunarity))
end

function Noise.FbmUnit3(
	x: number,
	y: number,
	z: number,
	scale: number?,
	seedRaw: SeedInput?,
	octaves: number?,
	persistence: number?,
	lacunarity: number?
): number
	return Noise.ToUnit(Noise.Fbm3(x, y, z, scale, seedRaw, octaves, persistence, lacunarity))
end

Noise.toUnit = Noise.ToUnit
Noise.toSigned = Noise.ToSigned
Noise.fbmOctaves = Noise.FbmOctaves
Noise.sample1 = Noise.Sample1
Noise.sample2 = Noise.Sample2
Noise.sample3 = Noise.Sample3
Noise.sampleUnit1 = Noise.SampleUnit1
Noise.sampleUnit2 = Noise.SampleUnit2
Noise.sampleUnit3 = Noise.SampleUnit3
Noise.fbm1 = Noise.Fbm1
Noise.fbm2 = Noise.Fbm2
Noise.fbm3 = Noise.Fbm3
Noise.fbmUnit1 = Noise.FbmUnit1
Noise.fbmUnit2 = Noise.FbmUnit2
Noise.fbmUnit3 = Noise.FbmUnit3

return Noise
