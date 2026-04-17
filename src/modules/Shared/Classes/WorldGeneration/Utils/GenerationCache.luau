--!strict

local Cache = {}
Cache.__index = Cache

export type CacheConfig = {
	maxPoolSize: number?,
	maxCachedChunkData: number?,
	createPart: (() -> BasePart)?,
}

type ChunkDataLike = {
	lastAccessedAt: number,
	[string]: any,
}

local DEFAULT_MAX_POOL_SIZE = 9000
local DEFAULT_MAX_CACHED_CHUNK_DATA = 320

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), minimum, maximum)
end

function Cache.New(configRaw: CacheConfig?): Cache
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local createPartCallback = if typeof((config :: any).createPart) == "function"
		then (config :: any).createPart :: () -> BasePart
		else nil

	local self = setmetatable({
		maxPoolSize = sanitizeInteger((config :: any).maxPoolSize, 16, 200000, DEFAULT_MAX_POOL_SIZE),
		maxCachedChunkData = sanitizeInteger(
			(config :: any).maxCachedChunkData,
			16,
			4096,
			DEFAULT_MAX_CACHED_CHUNK_DATA
		),
		createPart = createPartCallback,
		partPool = {} :: { BasePart },
		chunkDataCache = {} :: { [string]: ChunkDataLike },
		cachedChunkCount = 0,
	}, Cache)

	return self
end

function Cache.AcquirePart(self: Cache): BasePart
	local count = #self.partPool
	if count > 0 then
		local pooledPart = self.partPool[count]
		self.partPool[count] = nil
		return pooledPart
	end

	if self.createPart then
		return self.createPart()
	end

	return Instance.new("Part")
end

function Cache.ReleasePart(self: Cache, part: BasePart)
	part.Parent = nil
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false

	if #self.partPool >= self.maxPoolSize then
		part:Destroy()
		return
	end

	table.insert(self.partPool, part)
end

function Cache.GetChunkData(self: Cache, chunkKey: string): ChunkDataLike?
	local cached = self.chunkDataCache[chunkKey]
	if cached == nil then
		return nil
	end

	cached.lastAccessedAt = os.clock()
	return cached
end

function Cache.SetChunkData(self: Cache, chunkKey: string, chunkData: ChunkDataLike)
	if self.chunkDataCache[chunkKey] == nil then
		self.cachedChunkCount += 1
	end
	chunkData.lastAccessedAt = os.clock()
	self.chunkDataCache[chunkKey] = chunkData
end

function Cache.RemoveChunkData(self: Cache, chunkKey: string)
	if self.chunkDataCache[chunkKey] == nil then
		return
	end
	self.chunkDataCache[chunkKey] = nil
	self.cachedChunkCount = math.max(0, self.cachedChunkCount - 1)
end

function Cache.PruneChunkData(self: Cache, shouldKeep: ((chunkKey: string, chunkData: ChunkDataLike) -> boolean)?)
	while self.cachedChunkCount > self.maxCachedChunkData do
		local evictionKey: string? = nil
		local oldestAccess = math.huge

		for chunkKey, chunkData in self.chunkDataCache do
			if shouldKeep and shouldKeep(chunkKey, chunkData) then
				continue
			end

			if chunkData.lastAccessedAt < oldestAccess then
				oldestAccess = chunkData.lastAccessedAt
				evictionKey = chunkKey
			end
		end

		if evictionKey == nil then
			break
		end

		self:removeChunkData(evictionKey)
	end
end

function Cache.GetPooledPartCount(self: Cache): number
	return #self.partPool
end

function Cache.GetCachedChunkCount(self: Cache): number
	return self.cachedChunkCount
end

function Cache.ClearChunkData(self: Cache)
	table.clear(self.chunkDataCache)
	self.cachedChunkCount = 0
end

function Cache.Destroy(self: Cache)
	for _, part in self.partPool do
		part:Destroy()
	end
	table.clear(self.partPool)
	self:clearChunkData()
end

export type Cache = typeof(setmetatable(
	{} :: {
		maxPoolSize: number,
		maxCachedChunkData: number,
		createPart: (() -> BasePart)?,
		partPool: { BasePart },
		chunkDataCache: { [string]: ChunkDataLike },
		cachedChunkCount: number,
	},
	Cache
))

Cache.new = Cache.New
Cache.acquirePart = Cache.AcquirePart
Cache.releasePart = Cache.ReleasePart
Cache.getChunkData = Cache.GetChunkData
Cache.setChunkData = Cache.SetChunkData
Cache.removeChunkData = Cache.RemoveChunkData
Cache.pruneChunkData = Cache.PruneChunkData
Cache.getPooledPartCount = Cache.GetPooledPartCount
Cache.getCachedChunkCount = Cache.GetCachedChunkCount
Cache.clearChunkData = Cache.ClearChunkData
Cache.destroy = Cache.Destroy

return Cache
