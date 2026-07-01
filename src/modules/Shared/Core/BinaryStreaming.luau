local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Codec = require("Codec")

local BinaryStreaming = {}

local Writer = {}
Writer.__index = Writer

local Reader = {}
Reader.__index = Reader

export type Writer = {
	buffer: buffer,
	capacity: number,
	length: number,
	WriteUInt8: (self: Writer, value: number) -> (),
	WriteUInt16: (self: Writer, value: number) -> (),
	WriteUInt32: (self: Writer, value: number) -> (),
	WriteBitmask: (self: Writer, bitmask: number, bits: number?) -> (),
	WriteBytes: (self: Writer, source: buffer, sourceOffset: number?, byteCount: number?) -> (),
	WriteString16: (self: Writer, value: string) -> (),
	WriteString32: (self: Writer, value: string) -> (),
	ToBuffer: (self: Writer) -> (buffer, number),
	Reset: (self: Writer) -> (),
}

export type Reader = {
	buffer: buffer,
	length: number,
	cursor: number,
	ReadUInt8: (self: Reader) -> number,
	ReadUInt16: (self: Reader) -> number,
	ReadUInt32: (self: Reader) -> number,
	ReadBitmask: (self: Reader, bits: number?) -> number,
	ReadBytes: (self: Reader, byteCount: number) -> buffer,
	ReadString16: (self: Reader) -> string,
	ReadString32: (self: Reader) -> string,
	Remaining: (self: Reader) -> number,
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
		while
			readCursor + runLength < payloadSize
			and runLength < 255
			and buffer.readu8(payload, readCursor + runLength) == byteValue
		do
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

function BinaryStreaming.CreateWriter(initialCapacityRaw: any): Writer
	local initialCapacity = clampInteger(initialCapacityRaw, 64, 16 * 1024 * 1024)
	local self = setmetatable({
		buffer = buffer.create(initialCapacity),
		capacity = initialCapacity,
		length = 0,
	}, Writer)
	return self :: any
end

function Writer.WriteUInt8(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 255)
	ensureCapacity(self, 1)
	buffer.writeu8(self.buffer, self.length, value)
	self.length += 1
end

function Writer.WriteUInt16(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 65535)
	ensureCapacity(self, 2)
	buffer.writeu16(self.buffer, self.length, value)
	self.length += 2
end

function Writer.WriteUInt32(self: Writer, valueRaw: any)
	local value = clampInteger(valueRaw, 0, 4294967295)
	ensureCapacity(self, 4)
	buffer.writeu32(self.buffer, self.length, value)
	self.length += 4
end

function Writer.WriteBitmask(self: Writer, bitmaskRaw: any, bitsRaw: any)
	local bits = clampInteger(bitsRaw, 1, 32)
	local bitmask = clampInteger(bitmaskRaw, 0, 4294967295)
	if bits <= 8 then
		self:WriteUInt8(bitmask)
		return
	end
	if bits <= 16 then
		self:WriteUInt16(bitmask)
		return
	end
	self:WriteUInt32(bitmask)
end

function Writer.WriteBytes(self: Writer, source: buffer, sourceOffsetRaw: any, byteCountRaw: any)
	if typeof(source) ~= "buffer" then
		error("Writer.WriteBytes expects a buffer source")
	end
	local sourceSize = buffer.len(source)
	local sourceOffset = clampInteger(sourceOffsetRaw, 0, sourceSize)
	local byteCount = if typeof(byteCountRaw) == "number"
		then clampInteger(byteCountRaw, 0, sourceSize - sourceOffset)
		else sourceSize - sourceOffset
	ensureCapacity(self, byteCount)
	buffer.copy(self.buffer, self.length, source, sourceOffset, byteCount)
	self.length += byteCount
end

function Writer.WriteString16(self: Writer, valueRaw: any)
	local value = if typeof(valueRaw) == "string" then valueRaw else tostring(valueRaw)
	local byteLength = #value
	if byteLength > 65535 then
		error("Writer.WriteString16 exceeds UInt16 length")
	end
	self:WriteUInt16(byteLength)
	ensureCapacity(self, byteLength)
	buffer.writestring(self.buffer, self.length, value)
	self.length += byteLength
end

function Writer.WriteString32(self: Writer, valueRaw: any)
	local value = if typeof(valueRaw) == "string" then valueRaw else tostring(valueRaw)
	local byteLength = #value
	self:WriteUInt32(byteLength)
	ensureCapacity(self, byteLength)
	buffer.writestring(self.buffer, self.length, value)
	self.length += byteLength
end

function Writer.ToBuffer(self: Writer): (buffer, number)
	local out = buffer.create(self.length)
	buffer.copy(out, 0, self.buffer, 0, self.length)
	return out, self.length
end

function Writer.Reset(self: Writer)
	self.length = 0
end

function BinaryStreaming.CreateReader(payload: buffer, payloadSizeRaw: any): Reader
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.CreateReader expects a buffer")
	end
	local totalSize = buffer.len(payload)
	local payloadSize = if typeof(payloadSizeRaw) == "number"
		then clampInteger(payloadSizeRaw, 0, totalSize)
		else totalSize
	local self = setmetatable({
		buffer = payload,
		length = payloadSize,
		cursor = 0,
	}, Reader)
	return self :: any
end

local function assertCanRead(self: Reader, byteCount: number)
	if self.cursor + byteCount > self.length then
		error("BinaryStreaming reader overflow")
	end
end

function Reader.ReadUInt8(self: Reader): number
	assertCanRead(self, 1)
	local value = buffer.readu8(self.buffer, self.cursor)
	self.cursor += 1
	return value
end

function Reader.ReadUInt16(self: Reader): number
	assertCanRead(self, 2)
	local value = buffer.readu16(self.buffer, self.cursor)
	self.cursor += 2
	return value
end

function Reader.ReadUInt32(self: Reader): number
	assertCanRead(self, 4)
	local value = buffer.readu32(self.buffer, self.cursor)
	self.cursor += 4
	return value
end

function Reader.ReadBitmask(self: Reader, bitsRaw: any): number
	local bits = clampInteger(bitsRaw, 1, 32)
	if bits <= 8 then
		return self:ReadUInt8()
	end
	if bits <= 16 then
		return self:ReadUInt16()
	end
	return self:ReadUInt32()
end

function Reader.ReadBytes(self: Reader, byteCountRaw: any): buffer
	local byteCount = clampInteger(byteCountRaw, 0, self.length - self.cursor)
	assertCanRead(self, byteCount)
	local out = buffer.create(byteCount)
	buffer.copy(out, 0, self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return out
end

function Reader.ReadString16(self: Reader): string
	local byteCount = self:ReadUInt16()
	assertCanRead(self, byteCount)
	local value = buffer.readstring(self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return value
end

function Reader.ReadString32(self: Reader): string
	local byteCount = self:ReadUInt32()
	assertCanRead(self, byteCount)
	local value = buffer.readstring(self.buffer, self.cursor, byteCount)
	self.cursor += byteCount
	return value
end

function Reader.Remaining(self: Reader): number
	return self.length - self.cursor
end

function BinaryStreaming.FramePacket(payload: buffer, payloadSizeRaw: any, options: FrameOptions?): buffer
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.FramePacket expects a payload buffer")
	end

	local payloadSize = if typeof(payloadSizeRaw) == "number"
		then clampInteger(payloadSizeRaw, 0, buffer.len(payload))
		else buffer.len(payload)
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

	local writer = BinaryStreaming.CreateWriter(encodedPayloadSize + 16)
	writer:WriteUInt16(DEFAULT_MAGIC)
	writer:WriteUInt8(version)
	writer:WriteUInt8(flags)
	writer:WriteUInt32(encodedPayloadSize)
	writer:WriteBytes(encodedPayload, 0, encodedPayloadSize)
	if withChecksum then
		writer:WriteUInt32(fnv1aChecksum(encodedPayload, encodedPayloadSize))
	end
	local framed = writer:ToBuffer()
	return framed
end

function BinaryStreaming.ParseFrame(packet: buffer, options: FrameOptions?): ParsedFrame
	if typeof(packet) ~= "buffer" then
		error("BinaryStreaming.ParseFrame expects a packet buffer")
	end

	local reader = BinaryStreaming.CreateReader(packet)
	local magic = reader:ReadUInt16()
	if magic ~= DEFAULT_MAGIC then
		error("Malformed frame: magic mismatch")
	end

	local version = reader:ReadUInt8()
	local flags = reader:ReadUInt8()
	local payloadSize = reader:ReadUInt32()

	local maxPayloadBytes = clampInteger(if options then options.maxPayloadBytes else nil, 1, 32 * 1024 * 1024)
	if maxPayloadBytes <= 1 then
		maxPayloadBytes = DEFAULT_MAX_PAYLOAD
	end
	if payloadSize > maxPayloadBytes then
		error("Malformed frame: payload exceeds configured cap")
	end

	if reader:Remaining() < payloadSize then
		error("Malformed frame: payload truncated")
	end
	local payload = reader:ReadBytes(payloadSize)

	local hasChecksum = bit32.band(flags, FLAG_CHECKSUM) ~= 0
	local checksumValue: number? = nil
	if hasChecksum then
		if reader:Remaining() < 4 then
			error("Malformed frame: missing checksum")
		end
		checksumValue = reader:ReadUInt32()
		local computed = fnv1aChecksum(payload, payloadSize)
		if checksumValue ~= computed then
			error("Malformed frame: checksum mismatch")
		end
	end

	if reader:Remaining() ~= 0 then
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

function BinaryStreaming.ValidateFrame(packet: buffer, options: FrameOptions?): (boolean, string?)
	local ok, err = pcall(function()
		BinaryStreaming.ParseFrame(packet, options)
	end)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

function BinaryStreaming.SafeDispatch(
	sendFn: (packet: buffer) -> (),
	packet: buffer,
	options: FrameOptions?
): (boolean, string?)
	local ok, err = BinaryStreaming.ValidateFrame(packet, options)
	if not ok then
		return false, err
	end
	sendFn(packet)
	return true, nil
end

function BinaryStreaming.CreateChunkBatch(payload: buffer, payloadSizeRaw: any, options: ChunkOptions?): { buffer }
	if typeof(payload) ~= "buffer" then
		error("BinaryStreaming.CreateChunkBatch expects a payload buffer")
	end

	local payloadSize = if typeof(payloadSizeRaw) == "number"
		then clampInteger(payloadSizeRaw, 0, buffer.len(payload))
		else buffer.len(payload)
	local chunkSize = clampInteger(if options then options.chunkSize else nil, 64, 65535)
	if chunkSize == 64 then
		chunkSize = DEFAULT_CHUNK_SIZE
	end

	local chunkCount = math.max(1, math.ceil(payloadSize / chunkSize))
	local batchId = if options and options.batchId ~= nil
		then clampInteger(options.batchId, 1, 4294967295)
		else Codec.StableHash({ payloadSize = payloadSize, chunkCount = chunkCount })
	local frames = Sift.Array.create(chunkCount)

	for chunkIndex = 0, chunkCount - 1 do
		local startOffset = chunkIndex * chunkSize
		local remaining = payloadSize - startOffset
		local take = math.min(chunkSize, remaining)

		local writer = BinaryStreaming.CreateWriter(take + 16)
		writer:WriteUInt32(batchId)
		writer:WriteUInt16(chunkIndex)
		writer:WriteUInt16(chunkCount)
		writer:WriteUInt32(payloadSize)
		writer:WriteBytes(payload, startOffset, take)
		local chunkPayload, chunkPayloadSize = writer:ToBuffer()

		local framed = BinaryStreaming.FramePacket(chunkPayload, chunkPayloadSize, {
			version = if options then options.version else nil,
			checksum = if options then options.checksum else nil,
			enableRle = if options then options.enableRle else nil,
		})
		frames[chunkIndex + 1] = framed
	end

	return frames
end

function BinaryStreaming.CreateChunkAssembler(maxPendingRaw: any)
	local maxPending = clampInteger(maxPendingRaw, 1, 512)
	local state = {
		pending = {} :: { [number]: any },
		pendingOrder = {} :: { number },
		maxPending = maxPending,
	}

	local assembler = {}

	function assembler.Push(packet: buffer, options: FrameOptions?): AssemblerResult
		local frame
		local ok, err = pcall(function()
			frame = BinaryStreaming.ParseFrame(packet, options)
		end)
		if not ok then
			return {
				completed = false,
				error = tostring(err),
			}
		end

		local payloadFrame = frame :: ParsedFrame
		local reader = BinaryStreaming.CreateReader(payloadFrame.payload, payloadFrame.payloadSize)
		if reader:Remaining() < 12 then
			return {
				completed = false,
				error = "Chunk payload header is truncated",
			}
		end

		local batchId = reader:ReadUInt32()
		local chunkIndex = reader:ReadUInt16()
		local chunkCount = reader:ReadUInt16()
		local fullPayloadSize = reader:ReadUInt32()
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

		local chunkPayloadSize = reader:Remaining()
		local chunkPayload = reader:ReadBytes(chunkPayloadSize)

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

	function assembler.Clear(batchIdRaw: any)
		local batchId = clampInteger(batchIdRaw, 1, 4294967295)
		state.pending[batchId] = nil
		for index = #state.pendingOrder, 1, -1 do
			if state.pendingOrder[index] == batchId then
				table.remove(state.pendingOrder, index)
				break
			end
		end
	end

	function assembler.DebugPending(): { number }
		local copy = Sift.Dictionary.copy(state.pendingOrder)
		sortDeterministic(copy :: any)
		return copy
	end
	return assembler
end

function BinaryStreaming.EncodeMutationDelta(previousState: any, nextState: any, options: FrameOptions?): buffer
	local delta = Codec.CreateDelta(previousState, nextState)
	if delta == nil then
		delta = {
			__delta = true,
			changes = {},
			removals = {},
		}
	end
	local serialized = Codec.SerializeDeterministic(delta)
	local payload, payloadSize = createStringBuffer(serialized)
	return BinaryStreaming.FramePacket(payload, payloadSize, options)
end

function BinaryStreaming.DecodeMutationDelta(packet: buffer, previousState: any, options: FrameOptions?): any
	local frame = BinaryStreaming.ParseFrame(packet, options)
	local serialized = toStringFromBuffer(frame.payload, frame.payloadSize)
	local delta = Codec.DeserializeDeterministic(serialized)
	return Codec.ApplyDelta(previousState, delta)
end
return BinaryStreaming
