local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")
local VariantPicker = require("VariantPicker")

local BlendRule = {}

BlendRule.Name = "TerrariaBlend"
-- ported from terraria tileframe neighbor and blend ordering
-- slope and half tile frames stay unreachable until replicated tile state can represent them
BlendRule.Strictness = Table.readonly({
	Base = 0,
	Blend = 1,
	Grass = 2,
})

local EDGE_MASK = 0x00001111
local CORNER_MASK = 0x11110000

local function parseCell(cellName: string): Vector2
	local row = string.byte(cellName, 1) - string.byte("A")
	local column = assert(tonumber(string.sub(cellName, 2))) - 1
	return Vector2.new(column, row)
end

local function createVariants(cellStart: string, cellEnd: string): { any }
	local first = parseCell(cellStart)
	local third = parseCell(cellEnd)
	local second = third - (third - first) / 2
	return {
		{ Cell = first },
		{ Cell = second },
		{ Cell = third },
	}
end

local function createRule(
	cornerInclusionMask: number,
	cornerExclusionMask: number,
	blendInclusionMask: number,
	blendExclusionMask: number,
	cellStart: string,
	cellEnd: string
): any
	return {
		cornerInclusionMask = cornerInclusionMask,
		cornerExclusionMask = cornerExclusionMask,
		blendInclusionMask = blendInclusionMask,
		blendExclusionMask = blendExclusionMask,
		variants = createVariants(cellStart, cellEnd),
	}
end

local function createBaseRule(cornerExclusionMask: number, cellStart: string, cellEnd: string): any
	return createRule(0, cornerExclusionMask, 0, 0, cellStart, cellEnd)
end

local function createBlendRule(
	cornerExclusionMask: number,
	blendInclusionMask: number,
	blendCornerExclusionMask: number,
	cellStart: string,
	cellEnd: string
): any
	return createRule(
		0,
		cornerExclusionMask,
		blendInclusionMask,
		bit32.lshift(blendCornerExclusionMask, 16),
		cellStart,
		cellEnd
	)
end

local function addFirst(rules: { any }, rule: any)
	table.insert(rules, 1, rule)
end

local function addLast(rules: { any }, rule: any)
	table.insert(rules, rule)
end

local function matches(rule: any, neighborMask: number, blendMask: number): boolean
	local cornerInclusion = bit32.band(bit32.lshift(rule.cornerInclusionMask, 16), CORNER_MASK)
	if bit32.band(cornerInclusion, neighborMask) ~= cornerInclusion then
		return false
	end

	local cornerExclusion = bit32.band(bit32.lshift(rule.cornerExclusionMask, 16), CORNER_MASK)
	if cornerExclusion ~= 0 and bit32.band(cornerExclusion, neighborMask) ~= 0 then
		return false
	end

	local blendEdges = bit32.band(rule.blendInclusionMask, EDGE_MASK)
	if blendEdges ~= 0 and bit32.bxor(blendEdges, bit32.band(blendMask, EDGE_MASK)) ~= 0 then
		return false
	end

	local blendCorners = bit32.band(rule.blendInclusionMask, CORNER_MASK)
	if bit32.band(blendCorners, blendMask) ~= blendCorners then
		return false
	end

	local excludedBlendEdges = bit32.band(rule.blendExclusionMask, EDGE_MASK)
	if bit32.band(excludedBlendEdges, blendMask) ~= 0 then
		return false
	end

	local excludedBlendCorners = bit32.band(rule.blendExclusionMask, CORNER_MASK)
	return excludedBlendCorners == 0 or bit32.band(excludedBlendCorners, blendMask) == 0
end

