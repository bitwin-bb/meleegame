--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Codec = {}

export type SchemaKind = "any" | "nil" | "boolean" | "number" | "integer" | "string" | "array" | "object" | "map" | "literal"

export type SchemaNode = {
	kind: SchemaKind,
	optional: boolean?,
	min: number?,
	max: number?,
	minLength: number?,
	maxLength: number?,
	enum: { any }?,
	literal: any?,
	fields: { [string]: SchemaNode }?,
	element: SchemaNode?,
	key: SchemaNode?,
	value: SchemaNode?,
	allowUnknown: boolean?,
}

export type ValidationResult = {
	ok: boolean,
	errors: { string },
}

export type DeltaEnvelope = {
	__delta: true,
	changes: { [any]: any },
	removals: { any },
}

local FNV_OFFSET_BASIS = 2166136261
local FNV_PRIME = 16777619
local MAX_BITMASK_BITS = 31

local function cloneArray(source: { any }): { any }
	local out = Sift.Array.create(#source)
	for index = 1, #source do
		out[index] = source[index]
	end
	return out
end

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

local function keyTypeRank(key: any): number
	local kind = typeof(key)
	if kind == "number" then
		return 1
	end
	if kind == "string" then
		return 2
	end
	if kind == "boolean" then
		return 3
	end
	return 4
end

local function compareKeys(a: any, b: any): boolean
	local rankA = keyTypeRank(a)
	local rankB = keyTypeRank(b)
	if rankA ~= rankB then
		return rankA < rankB
	end

	local typeA = typeof(a)
	if typeA == "number" then
		return (a :: number) < (b :: number)
	end
	if typeA == "string" then
		return (a :: string) < (b :: string)
	end
	if typeA == "boolean" then
		if a == b then
			return false
		end
		return (a :: boolean) == false
	end
	return tostring(a) < tostring(b)
end

local function collectDeterministicKeys(source: { [any]: any }): { any }
	local keys = {}
	for key in source do
		local kind = typeof(key)
		if kind == "number" or kind == "string" or kind == "boolean" then
			keys[#keys + 1] = key
		else
			error(string.format("Codec deterministic serialization does not support key type '%s'", kind))
		end
	end
	table.sort(keys, compareKeys)
	return keys
end

local function isDenseArray(value: { [any]: any }): boolean
	local expectedCount = #value
	local observedCount = 0
	for key in value do
		if typeof(key) ~= "number" then
			return false
		end
		local numberKey = key :: number
		if numberKey < 1 or numberKey > expectedCount or numberKey % 1 ~= 0 then
			return false
		end
		observedCount += 1
	end
	return observedCount == expectedCount
end

local function appendNumber(builder: { string }, value: number)
	if value ~= value or value == math.huge or value == -math.huge then
		error("Codec cannot serialize NaN or infinite numbers")
	end
	builder[#builder + 1] = "d"
	builder[#builder + 1] = string.format("%.17g", value)
	builder[#builder + 1] = ";"
end

local function appendString(builder: { string }, value: string)
	builder[#builder + 1] = "s"
	builder[#builder + 1] = tostring(#value)
	builder[#builder + 1] = ":"
	builder[#builder + 1] = value
end

local function appendValue(builder: { string }, value: any)
	local kind = typeof(value)
	if kind == "nil" then
		builder[#builder + 1] = "n;"
		return
	end
	if kind == "boolean" then
		builder[#builder + 1] = if value then "t;" else "f;"
		return
	end
	if kind == "number" then
		appendNumber(builder, value)
		return
	end
	if kind == "string" then
		appendString(builder, value)
		return
	end
	if kind == "table" then
		local tableValue = value :: { [any]: any }
		if isDenseArray(tableValue) then
			builder[#builder + 1] = "a"
			builder[#builder + 1] = tostring(#tableValue)
			builder[#builder + 1] = "["
			for index = 1, #tableValue do
				appendValue(builder, tableValue[index])
			end
			builder[#builder + 1] = "]"
			return
		end

		local keys = collectDeterministicKeys(tableValue)
		builder[#builder + 1] = "o"
		builder[#builder + 1] = tostring(#keys)
		builder[#builder + 1] = "{"
		for _, key in keys do
			appendValue(builder, key)
			appendValue(builder, tableValue[key])
		end
		builder[#builder + 1] = "}"
		return
	end

	error(string.format("Codec does not support type '%s'", kind))
end

local function parseNumberToken(source: string, startIndex: number): (number, number)
	local endIndex = string.find(source, ";", startIndex, true)
	if endIndex == nil then
		error("Malformed deterministic payload: number is missing terminator")
	end
	local raw = string.sub(source, startIndex, endIndex - 1)
	local value = tonumber(raw)
	if value == nil then
		error("Malformed deterministic payload: invalid number token")
	end
	return value, endIndex + 1
end

local function parseLength(source: string, startIndex: number, delimiter: string): (number, number)
	local delimiterIndex = string.find(source, delimiter, startIndex, true)
	if delimiterIndex == nil then
		error("Malformed deterministic payload: missing length delimiter")
	end
	local rawLength = string.sub(source, startIndex, delimiterIndex - 1)
	local lengthValue = tonumber(rawLength)
	if lengthValue == nil then
		error("Malformed deterministic payload: invalid length")
	end
	if lengthValue < 0 or lengthValue % 1 ~= 0 then
		error("Malformed deterministic payload: length must be a non-negative integer")
	end
	return lengthValue, delimiterIndex + 1
end

local function parseValue(source: string, startIndex: number): (any, number)
	local tag = string.sub(source, startIndex, startIndex)
	if tag == "n" then
		if string.sub(source, startIndex + 1, startIndex + 1) ~= ";" then
			error("Malformed deterministic payload: nil token")
		end
		return nil, startIndex + 2
	end
	if tag == "t" then
		if string.sub(source, startIndex + 1, startIndex + 1) ~= ";" then
			error("Malformed deterministic payload: boolean token")
		end
		return true, startIndex + 2
	end
	if tag == "f" then
		if string.sub(source, startIndex + 1, startIndex + 1) ~= ";" then
			error("Malformed deterministic payload: boolean token")
		end
		return false, startIndex + 2
	end
	if tag == "d" then
		return parseNumberToken(source, startIndex + 1)
	end
	if tag == "s" then
		local lengthValue, contentIndex = parseLength(source, startIndex + 1, ":")
		local content = string.sub(source, contentIndex, contentIndex + lengthValue - 1)
		if #content ~= lengthValue then
			error("Malformed deterministic payload: string length mismatch")
		end
		return content, contentIndex + lengthValue
	end
	if tag == "a" then
		local count, cursor = parseLength(source, startIndex + 1, "[")
		local out = Sift.Array.create(count)
		for index = 1, count do
			local parsed
			parsed, cursor = parseValue(source, cursor)
			out[index] = parsed
		end
		if string.sub(source, cursor, cursor) ~= "]" then
			error("Malformed deterministic payload: array terminator")
		end
		return out, cursor + 1
	end
	if tag == "o" then
		local count, cursor = parseLength(source, startIndex + 1, "{")
		local out = {}
		for _ = 1, count do
			local key
			key, cursor = parseValue(source, cursor)
			local value
			value, cursor = parseValue(source, cursor)
			out[key] = value
		end
		if string.sub(source, cursor, cursor) ~= "}" then
			error("Malformed deterministic payload: object terminator")
		end
		return out, cursor + 1
	end

	error(string.format("Malformed deterministic payload: unknown tag '%s'", tag))
end

local function fnv1aHashString(source: string): number
	local hash = FNV_OFFSET_BASIS
	for index = 1, #source do
		hash = bit32.bxor(hash, string.byte(source, index))
		hash = (hash * FNV_PRIME) % 4294967296
	end
	return hash
end

local function deepEquals(a: any, b: any): boolean
	local typeA = typeof(a)
	if typeA ~= typeof(b) then
		return false
	end
	if typeA ~= "table" then
		return a == b
	end
	local tableA = a :: { [any]: any }
	local tableB = b :: { [any]: any }
	for key, value in tableA do
		if not deepEquals(value, tableB[key]) then
			return false
		end
	end
	for key in tableB do
		if tableA[key] == nil then
			return false
		end
	end
	return true
end

local function createDeltaRecursive(previous: any, current: any): any
	if deepEquals(previous, current) then
		return nil
	end
	if typeof(previous) ~= "table" or typeof(current) ~= "table" then
		return current
	end

	local previousTable = previous :: { [any]: any }
	local currentTable = current :: { [any]: any }
	local changes = {}
	local removals = {}

	for key, currentValue in currentTable do
		local delta = createDeltaRecursive(previousTable[key], currentValue)
		if delta ~= nil then
			changes[key] = delta
		end
	end

	for key in previousTable do
		if currentTable[key] == nil then
			removals[#removals + 1] = key
		end
	end

	if next(changes) == nil and #removals == 0 then
		return nil
	end

	table.sort(removals, compareKeys)

	return {
		__delta = true,
		changes = changes,
		removals = removals,
	}
end

local function applyDeltaRecursive(previous: any, delta: any): any
	if delta == nil then
		return previous
	end
	if typeof(delta) ~= "table" then
		return delta
	end

	local deltaTable = delta :: { [any]: any }
	if deltaTable.__delta ~= true then
		return deltaTable
	end

	local out = {}
	if typeof(previous) == "table" then
		for key, value in (previous :: { [any]: any }) do
			out[key] = value
		end
	end

	local removals = (deltaTable.removals or {}) :: { any }
	for _, key in removals do
		out[key] = nil
	end

	local changes = (deltaTable.changes or {}) :: { [any]: any }
	for key, value in changes do
		out[key] = applyDeltaRecursive(out[key], value)
	end

	return out
end

local function appendValidationError(errors: { string }, path: string, message: string)
	errors[#errors + 1] = string.format("%s: %s", path, message)
end

local function validateEnum(schema: SchemaNode, value: any): boolean
	if schema.enum == nil then
		return true
	end
	for _, candidate in schema.enum do
		if candidate == value then
			return true
		end
	end
	return false
end

local function validateSchemaNode(schemaRaw: any, value: any, path: string, errors: { string })
	if typeof(schemaRaw) ~= "table" then
		appendValidationError(errors, path, "invalid schema node")
		return
	end

	local schema = schemaRaw :: SchemaNode
	if value == nil then
		if schema.optional then
			return
		end
		if schema.kind == "nil" then
			return
		end
		appendValidationError(errors, path, "value is required")
		return
	end

	if not validateEnum(schema, value) then
		appendValidationError(errors, path, "value is not in enum")
		return
	end

	if schema.kind == "any" then
		return
	end
	if schema.kind == "nil" then
		appendValidationError(errors, path, "expected nil")
		return
	end
	if schema.kind == "boolean" then
		if typeof(value) ~= "boolean" then
			appendValidationError(errors, path, "expected boolean")
		end
		return
	end
	if schema.kind == "number" or schema.kind == "integer" then
		if typeof(value) ~= "number" then
			appendValidationError(errors, path, "expected number")
			return
		end
		if schema.kind == "integer" and value % 1 ~= 0 then
			appendValidationError(errors, path, "expected integer")
		end
		if schema.min ~= nil and value < schema.min then
			appendValidationError(errors, path, string.format("must be >= %s", tostring(schema.min)))
		end
		if schema.max ~= nil and value > schema.max then
			appendValidationError(errors, path, string.format("must be <= %s", tostring(schema.max)))
		end
		return
	end
	if schema.kind == "string" then
		if typeof(value) ~= "string" then
			appendValidationError(errors, path, "expected string")
			return
		end
		if schema.minLength ~= nil and #value < schema.minLength then
			appendValidationError(errors, path, string.format("length must be >= %d", schema.minLength))
		end
		if schema.maxLength ~= nil and #value > schema.maxLength then
			appendValidationError(errors, path, string.format("length must be <= %d", schema.maxLength))
		end
		return
	end
	if schema.kind == "array" then
		if typeof(value) ~= "table" then
			appendValidationError(errors, path, "expected array")
			return
		end
		local arrayValue = value :: { any }
		if not isDenseArray(arrayValue :: any) then
			appendValidationError(errors, path, "expected dense array")
			return
		end
		if schema.minLength ~= nil and #arrayValue < schema.minLength then
			appendValidationError(errors, path, string.format("length must be >= %d", schema.minLength))
		end
		if schema.maxLength ~= nil and #arrayValue > schema.maxLength then
			appendValidationError(errors, path, string.format("length must be <= %d", schema.maxLength))
		end
		local elementSchema = schema.element
		if elementSchema ~= nil then
			for index = 1, #arrayValue do
				validateSchemaNode(elementSchema, arrayValue[index], string.format("%s[%d]", path, index), errors)
			end
		end
		return
	end
	if schema.kind == "object" then
		if typeof(value) ~= "table" then
			appendValidationError(errors, path, "expected object")
			return
		end
		local objectValue = value :: { [string]: any }
		local fields = schema.fields or {}
		for fieldName, fieldSchema in fields do
			validateSchemaNode(fieldSchema, objectValue[fieldName], string.format("%s.%s", path, fieldName), errors)
		end
		if schema.allowUnknown ~= true then
			for key in objectValue do
				if typeof(key) == "string" and fields[key] == nil then
					appendValidationError(errors, string.format("%s.%s", path, key), "unknown field")
				end
			end
		end
		return
	end
	if schema.kind == "map" then
		if typeof(value) ~= "table" then
			appendValidationError(errors, path, "expected map")
			return
		end
		local mapValue = value :: { [any]: any }
		local keySchema = schema.key
		local valueSchema = schema.value
		for mapKey, mapEntry in mapValue do
			if keySchema ~= nil then
				validateSchemaNode(keySchema, mapKey, string.format("%s.<key>", path), errors)
			end
			if valueSchema ~= nil then
				validateSchemaNode(valueSchema, mapEntry, string.format("%s[%s]", path, tostring(mapKey)), errors)
			end
		end
		return
	end
	if schema.kind == "literal" then
		if value ~= schema.literal then
			appendValidationError(errors, path, "literal mismatch")
		end
		return
	end

	appendValidationError(errors, path, string.format("unknown schema kind '%s'", tostring(schema.kind)))
end

local function encodeHexByte(byteValue: number): string
	return string.format("%02X", byteValue)
end

local function decodeHexByte(raw: string): number
	local value = tonumber(raw, 16)
	if value == nil or value < 0 or value > 255 then
		error("Malformed compressed payload: invalid hex byte")
	end
	return value
end

local function encodeCompressedSegmentLiteral(builder: { string }, source: string, startIndex: number, lengthValue: number)
	builder[#builder + 1] = "L"
	builder[#builder + 1] = tostring(lengthValue)
	builder[#builder + 1] = ":"
	builder[#builder + 1] = string.sub(source, startIndex, startIndex + lengthValue - 1)
end

local function encodeCompressedSegmentRun(builder: { string }, byteValue: number, runLength: number)
	builder[#builder + 1] = "R"
	builder[#builder + 1] = tostring(runLength)
	builder[#builder + 1] = ":"
	builder[#builder + 1] = encodeHexByte(byteValue)
	builder[#builder + 1] = ";"
end

function Codec.GetDeterministicKeys(source: { [any]: any }): { any }
	return collectDeterministicKeys(source)
end

function Codec.SerializeDeterministic(value: any): string
	local builder = {}
	appendValue(builder, value)
	return table.concat(builder)
end

function Codec.DeserializeDeterministic(payload: string): any
	if typeof(payload) ~= "string" then
		error("Codec.DeserializeDeterministic expects a string payload")
	end
	local value, cursor = parseValue(payload, 1)
	if cursor <= #payload then
		error("Malformed deterministic payload: trailing bytes detected")
	end
	return value
end

function Codec.Validate(schema: SchemaNode, value: any): ValidationResult
	local errors = {}
	validateSchemaNode(schema, value, "$", errors)
	return {
		ok = #errors == 0,
		errors = errors,
	}
end

function Codec.AssertSchema(schema: SchemaNode, value: any)
	local result = Codec.Validate(schema, value)
	if result.ok then
		return
	end
	error(string.format("Schema validation failed: %s", table.concat(result.errors, " | ")))
end

function Codec.PackBitmask(flags: { boolean }): number
	local bitmask = 0
	local bitLimit = math.min(#flags, MAX_BITMASK_BITS)
	for index = 1, bitLimit do
		if flags[index] then
			bitmask = bit32.bor(bitmask, bit32.lshift(1, index - 1))
		end
	end
	return bitmask
end

function Codec.UnpackBitmask(bitmaskRaw: any, bitCountRaw: any): { boolean }
	local bitmask = clampInteger(bitmaskRaw, 0, 2147483647)
	local bitCount = clampInteger(bitCountRaw, 0, MAX_BITMASK_BITS)
	local flags = Sift.Array.create(bitCount, false)
	for index = 1, bitCount do
		flags[index] = bit32.band(bitmask, bit32.lshift(1, index - 1)) ~= 0
	end
	return flags
end

function Codec.PackNamedBitmask(layout: { [string]: number }, values: { [string]: boolean }): number
	local bitmask = 0
	for key, bitIndex in layout do
		if values[key] then
			local normalizedIndex = clampInteger(bitIndex, 1, MAX_BITMASK_BITS)
			bitmask = bit32.bor(bitmask, bit32.lshift(1, normalizedIndex - 1))
		end
	end
	return bitmask
end

function Codec.UnpackNamedBitmask(layout: { [string]: number }, bitmaskRaw: any): { [string]: boolean }
	local bitmask = clampInteger(bitmaskRaw, 0, 2147483647)
	local out = {}
	for key, bitIndex in layout do
		local normalizedIndex = clampInteger(bitIndex, 1, MAX_BITMASK_BITS)
		out[key] = bit32.band(bitmask, bit32.lshift(1, normalizedIndex - 1)) ~= 0
	end
	return out
end

function Codec.CreateDelta(previous: any, current: any): any
	return createDeltaRecursive(previous, current)
end

function Codec.ApplyDelta(previous: any, delta: any): any
	return applyDeltaRecursive(previous, delta)
end

function Codec.StableHash(value: any): number
	local serialized = Codec.SerializeDeterministic(value)
	return fnv1aHashString(serialized)
end

function Codec.StableHashString(value: string): number
	return fnv1aHashString(value)
end

function Codec.CompressSaveSafe(source: string): string
	if typeof(source) ~= "string" then
		error("Codec.CompressSaveSafe expects a string payload")
	end
	if #source == 0 then
		return "N"
	end

	local builder = {}
	local cursor = 1
	local sourceLength = #source
	while cursor <= sourceLength do
		local startCursor = cursor
		local currentByte = string.byte(source, cursor)
		local runLength = 1
		while cursor + runLength <= sourceLength and runLength < 65535 and string.byte(source, cursor + runLength) == currentByte do
			runLength += 1
		end

		if runLength >= 4 then
			encodeCompressedSegmentRun(builder, currentByte, runLength)
			cursor += runLength
		else
			cursor += runLength
			while cursor <= sourceLength do
				local byteValue = string.byte(source, cursor)
				local innerRun = 1
				while cursor + innerRun <= sourceLength and innerRun < 4 and string.byte(source, cursor + innerRun) == byteValue do
					innerRun += 1
				end
				if innerRun >= 4 then
					break
				end
				cursor += innerRun
			end
			encodeCompressedSegmentLiteral(builder, source, startCursor, cursor - startCursor)
		end
	end

	local compressed = table.concat(builder)
	if #compressed >= #source then
		return "N" .. source
	end
	return "C" .. compressed
end

function Codec.DecompressSaveSafe(source: string): string
	if typeof(source) ~= "string" then
		error("Codec.DecompressSaveSafe expects a string payload")
	end
	if #source == 0 then
		return ""
	end

	local mode = string.sub(source, 1, 1)
	if mode == "N" then
		return string.sub(source, 2)
	end
	if mode ~= "C" then
		error("Malformed compressed payload: unknown mode")
	end

	local cursor = 2
	local sourceLength = #source
	local builder = {}

	while cursor <= sourceLength do
		local token = string.sub(source, cursor, cursor)
		cursor += 1
		if token ~= "L" and token ~= "R" then
			error("Malformed compressed payload: unknown segment token")
		end

		local lengthValue, payloadIndex = parseLength(source, cursor, ":")
		cursor = payloadIndex
		if token == "L" then
			local literal = string.sub(source, cursor, cursor + lengthValue - 1)
			if #literal ~= lengthValue then
				error("Malformed compressed payload: literal length mismatch")
			end
			builder[#builder + 1] = literal
			cursor += lengthValue
		else
			local hexByte = string.sub(source, cursor, cursor + 1)
			if #hexByte ~= 2 then
				error("Malformed compressed payload: missing run byte")
			end
			cursor += 2
			if string.sub(source, cursor, cursor) ~= ";" then
				error("Malformed compressed payload: run segment terminator")
			end
			cursor += 1
			local byteValue = decodeHexByte(hexByte)
			builder[#builder + 1] = string.rep(string.char(byteValue), lengthValue)
		end
	end

	return table.concat(builder)
end

function Codec.SerializeCompressed(value: any): string
	local serialized = Codec.SerializeDeterministic(value)
	return Codec.CompressSaveSafe(serialized)
end

function Codec.DeserializeCompressed(payload: string): any
	local decompressed = Codec.DecompressSaveSafe(payload)
	return Codec.DeserializeDeterministic(decompressed)
end

function Codec.CloneDeterministicArray(source: { any }): { any }
	return cloneArray(source)
end

Codec.getDeterministicKeys = Codec.GetDeterministicKeys
Codec.serializeDeterministic = Codec.SerializeDeterministic
Codec.deserializeDeterministic = Codec.DeserializeDeterministic
Codec.validate = Codec.Validate
Codec.assertSchema = Codec.AssertSchema
Codec.packBitmask = Codec.PackBitmask
Codec.unpackBitmask = Codec.UnpackBitmask
Codec.packNamedBitmask = Codec.PackNamedBitmask
Codec.unpackNamedBitmask = Codec.UnpackNamedBitmask
Codec.createDelta = Codec.CreateDelta
Codec.applyDelta = Codec.ApplyDelta
Codec.stableHash = Codec.StableHash
Codec.stableHashString = Codec.StableHashString
Codec.compressSaveSafe = Codec.CompressSaveSafe
Codec.decompressSaveSafe = Codec.DecompressSaveSafe
Codec.serializeCompressed = Codec.SerializeCompressed
Codec.deserializeCompressed = Codec.DeserializeCompressed
Codec.cloneDeterministicArray = Codec.CloneDeterministicArray

return Codec
