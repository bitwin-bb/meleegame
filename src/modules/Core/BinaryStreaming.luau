--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Codec = require(script.Parent.Codec)

local BinaryStreaming = {}

local Writer = {}
Writer.__index = Writer

local Reader = {}
Reader.__index = Reader

export type Writer = {
	buffer: buffer,
	capacity: number,
	length: number,
	writeUInt8: (self: Writer, value: number) -> (),
	writeUInt16: (self: Writer, value: number) -> (),
	writeUInt32: (self: Writer, value: number) -> (),
	writeBitmask: (self: Writer, bitmask: number, bits: number?) -> (),
	writeBytes: (self: Writer, source: buffer, sourceOffset: number?, byteCount: number?) -> (),
	writeString16: (self: Writer, value: string) -> (),
	writeString32: (self: Writer, value: string) -> (),
	toBuffer: (self: Writer) -> (buffer, number),
	reset: (self: Writer) -> (),
}

export type Reader = {
	buffer: buffer,
	length: number,
	cursor: number,
	readUInt8: (self: Reader) -> number,
	readUInt16: (self: Reader) -> number,
	readUInt32: (self: Reader) -> number,
	readBitmask: (self: Reader, bits: number?) -> number,
	readBytes: (self: Reader, byteCount: number) -> buffer,
	readString16: (self: Reader) -> string,
	readString32: (self: Reader) -> string,
	remaining: (self: Reader) -> number,
}

export type FrameOptions = {
	version: number?,
	checksum: boolean?,
	enableRle: boolean?,
	maxPayloadBytes: number?,
}

export type ParsedFrame = {
	version: number,
	flags: number,
	payload: buffer,
	payloadSize: number,
	checksum: number?,
}

export type ChunkOptions = {
	batchId: number?,
	chunkSize: number?,
	version: number?,
	checksum: boolean?,
	enableRle: boolean?,
}

export type AssemblerResult = {
	completed: boolean,
	batchId: number?,
	payload: buffer?,
	payloadSize: number?,
	error: string?,
}

local FLAG_CHECKSUM = 1
local FLAG_RLE = 2
local DEFAULT_MAGIC = 0xBA71
local DEFAULT_VERSION = 1
local DEFAULT_MAX_PAYLOAD = 1024 * 1024
local DEFAULT_CHUNK_SIZE = 2048

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

local function ensureCapacity(self: Writer, additional: number)
	local required = self.length + additional
	if required <= self.capacity then
		return
	end

	local nextCapacity = self.capacity
	while nextCapacity < required do
		nextCapacity = nextCapacity * 2
	end

	local nextBuffer = buffer.create(nextCapacity)
	buffer.copy(nextBuffer, 0, self.buffer, 0, self.length)
	self.buffer = nextBuffer
	self.capacity = nextCapacity
end

local function createStringBuffer(value: string): (buffer, number)
	local byteLength = #value
	local out = buffer.create(byteLength)
	buffer.writestring(out, 0, value)
	return out, byteLength
end

local function toStringFromBuffer(value: buffer, byteCount: number): string
	if byteCount <= 0 then
		return ""
	end
	return buffer.readstring(value, 0, byteCount)
end

local function fnv1aChecksum(payload: buffer, payloadSize: number): number
	local hash = 2166136261
	for index = 0, payloadSize - 1 do
		hash = bit32.bxor(hash, buffer.readu8(payload, index))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

local function runLengthEncode(payload: buffer, payloadSize: number): (buffer, number, boolean)
	if payloadSize <= 2 then
		local copy = buffer.create(payloadSize)
		buffer.copy(copy, 0, payload, 0, payloadSize)
		return copy, payloadSize, false
	end

	local out = buffer.create(payloadSize * 2)
	local readCursor = 0
	local writeCursor = 0
	while readCursor < payloadSize do
		local byteValue = buffer.readu8(payload, readCursor)
		local runLength = 1
		while readCursor + runLength < payloadSize and runLength < 255 and buffer.readu8(payload, readCursor + runLength) == byteValue do
			runLength += 1
		end
		buffer.writeu8(out, writeCursor, runLength)
		buffer.writeu8(out, writeCursor + 1, byteValue)
		writeCursor += 2
		readCursor += runLength
	end

	if writeCursor >= payloadSize then
		local copy = buffer.create(payloadSize)
		buffer.copy(copy, 0, payload, 0, payloadSize)
		return copy, payloadSize, false
	end

	local resized = buffer.create(writeCursor)
	buffer.copy(resized, 0, out, 0, writeCursor)
	return resized, writeCursor, true