local function matchesRelaxed(rule: any, neighborMask: number, blendMask: number): boolean
	local column = 0x00010000
	for _ = 1, 4 do
		local sameCorner = bit32.band(bit32.lshift(rule.cornerInclusionMask, 16), column)
		local blendCorner = bit32.band(rule.blendInclusionMask, column)
		if bit32.band(sameCorner, blendCorner) == 0 then
			if sameCorner ~= 0 and bit32.band(sameCorner, neighborMask) == 0 then
				return false
			end
			if blendCorner ~= 0 and bit32.band(blendCorner, blendMask) == 0 then
				return false
			end
		elseif bit32.band(sameCorner, neighborMask) == 0 and bit32.band(blendCorner, blendMask) == 0 then
			return false
		end
		column = bit32.lshift(column, 4)
	end

	local cornerExclusion = bit32.band(bit32.lshift(rule.cornerExclusionMask, 16), CORNER_MASK)
	if cornerExclusion ~= 0 and bit32.band(cornerExclusion, neighborMask) ~= 0 then
		return false
	end

	local blendEdges = bit32.band(rule.blendInclusionMask, EDGE_MASK)
	if blendEdges ~= 0 and bit32.bxor(blendEdges, bit32.band(blendMask, EDGE_MASK)) ~= 0 then
		return false
	end

	local excludedBlendEdges = bit32.band(rule.blendExclusionMask, EDGE_MASK)
	if bit32.band(excludedBlendEdges, blendMask) ~= 0 then
		return false
	end

	local excludedBlendCorners = bit32.band(rule.blendExclusionMask, CORNER_MASK)
	return excludedBlendCorners == 0 or bit32.band(excludedBlendCorners, blendMask) == 0
end

