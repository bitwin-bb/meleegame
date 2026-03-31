--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local CoreObjectPool = require(ReplicatedStorage.Shared.Modules.Core.ObjectPool)

local Cache = {}
Cache.__index = Cache

export type VectorBuffer = {
	x: { number },
	y: { number },
	z: { number },
	size: number,
}

export type ObjectPool<T> = {
	acquire: (self: ObjectPool<T>) -> T,
	release: (self: ObjectPool<T>, value: T) -> (),
	destroy: (self: ObjectPool<T>) -> (),
	available: number,
	inUse: number,
}

export type Cache = typeof(setmetatable({} :: any, Cache))

local function clearDenseArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function ensureNumberArrayLength(array: { number }, length: number, fillValue: number)
	for index = 1, length do
		if array[index] == nil then
			array[index] = fillValue
		end
	end
	for index = #array, length + 1, -1 do
		array[index] = nil
	end
end

function Cache.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		tablePool = {} :: { { [any]: any } },
		numberArrayPool = {} :: { { number } },
		vectorBufferPool = {} :: { VectorBuffer },
		maxTablePoolSize = math.max(8, math.floor((config :: any).tablePoolSize or 256)),
		maxArrayPoolSize = math.max(8, math.floor((config :: any).arrayPoolSize or 256)),
		maxVectorPoolSize = math.max(8, math.floor((config :: any).vectorPoolSize or 128)),
		totalTableAcquires = 0,
		totalArrayAcquires = 0,
		totalVectorAcquires = 0,
	}, Cache)
	return self
end

function Cache.acquireTable(self: Cache): { [any]: any }
	self.totalTableAcquires += 1
	local count = #self.tablePool
	if count <= 0 then
		return {}
	end
	local value = self.tablePool[count]
	self.tablePool[count] = nil
	return value
end

function Cache.releaseTable(self: Cache, valueRaw: any)
	if typeof(valueRaw) ~= "table" then
		return
	end
	if #self.tablePool >= self.maxTablePoolSize then
		return
	end
	local value = valueRaw :: { [any]: any }
	table.clear(value)
	self.tablePool[#self.tablePool + 1] = value
end

function Cache.acquireNumberArray(self: Cache, lengthRaw: any, fillValueRaw: any): { number }
	self.totalArrayAcquires += 1
	local length = math.max(0, math.floor(if typeof(lengthRaw) == "number" then lengthRaw else 0))
	local fillValue = if typeof(fillValueRaw) == "number" then fillValueRaw else 0
	local count = #self.numberArrayPool
	if count <= 0 then
		local created = Sift.Array.create(length, fillValue)
		return created
	end
	local array = self.numberArrayPool[count]
	self.numberArrayPool[count] = nil
	ensureNumberArrayLength(array, length, fillValue)
	return array
end

function Cache.releaseNumberArray(self: Cache, arrayRaw: any)
	if typeof(arrayRaw) ~= "table" then
		return
	end
	if #self.numberArrayPool >= self.maxArrayPoolSize then
		return
	end
	local array = arrayRaw :: { number }
	clearDenseArray(array)
	self.numberArrayPool[#self.numberArrayPool + 1] = array
end

function Cache.acquireVectorBuffer(self: Cache, capacityRaw: any): VectorBuffer
	self.totalVectorAcquires += 1
	local capacity = math.max(0, math.floor(if typeof(capacityRaw) == "number" then capacityRaw else 0))
	local count = #self.vectorBufferPool
	if count > 0 then
		local buffer = self.vectorBufferPool[count]
		self.vectorBufferPool[count] = nil
		buffer.size = capacity
		ensureNumberArrayLength(buffer.x, capacity, 0)
		ensureNumberArrayLength(buffer.y, capacity, 0)
		ensureNumberArrayLength(buffer.z, capacity, 0)
		return buffer
	end

	return {
		x = Sift.Array.create(capacity, 0),
		y = Sift.Array.create(capacity, 0),
		z = Sift.Array.create(capacity, 0),
		size = capacity,
	}
end

function Cache.releaseVectorBuffer(self: Cache, bufferRaw: any)
	if typeof(bufferRaw) ~= "table" then
		return
	end
	if #self.vectorBufferPool >= self.maxVectorPoolSize then
		return
	end

	local buffer = bufferRaw :: VectorBuffer
	buffer.size = 0
	clearDenseArray(buffer.x)
	clearDenseArray(buffer.y)
	clearDenseArray(buffer.z)
	self.vectorBufferPool[#self.vectorBufferPool + 1] = buffer
end

function Cache.createObjectPool<T>(
	self: Cache,
	factory: () -> T,
	resetter: ((T) -> ())?,
	maxSizeRaw: any
): ObjectPool<T>
	local maxSize = math.max(1, math.floor(if typeof(maxSizeRaw) == "number" then maxSizeRaw else 128))
	local runtimePool = (CoreObjectPool :: any).new(factory, {
		expandBy = 1,
		maxAvailable = maxSize,
		reset = resetter,
	})

	local pool = {} :: ObjectPool<T>
	pool.available = 0
	pool.inUse = 0

	local function syncStats(selfPool: ObjectPool<T>)
		if typeof((runtimePool :: any).getStats) ~= "function" then
			return
		end
		local stats = (runtimePool :: any):getStats()
		if typeof(stats) ~= "table" then
			return
		end
		selfPool.available = if typeof(stats.available) == "number" then stats.available else selfPool.available
		selfPool.inUse = if typeof(stats.inUse) == "number" then stats.inUse else selfPool.inUse
	end

	function pool.acquire(selfPool: ObjectPool<T>): T
		local value = (runtimePool :: any):acquire() :: T
		syncStats(selfPool)
		return value
	end

	function pool.release(selfPool: ObjectPool<T>, value: T)
		local runtimePoolAny = runtimePool :: any
		runtimePoolAny:release(value)
		syncStats(selfPool)
	end

	function pool.destroy(selfPool: ObjectPool<T>)
		local runtimePoolAny = runtimePool :: any
		runtimePoolAny:destroy()
		selfPool.available = 0
		selfPool.inUse = 0
	end

	syncStats(pool)
	return pool
end

function Cache.getStats(self: Cache): { [string]: number }
	return {
		tablePool = #self.tablePool,
		numberArrayPool = #self.numberArrayPool,
		vectorBufferPool = #self.vectorBufferPool,
		tableAcquires = self.totalTableAcquires,
		arrayAcquires = self.totalArrayAcquires,
		vectorAcquires = self.totalVectorAcquires,
	}
end

function Cache.destroy(self: Cache)
	table.clear(self.tablePool)
	table.clear(self.numberArrayPool)
	table.clear(self.vectorBufferPool)
	self.totalTableAcquires = 0
	self.totalArrayAcquires = 0
	self.totalVectorAcquires = 0
end

return Cache