end

local function runLengthDecode(payload: buffer, payloadSize: number): (buffer, number)
	if payloadSize % 2 ~= 0 then
		error("Malformed RLE payload: byte count must be even")
	end

	local expandedSize = 0
	for readCursor = 0, payloadSize - 1, 2 do
		expandedSize += buffer.readu8(payload, readCursor)
	end

	local out = buffer.create(expandedSize)
	local writeCursor = 0
	for readCursor = 0, payloadSize - 1, 2 do
		local runLength = buffer.readu8(payload, readCursor)
		local byteValue = buffer.readu8(payload, readCursor + 1)
		for offset = 1, runLength do
			buffer.writeu8(out, writeCursor, byteValue)
			writeCursor += 1
		end
	end

	return out, writeCursor
end

local function sortDeterministic(values: { any })
	table.sort(values, function(a, b)
		return a < b
	end)
end

function BinaryStreaming.createWriter(initialCapacityRaw: any): Writer
	local initialCapacity = clampInteger(initialCapacityRaw, 64, 16 * 1024 * 1024)
	local self = setmetatable({
		buffer = buffer.create(initialCapacity),
		capacity = initialCapacity,
		length = 0,
	}, Writer)
	return self
end

function Writer.writeUInt8(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 255)
	ensureCapacity(self, 1)
	buffer.writeu8(self.buffer, self.length, value)
	self.length += 1
end

function Writer.writeUInt16(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 65535)
	ensureCapacity(self, 2)
	buffer.writeu16(self.buffer, self.length, value)
	self.length += 2
end

function Writer.writeUInt32(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 4294967295)
	ensureCapacity(self, 4)
	buffer.writeu32(self.buffer, self.length, value)
	self.length += 4
end

function Writer.writeBitmask(self: Writer, bitmaskRaw: any, bitsRaw: any)
	local bits = clampInteger(bitsRaw, 1, 32)
	local bitmask = clampInteger(bitmaskRaw, 0, 4294967295)
	if bits <= 8 then
		self:writeUInt8(bitmask)
		return
	end
	if bits <= 16 then
		self:writeUInt16(bitmask)
		return
	end
	self:writeUInt32(bitmask)
end

function Writer.writeBytes(self: Writer, source: buffer, sourceOffsetRaw: any, byteCountRaw: any)
	if typeof(source) ~= "buffer" then
		error("Writer.writeBytes expects a buffer source")
	end
	local sourceSize = buffer.len(source)
	local sourceOffset = clampInteger(sourceOffsetRaw, 0, sourceSize)
	local byteCount = if typeof(byteCountRaw) == "number" then clampInteger(byteCountRaw, 0, sourceSize - sourceOffset) else sourceSize - sourceOffset
	ensureCapacity(self, byteCount)
	buffer.copy(self.buffer, self.length, source, sourceOffset, byteCount)
	self.length += byteCount
end

function Writer.writeString16(self: Writer, valueRaw: any)
	local value = if typeof(valueRaw) == "string" then valueRaw else tostring(valueRaw)
	local byteLength = #value
	if byteLength > 65535 then
		error("Writer.writeString16 exceeds UInt16 length")
	end
	self:writeUInt16(byteLength)
	ensureCapacity(self, byteLength)
	buffer.writestring(self.buffer, self.length, value)
	self.length += byteLength
end

function Writer.writeString32(self: Writer, valueRaw: any)
	local value = if typeof(valueRaw) == "string" then valueRaw else tostring(valueRaw)
	local byteLength = #value
	self:writeUInt32(byteLength)
	ensureCapacity(self, byteLength)
	buffer.writestring(self.buffer, self.length, value)
	self.length += byteLength
end

function Writer.toBuffer(self: Writer): (buffer, number)
	local out = buffer.create(self.length)
	buffer.copy(out, 0, self.buffer, 0, self.length)
	return out, self.length
end

