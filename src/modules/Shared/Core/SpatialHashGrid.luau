--!strict

local SpatialHashGrid = {}
SpatialHashGrid.__index = SpatialHashGrid

export type EntryId = string | number

export type EntryRecord<T> = {
	id: EntryId,
	x: number,
	y: number,
	z: number,
	payload: T,
	cellX: number,
	cellY: number,
	cellZ: number,
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	cellKey: string,
	chunkKey: string,
}

export type SpatialHashGrid<T> = typeof(setmetatable({} :: any, SpatialHashGrid))

export type GridConfig = {
	cellSize: number,
	cellsPerChunk: number?,
	deterministicQueries: boolean?,
}

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
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

local function floorDiv(value: number, divisor: number): number
	return math.floor(value / divisor)
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function defaultSortById(a: EntryRecord<any>, b: EntryRecord<any>): boolean
	local idA = a.id
	local idB = b.id
	if typeof(idA) == typeof(idB) then
		if typeof(idA) == "number" then
			return (idA :: number) < (idB :: number)
		end
		return tostring(idA) < tostring(idB)
	end
	return tostring(typeof(idA)) < tostring(typeof(idB))
end

function SpatialHashGrid.new<T>(configRaw: GridConfig): SpatialHashGrid<T>
	local config = if typeof(configRaw) == "table" then configRaw else ({ cellSize = 8 } :: GridConfig)
	local cellSize = clampNumber(config.cellSize, 8, 0.001, 100000)
	local cellsPerChunk = math.max(1, math.floor(clampNumber(config.cellsPerChunk, 4, 1, 512)))
	local deterministic = if config.deterministicQueries == nil then true else config.deterministicQueries == true

	local self = setmetatable({
		cellSize = cellSize,
		invCellSize = 1 / cellSize,
		cellsPerChunk = cellsPerChunk,
		deterministicQueries = deterministic,
		entries = {} :: { [EntryId]: EntryRecord<T> },
		cells = {} :: { [string]: { [EntryId]: EntryRecord<T> } },
		chunks = {} :: { [string]: { [EntryId]: true } },
		entryCount = 0,
	}, SpatialHashGrid)
	return self
end

function SpatialHashGrid._worldToCell(self: SpatialHashGrid<any>, x: number, y: number, z: number): (number, number, number)
	local cellX = floorDiv(x, self.cellSize)
	local cellY = floorDiv(y, self.cellSize)
	local cellZ = floorDiv(z, self.cellSize)
	return cellX, cellY, cellZ
end

function SpatialHashGrid._cellToChunk(self: SpatialHashGrid<any>, cellX: number, cellY: number, cellZ: number): (number, number, number)
	local chunkX = floorDiv(cellX, self.cellsPerChunk)
	local chunkY = floorDiv(cellY, self.cellsPerChunk)
	local chunkZ = floorDiv(cellZ, self.cellsPerChunk)
	return chunkX, chunkY, chunkZ
end

function SpatialHashGrid._attach(self: SpatialHashGrid<any>, record: EntryRecord<any>)
	local cellBucket = self.cells[record.cellKey]
	if cellBucket == nil then
		cellBucket = {}
		self.cells[record.cellKey] = cellBucket
	end
	cellBucket[record.id] = record

	local chunkBucket = self.chunks[record.chunkKey]
	if chunkBucket == nil then
		chunkBucket = {}
		self.chunks[record.chunkKey] = chunkBucket
	end
	chunkBucket[record.id] = true
end

function SpatialHashGrid._detach(self: SpatialHashGrid<any>, record: EntryRecord<any>)
	local cellBucket = self.cells[record.cellKey]
	if cellBucket ~= nil then
		cellBucket[record.id] = nil
		if next(cellBucket) == nil then
			self.cells[record.cellKey] = nil
		end
	end

	local chunkBucket = self.chunks[record.chunkKey]
	if chunkBucket ~= nil then
		chunkBucket[record.id] = nil
		if next(chunkBucket) == nil then
			self.chunks[record.chunkKey] = nil
		end
	end
