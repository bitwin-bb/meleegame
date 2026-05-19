--!strict
local TextService = game:GetService("TextService")

local TextMeasurementCache = {}
TextMeasurementCache.__index = TextMeasurementCache

export type MeasureRequest = {
	text: string,
	fontSize: number,
	font: Enum.Font?,
	bounds: Vector2?,
}

export type TextMeasurementCacheConfig = {
	maxEntries: number?,
	evictBatchSize: number?,
}

export type TextMeasurementCache = typeof(setmetatable({} :: any, TextMeasurementCache))

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

local function normalizeBounds(boundsRaw: any): Vector2
	if typeof(boundsRaw) == "Vector2" then
		return Vector2.new(math.max(0, boundsRaw.X), math.max(0, boundsRaw.Y))
	end
	return Vector2.new(10000, 10000)
end

local function normalizeFont(fontRaw: any): Enum.Font
	if typeof(fontRaw) == "EnumItem" then
		return fontRaw :: Enum.Font
	end
	if typeof(fontRaw) == "string" then
		for _, enumValue in Enum.Font:GetEnumItems() do
			if enumValue.Name == fontRaw then
				return enumValue
			end
		end
	end
	return Enum.Font.SourceSans
end

local function buildKey(text: string, fontSize: number, font: Enum.Font, bounds: Vector2): string
	return string.format("%s|%d|%s|%d|%d", text, fontSize, font.Name, math.floor(bounds.X), math.floor(bounds.Y))
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

function TextMeasurementCache.New(configRaw: TextMeasurementCacheConfig?): TextMeasurementCache
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		entries = {} :: { [string]: { size: Vector2, lastAccess: number } },
		maxEntries = clampInteger(config.maxEntries, 4096, 32, 200000),
		evictBatchSize = clampInteger(config.evictBatchSize, 128, 1, 50000),
		clock = 0,
		hits = 0,
		misses = 0,
	}, TextMeasurementCache)
	return self
end

function TextMeasurementCache._evictIfNeeded(self: TextMeasurementCache)
	local entryCount = 0
	for _ in self.entries do
		entryCount += 1
	end
	if entryCount <= self.maxEntries then
		return
	end

	local snapshots = {}
	for key, entry in self.entries do
		snapshots[#snapshots + 1] = {
			key = key,
			lastAccess = entry.lastAccess,
		}
	end
	table.sort(snapshots, function(a, b)
		return a.lastAccess < b.lastAccess
	end)

	local removeCount = math.min(#snapshots, math.max(entryCount - self.maxEntries, self.evictBatchSize))
	for index = 1, removeCount do
		self.entries[snapshots[index].key] = nil
	end
end

function TextMeasurementCache.Measure(
	self: TextMeasurementCache,
	textRaw: any,
	fontSizeRaw: any,
	fontRaw: any,
	boundsRaw: any
): Vector2
	local text = if typeof(textRaw) == "string" then textRaw else tostring(textRaw)
	local fontSize = clampInteger(fontSizeRaw, 14, 1, 512)
	local font = normalizeFont(fontRaw)
	local bounds = normalizeBounds(boundsRaw)
	local key = buildKey(text, fontSize, font, bounds)

	self.clock += 1
	local cached = self.entries[key]
	if cached ~= nil then
		self.hits += 1
		cached.lastAccess = self.clock
		return cached.size
	end

	self.misses += 1
	local size = TextService:GetTextSize(text, fontSize, font, bounds)
	self.entries[key] = {
		size = size,
		lastAccess = self.clock,
	}
	self:_evictIfNeeded()
	return size
end

function TextMeasurementCache.MeasureBatch(self: TextMeasurementCache, requestsRaw: any, outRaw: { Vector2 }?): { Vector2 }
	local out = if outRaw ~= nil then outRaw else {}
	if typeof(requestsRaw) ~= "table" then
		clearArray(out)
		return out
	end

	local count = #requestsRaw
	for index = 1, count do
		local request = requestsRaw[index]
		if typeof(request) ~= "table" then
			out[index] = Vector2.zero
			continue
		end
		out[index] = self:measure(request.text, request.fontSize, request.font, request.bounds)
	end
	for index = #out, count + 1, -1 do
		out[index] = nil
	end
	return out
end

function TextMeasurementCache.SetMaxEntries(self: TextMeasurementCache, maxEntriesRaw: any)
	self.maxEntries = clampInteger(maxEntriesRaw, self.maxEntries, 32, 200000)
	self:_evictIfNeeded()
end

function TextMeasurementCache.Clear(self: TextMeasurementCache)
	table.clear(self.entries)
	self.clock = 0
	self.hits = 0
	self.misses = 0
end

function TextMeasurementCache.GetStats(self: TextMeasurementCache): { [string]: number }
	local entryCount = 0
	for _ in self.entries do
		entryCount += 1
	end
	return {
		entries = entryCount,
		hits = self.hits,
		misses = self.misses,
		maxEntries = self.maxEntries,
	}
end

TextMeasurementCache.new = TextMeasurementCache.New
TextMeasurementCache.measure = TextMeasurementCache.Measure
TextMeasurementCache.measureBatch = TextMeasurementCache.MeasureBatch
TextMeasurementCache.setMaxEntries = TextMeasurementCache.SetMaxEntries
TextMeasurementCache.clear = TextMeasurementCache.Clear
TextMeasurementCache.getStats = TextMeasurementCache.GetStats

return TextMeasurementCache