local function createRuleBuckets(): ({ [number]: { any } }, { [number]: { any } }, { [number]: { any } })
	local baseRules = {}
	local blendRules = {}
	local grassRules = {}
	for bucket = 0, 15 do
		baseRules[bucket] = {}
		blendRules[bucket] = {}
	end

	addFirst(baseRules[0], createBaseRule(0x0000, "D10", "D12"))
	addFirst(baseRules[1], createBaseRule(0x0000, "A10", "C10"))
	addFirst(baseRules[2], createBaseRule(0x0000, "D7", "D9"))
	addFirst(baseRules[3], createBaseRule(0x0000, "E1", "E5"))
	addFirst(baseRules[4], createBaseRule(0x0000, "A13", "C13"))
	addFirst(baseRules[5], createBaseRule(0x0000, "E7", "E9"))
	addFirst(baseRules[6], createBaseRule(0x0000, "E2", "E6"))
	addFirst(baseRules[7], createBaseRule(0x0000, "C2", "C4"))
	addFirst(baseRules[8], createBaseRule(0x0000, "A7", "A9"))
	addFirst(baseRules[9], createBaseRule(0x0000, "D1", "D5"))
	addFirst(baseRules[10], createBaseRule(0x0000, "A6", "C6"))
	addFirst(baseRules[11], createBaseRule(0x0000, "A1", "C1"))
	addFirst(baseRules[12], createBaseRule(0x0000, "D2", "D6"))
	addFirst(baseRules[13], createBaseRule(0x0000, "A2", "A4"))
	addFirst(baseRules[14], createBaseRule(0x0000, "A5", "C5"))
	addFirst(baseRules[15], createBaseRule(0x0000, "B2", "B4"))
	addFirst(baseRules[15], createBaseRule(0x0110, "A11", "C11"))
	addFirst(baseRules[15], createBaseRule(0x1001, "A12", "C12"))
	addFirst(baseRules[15], createBaseRule(0x0011, "B7", "B9"))
	addFirst(baseRules[15], createBaseRule(0x1100, "C7", "C9"))

	addFirst(blendRules[0], createBlendRule(0x0000, 0x00000001, 0x0000, "N4", "N6"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00000010, 0x0000, "I7", "K7"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00000100, 0x0000, "N1", "N3"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00001000, 0x0000, "F7", "H7"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00000101, 0x0000, "L10", "L12"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00001010, 0x0000, "M7", "O7"))
	addFirst(blendRules[0], createBlendRule(0x0000, 0x00001111, 0x0000, "L7", "L9"))
	addFirst(blendRules[1], createBlendRule(0x0000, 0x00000100, 0x0000, "O1", "O3"))
	addFirst(blendRules[2], createBlendRule(0x0000, 0x00001000, 0x0000, "F8", "H8"))
	addFirst(blendRules[3], createBlendRule(0x0000, 0x00000100, 0x0000, "M1", "M3"))
	addFirst(blendRules[3], createBlendRule(0x0000, 0x00001000, 0x0000, "F5", "H5"))
	addFirst(blendRules[3], createBlendRule(0x0000, 0x00001100, 0x0000, "G3", "K3"))
	addFirst(blendRules[4], createBlendRule(0x0000, 0x00000001, 0x0000, "O4", "O6"))
	addFirst(blendRules[5], createBlendRule(0x0000, 0x00001010, 0x0000, "K9", "K11"))
	addFirst(blendRules[6], createBlendRule(0x0000, 0x00000001, 0x0000, "M4", "M6"))
	addFirst(blendRules[6], createBlendRule(0x0000, 0x00001000, 0x0000, "F6", "H6"))
	addFirst(blendRules[6], createBlendRule(0x0000, 0x00001001, 0x0000, "G4", "K4"))
	addFirst(blendRules[7], createBlendRule(0x0000, 0x00001000, 0x0000, "F9", "F11"))
	addFirst(blendRules[8], createBlendRule(0x0000, 0x00000010, 0x0000, "I8", "K8"))
	addFirst(blendRules[9], createBlendRule(0x0000, 0x00000010, 0x0000, "I5", "K5"))
	addFirst(blendRules[9], createBlendRule(0x0000, 0x00000100, 0x0000, "L1", "L3"))
	addFirst(blendRules[9], createBlendRule(0x0000, 0x00000110, 0x0000, "F3", "J3"))
	addFirst(blendRules[10], createBlendRule(0x0000, 0x00000101, 0x0000, "H11", "J11"))
	addFirst(blendRules[11], createBlendRule(0x0000, 0x00000100, 0x0000, "H10", "J10"))
	addFirst(blendRules[12], createBlendRule(0x0000, 0x00000001, 0x0000, "L4", "L6"))
	addFirst(blendRules[12], createBlendRule(0x0000, 0x00000010, 0x0000, "I6", "K6"))
	addFirst(blendRules[12], createBlendRule(0x0000, 0x00000011, 0x0000, "F4", "J4"))
	addFirst(blendRules[13], createBlendRule(0x0000, 0x00000010, 0x0000, "G9", "G11"))
	addFirst(blendRules[14], createBlendRule(0x0000, 0x00000001, 0x0000, "H9", "J9"))

	for bucket = 0, 15 do
		grassRules[bucket] = table.clone(blendRules[bucket])
		for _, rule in baseRules[bucket] do
			addLast(blendRules[bucket], rule)
		end
	end

	for _, bucket in { 7, 11, 13, 14, 3, 6, 9, 12 } do
		table.remove(grassRules[bucket], 1)
	end

	addFirst(blendRules[1], createBlendRule(0x0000, 0x00001110, 0x0000, "F13", "H13"))
	addFirst(blendRules[2], createBlendRule(0x0000, 0x00001101, 0x0000, "I12", "K12"))
	addFirst(blendRules[4], createBlendRule(0x0000, 0x00001011, 0x0000, "I13", "K13"))
	addFirst(blendRules[5], createBlendRule(0x0000, 0x00000010, 0x0000, "B14", "B16"))
	addFirst(blendRules[5], createBlendRule(0x0000, 0x00001000, 0x0000, "A14", "A16"))
	addFirst(blendRules[8], createBlendRule(0x0000, 0x00000111, 0x0000, "F12", "H12"))
	addFirst(blendRules[10], createBlendRule(0x0000, 0x00000001, 0x0000, "C14", "C16"))
	addFirst(blendRules[10], createBlendRule(0x0000, 0x00000100, 0x0000, "D14", "D16"))
	addFirst(blendRules[15], createBlendRule(0x0000, 0x00010000, 0x0000, "G1", "K1"))
	addFirst(blendRules[15], createBlendRule(0x0000, 0x00100000, 0x0000, "G2", "K2"))
	addFirst(blendRules[15], createBlendRule(0x0000, 0x01000000, 0x0000, "F2", "J2"))
	addFirst(blendRules[15], createBlendRule(0x0000, 0x10000000, 0x0000, "F1", "J1"))

	addLast(grassRules[1], createRule(0x0000, 0x0000, 0x00001010, 0x00000000, "P1", "R1"))
	addLast(grassRules[1], createRule(0x0000, 0x0000, 0x00001110, 0x00000000, "R9", "R11"))
	addLast(grassRules[2], createRule(0x0000, 0x0000, 0x00000101, 0x00000000, "Q3", "Q5"))
	addLast(grassRules[2], createRule(0x0000, 0x0000, 0x00001101, 0x00000000, "Q12", "Q14"))
	addLast(grassRules[3], createRule(0x0000, 0x0001, 0x00000000, 0x00010000, "Q6", "Q8"))
	addLast(grassRules[4], createRule(0x0000, 0x0000, 0x00001010, 0x00000000, "P2", "R2"))
	addLast(grassRules[4], createRule(0x0000, 0x0000, 0x00001011, 0x00000000, "R12", "R14"))
	addLast(grassRules[6], createRule(0x0000, 0x0010, 0x00000000, 0x00100000, "Q9", "Q11"))
	addLast(grassRules[7], createRule(0x0000, 0x0011, 0x00000000, 0x00111000, "O9", "O15"))
	addLast(grassRules[7], createRule(0x0010, 0x0001, 0x00100000, 0x00011000, "T1", "T3"))
	addLast(grassRules[7], createRule(0x0001, 0x0010, 0x00010000, 0x00101000, "T4", "T6"))
	addLast(grassRules[8], createRule(0x0000, 0x0000, 0x00000101, 0x00000000, "P3", "P5"))
	addLast(grassRules[8], createRule(0x0000, 0x0000, 0x00000111, 0x00000000, "P12", "P14"))
	addLast(grassRules[9], createRule(0x0000, 0x1000, 0x00000000, 0x10000000, "P6", "P8"))
	addLast(grassRules[11], createRule(0x0000, 0x1001, 0x00000000, 0x10010100, "N8", "N14"))
	addLast(grassRules[11], createRule(0x1000, 0x0001, 0x10000000, 0x00010100, "U1", "U3"))
	addLast(grassRules[11], createRule(0x0001, 0x1000, 0x00010000, 0x10000100, "U4", "U6"))
	addLast(grassRules[12], createRule(0x0000, 0x0100, 0x00000000, 0x01000000, "P9", "P11"))
	addLast(grassRules[13], createRule(0x0000, 0x1100, 0x00000000, 0x11000010, "M9", "M15"))
	addLast(grassRules[13], createRule(0x0100, 0x1000, 0x01000000, 0x10000010, "S1", "S3"))
	addLast(grassRules[13], createRule(0x1000, 0x0100, 0x10000000, 0x01000010, "S4", "S6"))
	addLast(grassRules[14], createRule(0x0000, 0x0110, 0x00000000, 0x01100001, "N10", "N16"))
	addLast(grassRules[14], createRule(0x0010, 0x0100, 0x00100000, 0x01000001, "V1", "V3"))
	addLast(grassRules[14], createRule(0x0100, 0x0010, 0x01000000, 0x00100001, "V4", "V6"))
	addLast(grassRules[15], createRule(0x0000, 0x1111, 0x00000000, 0x11110000, "N9", "N15"))
	addLast(grassRules[15], createRule(0x0000, 0x0111, 0x10000000, 0x01110000, "S7", "S9"))
	addLast(grassRules[15], createRule(0x0000, 0x1110, 0x00010000, 0x11100000, "T7", "T9"))
	addLast(grassRules[15], createRule(0x0000, 0x1011, 0x01000000, 0x10110000, "U7", "U9"))
	addLast(grassRules[15], createRule(0x0000, 0x1101, 0x00100000, 0x11010000, "V7", "V9"))
	addLast(grassRules[15], createRule(0x0000, 0x1010, 0x00000000, 0x10100000, "R3", "R5"))
	addLast(grassRules[15], createRule(0x0000, 0x0101, 0x00000000, 0x01010000, "R6", "R8"))

	addFirst(grassRules[0], createRule(0x0000, 0x0000, 0x00001110, 0x00000001, "P2", "R2"))
	addFirst(grassRules[0], createRule(0x0000, 0x0000, 0x00001101, 0x00000010, "P3", "P5"))
	addFirst(grassRules[0], createRule(0x0000, 0x0000, 0x00001011, 0x00000100, "P1", "R1"))
	addFirst(grassRules[0], createRule(0x0000, 0x0000, 0x00000111, 0x00001000, "Q3", "Q5"))
	addFirst(grassRules[1], createRule(0x0000, 0x0000, 0x00000110, 0x00001001, "M1", "M3"))
	addFirst(grassRules[1], createRule(0x0000, 0x0000, 0x00001100, 0x00000011, "L1", "L3"))
	addFirst(grassRules[2], createRule(0x0000, 0x0000, 0x00001001, 0x00000110, "F5", "H5"))
	addFirst(grassRules[2], createRule(0x0000, 0x0000, 0x00001100, 0x00000011, "F6", "H6"))
	addFirst(grassRules[3], createRule(0x0000, 0x0001, 0x00001100, 0x00010000, "G3", "K3"))
	addFirst(grassRules[4], createRule(0x0000, 0x0000, 0x00000011, 0x00001100, "M4", "M6"))
	addFirst(grassRules[4], createRule(0x0000, 0x0000, 0x00001001, 0x00000110, "L4", "L6"))
	addFirst(grassRules[6], createRule(0x0000, 0x0010, 0x00001001, 0x00100000, "G4", "K4"))
	addLast(grassRules[7], createRule(0x0000, 0x0011, 0x00001000, 0x00110000, "B7", "B9"))
	addLast(grassRules[7], createRule(0x0000, 0x0001, 0x00001000, 0x00010000, "G3", "K3"))
	addLast(grassRules[7], createRule(0x0000, 0x0010, 0x00001000, 0x00100000, "G4", "K4"))
	addFirst(grassRules[8], createRule(0x0000, 0x0000, 0x00000011, 0x00001100, "I5", "K5"))
	addFirst(grassRules[8], createRule(0x0000, 0x0000, 0x00000110, 0x00001001, "I6", "K6"))
	addFirst(grassRules[9], createRule(0x0000, 0x1000, 0x00000110, 0x10000000, "F3", "J3"))
	addLast(grassRules[11], createRule(0x0000, 0x1001, 0x00000100, 0x10010000, "A12", "C12"))
	addLast(grassRules[11], createRule(0x0000, 0x0001, 0x00000100, 0x00010000, "G3", "K3"))
	addLast(grassRules[11], createRule(0x0000, 0x1000, 0x00000100, 0x10000000, "F3", "J3"))
	addFirst(grassRules[12], createRule(0x0000, 0x0100, 0x00000011, 0x01000000, "F4", "J4"))
	addLast(grassRules[13], createRule(0x0000, 0x1100, 0x00000010, 0x11000000, "C7", "C9"))
	addLast(grassRules[13], createRule(0x0000, 0x0100, 0x00000010, 0x01000000, "F4", "J4"))
	addLast(grassRules[13], createRule(0x0000, 0x1000, 0x00000010, 0x10000000, "F3", "J3"))
	addLast(grassRules[14], createRule(0x0000, 0x0110, 0x00000001, 0x01100000, "A11", "C11"))
	addLast(grassRules[14], createRule(0x0000, 0x0010, 0x00000001, 0x00100000, "G4", "K4"))
	addLast(grassRules[14], createRule(0x0000, 0x0100, 0x00000001, 0x01000000, "F4", "J4"))
	addLast(grassRules[15], createRule(0x0000, 0x0011, 0x00000000, 0x00110000, "B7", "B9"))
	addLast(grassRules[15], createRule(0x0000, 0x1100, 0x00000000, 0x11000000, "C7", "C9"))
	addLast(grassRules[15], createRule(0x0000, 0x0110, 0x00000000, 0x01100000, "A11", "C11"))
	addLast(grassRules[15], createRule(0x0000, 0x1001, 0x00000000, 0x10010000, "A12", "C12"))
	addLast(grassRules[15], createRule(0x0000, 0x0001, 0x00000000, 0x00010000, "G3", "K3"))
	addLast(grassRules[15], createRule(0x0000, 0x0010, 0x00000000, 0x00100000, "G4", "K4"))
	addLast(grassRules[15], createRule(0x0000, 0x0100, 0x00000000, 0x01000000, "F4", "J4"))
	addLast(grassRules[15], createRule(0x0000, 0x1000, 0x00000000, 0x10000000, "F3", "J3"))

	return baseRules, blendRules, grassRules