end

function SpatialHashGrid.insert<T>(self: SpatialHashGrid<T>, idRaw: any, xRaw: any, yRaw: any, zRaw: any, payload: T): boolean
	local idKind = typeof(idRaw)
	if idKind ~= "string" and idKind ~= "number" then
		return false
	end
	local id = idRaw :: EntryId
	if self.entries[id] ~= nil then
		return false
	end

	local x = if typeof(xRaw) == "number" then xRaw else 0
	local y = if typeof(yRaw) == "number" then yRaw else 0
	local z = if typeof(zRaw) == "number" then zRaw else 0
	local cellX, cellY, cellZ = self:_worldToCell(x, y, z)
	local chunkX, chunkY, chunkZ = self:_cellToChunk(cellX, cellY, cellZ)

	local record = {
		id = id,
		x = x,
		y = y,
		z = z,
		payload = payload,
		cellX = cellX,
		cellY = cellY,
		cellZ = cellZ,
		chunkX = chunkX,
		chunkY = chunkY,
		chunkZ = chunkZ,
		cellKey = key3(cellX, cellY, cellZ),
		chunkKey = key3(chunkX, chunkY, chunkZ),
	} :: EntryRecord<T>

	self.entries[id] = record
	self.entryCount += 1
	self:_attach(record)
	return true
end

function SpatialHashGrid.Remove(self: SpatialHashGrid<any>, idRaw: any): boolean
	local record = self.entries[idRaw]
	if record == nil then
		return false
	end
	self:_detach(record)
	self.entries[idRaw] = nil
	self.entryCount -= 1
	return true
end

function SpatialHashGrid.update<T>(self: SpatialHashGrid<T>, idRaw: any, xRaw: any, yRaw: any, zRaw: any, payload: T?): boolean
	local record = self.entries[idRaw]
	if record == nil then
		return false
	end

	local x = if typeof(xRaw) == "number" then xRaw else record.x
	local y = if typeof(yRaw) == "number" then yRaw else record.y
	local z = if typeof(zRaw) == "number" then zRaw else record.z
	local cellX, cellY, cellZ = self:_worldToCell(x, y, z)
	local chunkX, chunkY, chunkZ = self:_cellToChunk(cellX, cellY, cellZ)

	if payload ~= nil then
		record.payload = payload
	end

	if cellX == record.cellX and cellY == record.cellY and cellZ == record.cellZ and chunkX == record.chunkX and chunkY == record.chunkY and chunkZ == record.chunkZ then
		record.x = x
		record.y = y
		record.z = z
		return true
	end

	self:_detach(record)
	record.x = x
	record.y = y
	record.z = z
	record.cellX = cellX
	record.cellY = cellY
	record.cellZ = cellZ
	record.chunkX = chunkX
	record.chunkY = chunkY
	record.chunkZ = chunkZ
	record.cellKey = key3(cellX, cellY, cellZ)
	record.chunkKey = key3(chunkX, chunkY, chunkZ)
	self:_attach(record)
	return true
end

function SpatialHashGrid.Get(self: SpatialHashGrid<any>, idRaw: any): EntryRecord<any>?
	return self.entries[idRaw]
end

function SpatialHashGrid.Count(self: SpatialHashGrid<any>): number
	return self.entryCount
end