function Writer.reset(self: Writer)
	self.length = 0
end

function BinaryStreaming.createReader(payload: buffer, payloadSizeRaw: any): Reader
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.createReader expects a buffer")
	end
	local totalSize = buffer.len(payload)
	local payloadSize = if typeof(payloadSizeRaw) == "number" then clampInteger(payloadSizeRaw, 0, totalSize) else totalSize
	local self = setmetatable({
		buffer = payload,
		length = payloadSize,
		cursor = 0,
	}, Reader)
	return self
end

local function assertCanRead(self: Reader, byteCount: number)
	if self.cursor + byteCount > self.length then
		error("BinaryStreaming reader overflow")
	end
end

function Reader.readUInt8(self: Reader): number
	assertCanRead(self, 1)
	local value = buffer.readu8(self.buffer, self.cursor)
	self.cursor += 1
	return value
end

function Reader.readUInt16(self: Reader): number
	assertCanRead(self, 2)
	local value = buffer.readu16(self.buffer, self.cursor)
	self.cursor += 2
	return value
end

function Reader.readUInt32(self: Reader): number
	assertCanRead(self, 4)
	local value = buffer.readu32(self.buffer, self.cursor)
	self.cursor += 4
	return value
end

function Reader.readBitmask(self: Reader, bitsRaw: any): number
	local bits = clampInteger(bitsRaw, 1, 32)
	if bits <= 8 then
		return self:readUInt8()
	end
	if bits <= 16 then
		return self:readUInt16()
	end
	return self:readUInt32()
end