end

local BASE_RULES, BLEND_RULES, GRASS_RULES = createRuleBuckets()
local FALLBACK_VARIANTS = createVariants("A1", "A1")

local MASK_TRANSLATIONS = Table.readonly({
	{ source = DirectionBits.N, target = 0x00000010 },
	{ source = DirectionBits.E, target = 0x00000001 },
	{ source = DirectionBits.S, target = 0x00001000 },
	{ source = DirectionBits.W, target = 0x00000100 },
	{ source = DirectionBits.NE, target = 0x00010000 },
	{ source = DirectionBits.SE, target = 0x10000000 },
	{ source = DirectionBits.SW, target = 0x01000000 },
	{ source = DirectionBits.NW, target = 0x00100000 },
})

local function toTerrariaMask(maskRaw: any): number
	local mask = if typeof(maskRaw) == "number" then bit32.band(math.floor(maskRaw), DirectionBits.AllMask) else 0
	local translated = 0
	for _, mapping in MASK_TRANSLATIONS do
		if bit32.band(mask, mapping.source) ~= 0 then
			translated = bit32.bor(translated, mapping.target)
		end
	end
	return translated
end

local function getBucket(mask: number): number
	local bucket = 0
	if bit32.band(mask, 0x00000001) ~= 0 then
		bucket += 1
	end
	if bit32.band(mask, 0x00000010) ~= 0 then
		bucket += 2
	end
	if bit32.band(mask, 0x00000100) ~= 0 then
		bucket += 4
	end
	if bit32.band(mask, 0x00001000) ~= 0 then
		bucket += 8
	end
	return bucket
