--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Codec = require(script.Parent.Codec)
local BinaryStreaming = require(script.Parent.BinaryStreaming)

local WorldMutationQueue = {}
WorldMutationQueue.__index = WorldMutationQueue

export type TileMutation = {
	x: number,
	y: number,
	z: number,
	tileId: any,
	previousTileId: any?,
	flags: number?,
	metadata: { [string]: any }?,
}

export type ChunkMutationBatch = {
	key: string,
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	mutations: { TileMutation },
}

export type FlushBatch = {
	sequence: number,
	timestamp: number,
	totalMutations: number,
	chunks: { ChunkMutationBatch },
}

export type QueueConfig = {
	chunkSize: number?,
	flushInterval: number?,
	maxMutationsPerFlush: number?,
}

export type WorldMutationQueue = typeof(setmetatable({} :: any, WorldMutationQueue))

local function clampInteger(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then math.floor(valueRaw) else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function clampPositiveNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function key3(x: number, y: number, z: number): string
	return string.format("%d|%d|%d", x, y, z)
end

local function sortChunkKeys(a: string, b: string): boolean
	return a < b
end

local function worldToChunk(value: number, chunkSize: number): number
	return math.floor(value / chunkSize)
end

local function sanitizeMutation(raw: any): TileMutation?
	if typeof(raw) ~= "table" then
		return nil
	end
	if typeof(raw.x) ~= "number" or typeof(raw.y) ~= "number" or typeof(raw.z) ~= "number" then
		return nil
	end
	if raw.tileId == nil then
		return nil
	end
	local metadata: { [string]: any }? = nil
	if typeof(raw.metadata) == "table" then
		metadata = Sift.Dictionary.copy(raw.metadata)
	end
	return {
		x = math.floor(raw.x),
		y = math.floor(raw.y),
		z = math.floor(raw.z),
		tileId = raw.tileId,
		previousTileId = raw.previousTileId,
		flags = if typeof(raw.flags) == "number" then math.floor(raw.flags) else nil,
		metadata = metadata,
	}
end

local function rebuildLookup(bucket: any)
	local lookup = bucket.lookup
	table.clear(lookup)
	for index = 1, #bucket.mutations do
		local mutation = bucket.mutations[index]
		lookup[key3(mutation.x, mutation.y, mutation.z)] = index
	end
end

function WorldMutationQueue.new(configRaw: QueueConfig?): WorldMutationQueue
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local chunkSize = clampInteger(config.chunkSize, 32, 1, 1024)
	local flushInterval = clampPositiveNumber(config.flushInterval, 0.1, 0.005, 60)
	local maxMutationsPerFlush = clampInteger(config.maxMutationsPerFlush, 4096, 1, 1000000)

	local self = setmetatable({
		chunkSize = chunkSize,
		flushInterval = flushInterval,
		maxMutationsPerFlush = maxMutationsPerFlush,
		elapsed = 0,
		clock = 0,
		pendingCount = 0,
		sequence = 0,
		chunkBuckets = {} :: { [string]: any },
		chunkKeys = {} :: { string },
	}, WorldMutationQueue)
	return self
end

function WorldMutationQueue._getOrCreateBucket(self: WorldMutationQueue, chunkX: number, chunkY: number, chunkZ: number)
	local chunkKey = key3(chunkX, chunkY, chunkZ)
	local bucket = self.chunkBuckets[chunkKey]
	if bucket ~= nil then
		return bucket
	end
	bucket = {
		key = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		chunkZ = chunkZ,
		mutations = {},
		lookup = {},
	}
	self.chunkBuckets[chunkKey] = bucket
	self.chunkKeys[#self.chunkKeys + 1] = chunkKey
	return bucket
end

function WorldMutationQueue.enqueue(self: WorldMutationQueue, mutationRaw: any): boolean
	local mutation = sanitizeMutation(mutationRaw)
	if mutation == nil then
		return false
	end

	local chunkX = worldToChunk(mutation.x, self.chunkSize)
	local chunkY = worldToChunk(mutation.y, self.chunkSize)
	local chunkZ = worldToChunk(mutation.z, self.chunkSize)
	local bucket = self:_getOrCreateBucket(chunkX, chunkY, chunkZ)
	local coordKey = key3(mutation.x, mutation.y, mutation.z)
	local existingIndex = bucket.lookup[coordKey]
	if existingIndex ~= nil then
		bucket.mutations[existingIndex] = mutation
		return true
	end

	bucket.mutations[#bucket.mutations + 1] = mutation
	bucket.lookup[coordKey] = #bucket.mutations
	self.pendingCount += 1
	return true
end

function WorldMutationQueue.enqueueBatch(self: WorldMutationQueue, listRaw: any): number
	if typeof(listRaw) ~= "table" then
		return 0
	end
	local accepted = 0
	for _, mutation in listRaw do
		if self:enqueue(mutation) then
			accepted += 1
		end
	end
	return accepted
end

function WorldMutationQueue.setFlushInterval(self: WorldMutationQueue, secondsRaw: any)
	self.flushInterval = clampPositiveNumber(secondsRaw, self.flushInterval, 0.005, 60)
end

function WorldMutationQueue.setMaxMutationsPerFlush(self: WorldMutationQueue, countRaw: any)
	self.maxMutationsPerFlush = clampInteger(countRaw, self.maxMutationsPerFlush, 1, 1000000)
end

function WorldMutationQueue.getPendingCount(self: WorldMutationQueue): number
	return self.pendingCount
end

function WorldMutationQueue._drainBucket(self: WorldMutationQueue, bucket: any, remainingBudget: number): ChunkMutationBatch?
	local mutationCount = #bucket.mutations
	if mutationCount <= 0 then
		return nil
	end

	if mutationCount <= remainingBudget then
		local out = {
			key = bucket.key,
			chunkX = bucket.chunkX,
			chunkY = bucket.chunkY,
			chunkZ = bucket.chunkZ,
			mutations = bucket.mutations,
		} :: ChunkMutationBatch
		self.pendingCount -= mutationCount
		bucket.mutations = {}
		table.clear(bucket.lookup)
		return out
	end

	if remainingBudget <= 0 then
		return nil
	end

	local outMutations = Sift.Array.create(remainingBudget)
	for index = 1, remainingBudget do
		outMutations[index] = bucket.mutations[index]
	end

	for index = 1, mutationCount - remainingBudget do
		bucket.mutations[index] = bucket.mutations[index + remainingBudget]
	end
	for index = mutationCount, mutationCount - remainingBudget + 1, -1 do
		bucket.mutations[index] = nil
	end

	rebuildLookup(bucket)
	self.pendingCount -= remainingBudget

	return {
		key = bucket.key,
		chunkX = bucket.chunkX,
		chunkY = bucket.chunkY,
		chunkZ = bucket.chunkZ,
		mutations = outMutations,
	} :: ChunkMutationBatch
end

function WorldMutationQueue.flush(self: WorldMutationQueue, maxMutationsRaw: any?, onFlush: ((batch: FlushBatch) -> ())?): FlushBatch?
	if self.pendingCount <= 0 then
		return nil
	end

	local maxMutations = if maxMutationsRaw ~= nil then clampInteger(maxMutationsRaw, self.maxMutationsPerFlush, 1, 1000000) else self.maxMutationsPerFlush
	if maxMutations <= 0 then
		return nil
	end

	table.sort(self.chunkKeys, sortChunkKeys)
	local chunks = {}
	local emitted = 0

	for index = 1, #self.chunkKeys do
		if emitted >= maxMutations then
			break
		end
		local chunkKey = self.chunkKeys[index]
		local bucket = self.chunkBuckets[chunkKey]
		if bucket == nil then
			continue
		end
		local remaining = maxMutations - emitted
		local chunkBatch = self:_drainBucket(bucket, remaining)
		if chunkBatch ~= nil then
			emitted += #chunkBatch.mutations
			chunks[#chunks + 1] = chunkBatch
		end
	end

	for index = #self.chunkKeys, 1, -1 do
		local chunkKey = self.chunkKeys[index]
		local bucket = self.chunkBuckets[chunkKey]
		if bucket == nil then
			table.remove(self.chunkKeys, index)
		elseif #bucket.mutations == 0 then
			self.chunkBuckets[chunkKey] = nil
			table.remove(self.chunkKeys, index)
		end
	end

	if emitted <= 0 then
		return nil
	end

	self.sequence += 1
	local batch = {
		sequence = self.sequence,
		timestamp = self.clock,
		totalMutations = emitted,
		chunks = chunks,
	} :: FlushBatch

	if onFlush ~= nil then
		onFlush(batch)
	end
	return batch
end

function WorldMutationQueue.update(self: WorldMutationQueue, dtRaw: any, onFlush: ((batch: FlushBatch) -> ())?): { FlushBatch }
	local dt = if typeof(dtRaw) == "number" and dtRaw > 0 then dtRaw else 0
	if dt <= 0 then
		return {}
	end
	self.clock += dt
	self.elapsed += dt
	if self.pendingCount <= 0 then
		return {}
	end
	if self.elapsed < self.flushInterval then
		return {}
	end

	local flushed = {}
	while self.elapsed >= self.flushInterval and self.pendingCount > 0 do
		local batch = self:flush(nil, onFlush)
		if batch == nil then
			break
		end
		flushed[#flushed + 1] = batch
		self.elapsed -= self.flushInterval
	end
	return flushed
end

function WorldMutationQueue.encodeBatch(self: WorldMutationQueue, batch: FlushBatch, compressRaw: any?): string
	local shouldCompress = compressRaw ~= false
	local payload = {
		sequence = batch.sequence,
		timestamp = batch.timestamp,
		totalMutations = batch.totalMutations,
		chunks = batch.chunks,
	}
	if shouldCompress then
		return Codec.serializeCompressed(payload)
	end
	return Codec.serializeDeterministic(payload)
end

function WorldMutationQueue.decodeBatch(self: WorldMutationQueue, payloadRaw: any, compressedRaw: any?): FlushBatch?
	if typeof(payloadRaw) ~= "string" then
		return nil
	end
	local compressed = compressedRaw ~= false
	local decoded = if compressed then Codec.deserializeCompressed(payloadRaw) else Codec.deserializeDeterministic(payloadRaw)
	if typeof(decoded) ~= "table" then
		return nil
	end
	return decoded :: FlushBatch
end

function WorldMutationQueue.encodeBatchFrame(self: WorldMutationQueue, batch: FlushBatch, options: any?): buffer
	local serialized = self:encodeBatch(batch, true)
	local payload = buffer.create(#serialized)
	buffer.writestring(payload, 0, serialized)
	return BinaryStreaming.framePacket(payload, #serialized, options)
end

function WorldMutationQueue.destroy(self: WorldMutationQueue)
	table.clear(self.chunkBuckets)
	table.clear(self.chunkKeys)
	self.pendingCount = 0
	self.elapsed = 0
end

return WorldMutationQueue