function Reader.readBytes(self: Reader, byteCountRaw: any): buffer
	local byteCount = clampInteger(byteCountRaw, 0, self.length - self.cursor)
	assertCanRead(self, byteCount)
	local out = buffer.create(byteCount)
	buffer.copy(out, 0, self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return out
end

function Reader.readString16(self: Reader): string
	local byteCount = self:readUInt16()
	assertCanRead(self, byteCount)
	local value = buffer.readstring(self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return value
end

function Reader.readString32(self: Reader): string
	local byteCount = self:readUInt32()
	assertCanRead(self, byteCount)
	local value = buffer.readstring(self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return value
end

function Reader.remaining(self: Reader): number
	return self.length - self.cursor
end

function BinaryStreaming.framePacket(payload: buffer, payloadSizeRaw: any, options: FrameOptions?): buffer
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.framePacket expects a payload buffer")
	end

	local payloadSize = if typeof(payloadSizeRaw) == "number" then clampInteger(payloadSizeRaw, 0, buffer.len(payload)) else buffer.len(payload)
	local version = clampInteger(if options then options.version else nil, 0, 255)
	if version == 0 then
		version = DEFAULT_VERSION
	end
	local withChecksum = if options then options.checksum == true else false
	local withRle = if options then options.enableRle == true else false

	local encodedPayload = payload
	local encodedPayloadSize = payloadSize
	local rleUsed = false
	if withRle then
		encodedPayload, encodedPayloadSize, rleUsed = runLengthEncode(payload, payloadSize)
	end

	local flags = 0
	if withChecksum then
		flags = bit32.bor(flags, FLAG_CHECKSUM)
	end
	if rleUsed then
		flags = bit32.bor(flags, FLAG_RLE)
	end

	local writer = BinaryStreaming.createWriter(encodedPayloadSize + 16)
	writer:writeUInt16(DEFAULT_MAGIC)
	writer:writeUInt8(version)
	writer:writeUInt8(flags)
	writer:writeUInt32(encodedPayloadSize)
	writer:writeBytes(encodedPayload, 0, encodedPayloadSize)
	if withChecksum then
		writer:writeUInt32(fnv1aChecksum(encodedPayload, encodedPayloadSize))
	end
	local framed = writer:toBuffer()
	return framed
end

function BinaryStreaming.parseFrame(packet: buffer, options: FrameOptions?): ParsedFrame
	if typeof(packet) ~= "buffer" then
		error("BinaryStreaming.parseFrame expects a packet buffer")
	end

	local reader = BinaryStreaming.createReader(packet)
	local magic = reader:readUInt16()
	if magic ~= DEFAULT_MAGIC then
		error("Malformed frame: magic mismatch")
	end

	local version = reader:readUInt8()
	local flags = reader:readUInt8()
	local payloadSize = reader:readUInt32()

	local maxPayloadBytes = clampInteger(if options then options.maxPayloadBytes else nil, 1, 32 * 1024 * 1024)
	if maxPayloadBytes <= 1 then
		maxPayloadBytes = DEFAULT_MAX_PAYLOAD
	end
	if payloadSize > maxPayloadBytes then
		error("Malformed frame: payload exceeds configured cap")
	end

	if reader:remaining() < payloadSize then
		error("Malformed frame: payload truncated")
	end
	local payload = reader:readBytes(payloadSize)

	local hasChecksum = bit32.band(flags, FLAG_CHECKSUM) ~= 0
	local checksumValue: number? = nil
	if hasChecksum then
		if reader:remaining() < 4 then
			error("Malformed frame: missing checksum")
		end
		checksumValue = reader:readUInt32()
		local computed = fnv1aChecksum(payload, payloadSize)
		if checksumValue ~= computed then
			error("Malformed frame: checksum mismatch")
		end
	end

	if reader:remaining() ~= 0 then
		error("Malformed frame: trailing bytes")
	end

	local isRle = bit32.band(flags, FLAG_RLE) ~= 0
	if isRle then
		payload, payloadSize = runLengthDecode(payload, payloadSize)
	end

	return {
		version = version,
		flags = flags,
		payload = payload,
		payloadSize = payloadSize,
		checksum = checksumValue,
	}
end

function BinaryStreaming.validateFrame(packet: buffer, options: FrameOptions?): (boolean, string?)
	local ok, err = pcall(function()
		BinaryStreaming.parseFrame(packet, options)
	end)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

function BinaryStreaming.safeDispatch(sendFn: (packet: buffer) -> (), packet: buffer, options: FrameOptions?): (boolean, string?)
	local ok, err = BinaryStreaming.validateFrame(packet, options)
	if not ok then
		return false, err
	end
	sendFn(packet)
	return true, nil
end

function BinaryStreaming.createChunkBatch(payload: buffer, payloadSizeRaw: any, options: ChunkOptions?): { buffer }
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.createChunkBatch expects a payload buffer")
	end

	local payloadSize = if typeof(payloadSizeRaw) == "number" then clampInteger(payloadSizeRaw, 0, buffer.len(payload)) else buffer.len(payload)
	local chunkSize = clampInteger(if options then options.chunkSize else nil, 64, 65535)
	if chunkSize == 64 then
		chunkSize = DEFAULT_CHUNK_SIZE
	end

	local chunkCount = math.max(1, math.ceil(payloadSize / chunkSize))
	local batchId = if options and options.batchId ~= nil then clampInteger(options.batchId, 1, 4294967295) else Codec.stableHash({ payloadSize = payloadSize, chunkCount = chunkCount })
	local frames = Sift.Array.create(chunkCount)

	for chunkIndex = 0, chunkCount - 1 do
		local startOffset = chunkIndex * chunkSize
		local remaining = payloadSize - startOffset
		local take = math.min(chunkSize, remaining)

		local writer = BinaryStreaming.createWriter(take + 16)
		writer:writeUInt32(batchId)
		writer:writeUInt16(chunkIndex)
		writer:writeUInt16(chunkCount)
		writer:writeUInt32(payloadSize)
		writer:writeBytes(payload, startOffset, take)
		local chunkPayload, chunkPayloadSize = writer:toBuffer()

		local framed = BinaryStreaming.framePacket(chunkPayload, chunkPayloadSize, {
			version = if options then options.version else nil,
			checksum = if options then options.checksum else nil,
			enableRle = if options then options.enableRle else nil,
		})
		frames[chunkIndex + 1] = framed
	end

	return frames
end

function BinaryStreaming.createChunkAssembler(maxPendingRaw: any)
	local maxPending = clampInteger(maxPendingRaw, 1, 512)
	local state = {
		pending = {} :: { [number]: any },
		pendingOrder = {} :: { number },
		maxPending = maxPending,
	}

	local assembler = {}

	function assembler.push(packet: buffer, options: FrameOptions?): AssemblerResult
		local frame
		local ok, err = pcall(function()
			frame = BinaryStreaming.parseFrame(packet, options)
		end)
		if not ok then
			return {
				completed = false,
				error = tostring(err),
			}
		end

		local payloadFrame = frame :: ParsedFrame
		local reader = BinaryStreaming.createReader(payloadFrame.payload, payloadFrame.payloadSize)
		if reader:remaining() < 12 then
			return {
				completed = false,
				error = "Chunk payload header is truncated",
			}
		end

		local batchId = reader:readUInt32()
		local chunkIndex = reader:readUInt16()
		local chunkCount = reader:readUInt16()
		local fullPayloadSize = reader:readUInt32()
		if chunkCount <= 0 then
			return {
				completed = false,
				error = "Chunk count must be positive",
			}
		end
		if chunkIndex >= chunkCount then
			return {
				completed = false,
				error = "Chunk index out of range",
			}
		end

		local chunkPayloadSize = reader:remaining()
		local chunkPayload = reader:readBytes(chunkPayloadSize)

		local batch = state.pending[batchId]
		if batch == nil then
			if #state.pendingOrder >= state.maxPending then
				table.sort(state.pendingOrder)
				local oldestBatchId = state.pendingOrder[1]
				if oldestBatchId ~= nil then
					state.pending[oldestBatchId] = nil
					table.remove(state.pendingOrder, 1)
				end
			end

			batch = {
				chunkCount = chunkCount,
				fullPayloadSize = fullPayloadSize,
				parts = Sift.Array.create(chunkCount),
				received = 0,
			}
			state.pending[batchId] = batch
			state.pendingOrder[#state.pendingOrder + 1] = batchId
		end

		if batch.chunkCount ~= chunkCount or batch.fullPayloadSize ~= fullPayloadSize then
			state.pending[batchId] = nil
			return {
				completed = false,
				error = "Conflicting chunk batch metadata",
			}
		end

		if batch.parts[chunkIndex + 1] == nil then
			batch.received += 1
		end
		batch.parts[chunkIndex + 1] = {
			payload = chunkPayload,
			size = chunkPayloadSize,
		}

		if batch.received < batch.chunkCount then
			return {
				completed = false,
				batchId = batchId,
			}
		end

		local merged = buffer.create(batch.fullPayloadSize)
		local cursor = 0
		for index = 1, batch.chunkCount do
			local part = batch.parts[index]
			if part == nil then
				return {
					completed = false,
					error = "Chunk batch is incomplete",
				}
			end
			buffer.copy(merged, cursor, part.payload, 0, part.size)
			cursor += part.size
		end

		state.pending[batchId] = nil
		for index = #state.pendingOrder, 1, -1 do
			if state.pendingOrder[index] == batchId then
				table.remove(state.pendingOrder, index)
				break
			end
		end

		return {
			completed = true,
			batchId = batchId,
			payload = merged,
			payloadSize = cursor,
		}
	end

	function assembler.clear(batchIdRaw: any)
		local batchId = clampInteger(batchIdRaw, 1, 4294967295)
		state.pending[batchId] = nil
		for index = #state.pendingOrder, 1, -1 do
			if state.pendingOrder[index] == batchId then
				table.remove(state.pendingOrder, index)
				break
			end
		end
	end

	function assembler.debugPending(): { number }
		local copy = Sift.Dictionary.copy(state.pendingOrder)
		sortDeterministic(copy :: any)
		return copy
	end

	return assembler
end

function BinaryStreaming.encodeMutationDelta(previousState: any, nextState: any, options: FrameOptions?): buffer
	local delta = Codec.createDelta(previousState, nextState)
	if delta == nil then
		delta = {
			__delta = true,
			changes = {},
			removals = {},
		}
	end
	local serialized = Codec.serializeDeterministic(delta)
	local payload, payloadSize = createStringBuffer(serialized)
	return BinaryStreaming.framePacket(payload, payloadSize, options)
end

function BinaryStreaming.decodeMutationDelta(packet: buffer, previousState: any, options: FrameOptions?): any
	local frame = BinaryStreaming.parseFrame(packet, options)
	local serialized = toStringFromBuffer(frame.payload, frame.payloadSize)
	local delta = Codec.deserializeDeterministic(serialized)
	return Codec.applyDelta(previousState, delta)
end

return BinaryStreaming