end

local function findVariants(rules: { any }, sameMask: number, blendMask: number, relaxed: boolean): { any }?
	for _, rule in rules do
		if if relaxed then matchesRelaxed(rule, sameMask, blendMask) else matches(rule, sameMask, blendMask) then
			return rule.variants
		end
	end
	return nil
end

function BlendRule.IsDefinition(definitionRaw: any): boolean
	return typeof(definitionRaw) == "table" and rawget(definitionRaw, "FrameRule") == BlendRule.Name
end

function BlendRule.ResolveVariants(sameMaskRaw: any, blendMaskRaw: any, strictnessRaw: any): { any }
	local sameMask = toTerrariaMask(sameMaskRaw)
	local blendMask = toTerrariaMask(blendMaskRaw)
	local strictness = if typeof(strictnessRaw) == "number" then math.floor(strictnessRaw) else 0
	local bucket = getBucket(sameMask)
	local variants
	if strictness == BlendRule.Strictness.Grass then
		variants = findVariants(GRASS_RULES[bucket], sameMask, blendMask, true)
		if variants == nil then
			sameMask = bit32.bor(sameMask, blendMask)
			variants = findVariants(BASE_RULES[getBucket(sameMask)], sameMask, blendMask, false)
		end
	elseif strictness == BlendRule.Strictness.Blend then
		variants = findVariants(BLEND_RULES[bucket], sameMask, blendMask, false)
	else
		variants = findVariants(BASE_RULES[bucket], sameMask, blendMask, false)
	end
	return variants or FALLBACK_VARIANTS
end

function BlendRule.Resolve(sameMaskRaw: any, blendMaskRaw: any, strictnessRaw: any, coordRaw: any, seedRaw: any?): any
	local variants = BlendRule.ResolveVariants(sameMaskRaw, blendMaskRaw, strictnessRaw)
	return variants[VariantPicker.GetTerrariaVariantIndex(coordRaw, seedRaw)]
end

function BlendRule.CreateEntries(strictnessRaw: any): { [number]: any }
	local entries = {}
	for mask = 0, DirectionBits.AllMask do
		entries[mask] = {
			Variants = BlendRule.ResolveVariants(mask, 0, strictnessRaw),
		}
	end
	return entries
end

return Table.readonly(BlendRule)