function SpatialHashGrid.queryCell<T>(self: SpatialHashGrid<T>, cellXRaw: any, cellYRaw: any, cellZRaw: any, outRaw: { EntryRecord<T> }?): { EntryRecord<T> }
	local cellX = if typeof(cellXRaw) == "number" then math.floor(cellXRaw) else 0
	local cellY = if typeof(cellYRaw) == "number" then math.floor(cellYRaw) else 0
	local cellZ = if typeof(cellZRaw) == "number" then math.floor(cellZRaw) else 0
	local out = if outRaw ~= nil then outRaw else {}
	clearArray(out)

	local bucket = self.cells[key3(cellX, cellY, cellZ)]
	if bucket ~= nil then
		for _, record in bucket do
			out[#out + 1] = record
		end
	end
	if self.deterministicQueries and #out > 1 then
		table.sort(out :: any, defaultSortById)
	end
	return out
end

function SpatialHashGrid.queryChunk<T>(self: SpatialHashGrid<T>, chunkXRaw: any, chunkYRaw: any, chunkZRaw: any, outRaw: { EntryRecord<T> }?): { EntryRecord<T> }
	local chunkX = if typeof(chunkXRaw) == "number" then math.floor(chunkXRaw) else 0
	local chunkY = if typeof(chunkYRaw) == "number" then math.floor(chunkYRaw) else 0
	local chunkZ = if typeof(chunkZRaw) == "number" then math.floor(chunkZRaw) else 0
	local out = if outRaw ~= nil then outRaw else {}
	clearArray(out)

	local bucket = self.chunks[key3(chunkX, chunkY, chunkZ)]
	if bucket ~= nil then
		for id in bucket do
			local record = self.entries[id]
			if record ~= nil then
				out[#out + 1] = record
			end
		end
	end
	if self.deterministicQueries and #out > 1 then
		table.sort(out :: any, defaultSortById)
	end
	return out
end

function SpatialHashGrid.queryRadius<T>(self: SpatialHashGrid<T>, xRaw: any, yRaw: any, zRaw: any, radiusRaw: any, outRaw: { EntryRecord<T> }?): { EntryRecord<T> }
	local x = if typeof(xRaw) == "number" then xRaw else 0
	local y = if typeof(yRaw) == "number" then yRaw else 0
	local z = if typeof(zRaw) == "number" then zRaw else 0
	local radius = clampNumber(radiusRaw, 0, 0, 1000000)
	local out = if outRaw ~= nil then outRaw else {}
	clearArray(out)

	local minCellX = floorDiv(x - radius, self.cellSize)
	local minCellY = floorDiv(y - radius, self.cellSize)
	local minCellZ = floorDiv(z - radius, self.cellSize)
	local maxCellX = floorDiv(x + radius, self.cellSize)
	local maxCellY = floorDiv(y + radius, self.cellSize)
	local maxCellZ = floorDiv(z + radius, self.cellSize)

	local radiusSq = radius * radius
	for cellY = minCellY, maxCellY do
		for cellX = minCellX, maxCellX do
			for cellZ = minCellZ, maxCellZ do
				local bucket = self.cells[key3(cellX, cellY, cellZ)]
				if bucket ~= nil then
					for _, record in bucket do
						local dx = record.x - x
						local dy = record.y - y
						local dz = record.z - z
						if dx * dx + dy * dy + dz * dz <= radiusSq then
							out[#out + 1] = record
						end
					end
				end
			end
		end
	end

	if self.deterministicQueries and #out > 1 then
		table.sort(out :: any, defaultSortById)
	end
	return out
end

function SpatialHashGrid.WorldToChunk(self: SpatialHashGrid<any>, xRaw: any, yRaw: any, zRaw: any): (number, number, number)
	local x = if typeof(xRaw) == "number" then xRaw else 0
	local y = if typeof(yRaw) == "number" then yRaw else 0
	local z = if typeof(zRaw) == "number" then zRaw else 0
	local cellX, cellY, cellZ = self:_worldToCell(x, y, z)
	return self:_cellToChunk(cellX, cellY, cellZ)
end

function SpatialHashGrid.Clear(self: SpatialHashGrid<any>)
	table.clear(self.entries)
	table.clear(self.cells)
	table.clear(self.chunks)
	self.entryCount = 0
end

SpatialHashGrid.remove = SpatialHashGrid.Remove
SpatialHashGrid.get = SpatialHashGrid.Get
SpatialHashGrid.count = SpatialHashGrid.Count
SpatialHashGrid.worldToChunk = SpatialHashGrid.WorldToChunk
SpatialHashGrid.clear = SpatialHashGrid.Clear

return SpatialHashGrid
