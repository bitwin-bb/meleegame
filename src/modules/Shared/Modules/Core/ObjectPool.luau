--!strict

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type Factory<T> = () -> T
export type Resetter<T> = (value: T) -> ()
export type Destroyer<T> = (value: T) -> ()

export type PoolConfig<T> = {
	prewarm: number?,
	expandBy: number?,
	maxAvailable: number?,
	minAvailable: number?,
	reset: Resetter<T>?,
	destroy: Destroyer<T>?,
}

export type ObjectPool<T> = typeof(setmetatable({} :: any, ObjectPool))

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

local function clearDenseArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

function ObjectPool.new<T>(factory: Factory<T>, configRaw: PoolConfig<T>?): ObjectPool<T>
	if typeof(factory) ~= "function" then
		error("ObjectPool.new expects a factory callback")
	end
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local prewarmCount = clampInteger(config.prewarm, 0, 0, 1000000)
	local expandBy = clampInteger(config.expandBy, 8, 1, 100000)
	local maxAvailable = clampInteger(config.maxAvailable, 2048, 1, 10000000)
	local minAvailable = clampInteger(config.minAvailable, 0, 0, maxAvailable)

	local self = setmetatable({
		factory = factory,
		reset = config.reset,
		destroyer = config.destroy,
		expandBy = expandBy,
		maxAvailable = maxAvailable,
		minAvailable = minAvailable,
		available = {} :: { T },
		inUse = {} :: { [T]: true },
		inUseCount = 0,
		totalCreated = 0,
		totalAcquired = 0,
		totalReleased = 0,
		totalDestroyed = 0,
	}, ObjectPool)

	self:prewarm(prewarmCount)
	return self
end

function ObjectPool._create(self: ObjectPool<any>): any
	local value = self.factory()
	self.totalCreated += 1
	return value
end

function ObjectPool.Prewarm(self: ObjectPool<any>, countRaw: any)
	local count = clampInteger(countRaw, 0, 0, self.maxAvailable - #self.available)
	for _ = 1, count do
		self.available[#self.available + 1] = self:_create()
	end
end

function ObjectPool.Acquire(self: ObjectPool<any>): any
	self.totalAcquired += 1
	if #self.available == 0 then
		local createCount = math.max(1, self.expandBy)
		for index = 1, createCount do
			local created = self:_create()
			if index == 1 then
				self.inUse[created] = true
				self.inUseCount += 1
				return created
			end
			if #self.available < self.maxAvailable then
				self.available[#self.available + 1] = created
			else
				if self.destroyer ~= nil then
					self.destroyer(created)
				end
				self.totalDestroyed += 1
			end
		end
	end

	local index = #self.available
	local value = self.available[index]
	self.available[index] = nil
	self.inUse[value] = true
	self.inUseCount += 1
	return value
end

function ObjectPool.Release(self: ObjectPool<any>, value: any)
	if value == nil then
		return
	end
	if self.inUse[value] == nil then
		return
	end

	self.inUse[value] = nil
	if self.inUseCount > 0 then
		self.inUseCount -= 1
	end
	self.totalReleased += 1

	if self.reset ~= nil then
		self.reset(value)
	end

	if #self.available >= self.maxAvailable then
		if self.destroyer ~= nil then
			self.destroyer(value)
		end
		self.totalDestroyed += 1
		return
	end

	self.available[#self.available + 1] = value
end

function ObjectPool.SoftShrink(self: ObjectPool<any>, maxRemovalsRaw: any): number
	local targetAvailable = self.minAvailable
	if #self.available <= targetAvailable then
		return 0
	end

	local maxRemovals = clampInteger(maxRemovalsRaw, #self.available - targetAvailable, 0, #self.available)
	local removed = 0
	while removed < maxRemovals and #self.available > targetAvailable do
		local index = #self.available
		local value = self.available[index]
		self.available[index] = nil
		if self.destroyer ~= nil then
			self.destroyer(value)
		end
		self.totalDestroyed += 1
		removed += 1
	end
	return removed
end

function ObjectPool.Clear(self: ObjectPool<any>, destroyInUseRaw: any?)
	local destroyInUse = destroyInUseRaw == true
	for index = #self.available, 1, -1 do
		local value = self.available[index]
		if self.destroyer ~= nil then
			self.destroyer(value)
		end
		self.totalDestroyed += 1
		self.available[index] = nil
	end

	if destroyInUse then
		for value in self.inUse do
			if self.destroyer ~= nil then
				self.destroyer(value)
			end
			self.totalDestroyed += 1
		end
		table.clear(self.inUse)
		self.inUseCount = 0
	end
end

function ObjectPool.Destroy(self: ObjectPool<any>)
	self:clear(true)
	clearDenseArray(self.available)
	table.clear(self.inUse)
end

function ObjectPool.GetStats(self: ObjectPool<any>): { [string]: number }
	return {
		available = #self.available,
		inUse = self.inUseCount,
		totalCreated = self.totalCreated,
		totalAcquired = self.totalAcquired,
		totalReleased = self.totalReleased,
		totalDestroyed = self.totalDestroyed,
	}
end

ObjectPool.prewarm = ObjectPool.Prewarm
ObjectPool.acquire = ObjectPool.Acquire
ObjectPool.release = ObjectPool.Release
ObjectPool.softShrink = ObjectPool.SoftShrink
ObjectPool.clear = ObjectPool.Clear
ObjectPool.destroy = ObjectPool.Destroy
ObjectPool.getStats = ObjectPool.GetStats

return ObjectPool
