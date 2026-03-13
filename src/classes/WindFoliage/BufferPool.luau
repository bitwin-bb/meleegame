--!strict

local BufferPool = {}
BufferPool.__index = BufferPool

export type BufferPool = typeof(setmetatable({} :: any, BufferPool))

local function clampInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then math.floor(valueRaw) else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

function BufferPool.new(configRaw: any?): BufferPool
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		maxAvailable = clampInteger(config.maxAvailable, 32, 1, 1024),
		arrays = {} :: { { any } },
	}, BufferPool)
	return self
end

function BufferPool.acquireArray(self: BufferPool): { any }
	local count = #self.arrays
	if count <= 0 then
		return {}
	end

	local array = self.arrays[count]
	self.arrays[count] = nil
	table.clear(array)
	return array
end

function BufferPool.releaseArray(self: BufferPool, arrayRaw: any)
	if typeof(arrayRaw) ~= "table" then
		return
	end

	local array = arrayRaw :: { any }
	table.clear(array)
	if #self.arrays >= self.maxAvailable then
		return
	end
	self.arrays[#self.arrays + 1] = array
end

function BufferPool.destroy(self: BufferPool)
	for index = #self.arrays, 1, -1 do
		self.arrays[index] = nil
	end
end

return BufferPool
