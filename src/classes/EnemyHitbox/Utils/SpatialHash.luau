--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bounds = require(ReplicatedStorage.Shared.Modules.Math.Bounds)

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type SpatialHashEntry<T> = {
	id: string,
	payload: T,
	aabbMin: Vector3,
	aabbMax: Vector3,
	cellKeys: { [string]: true },
}

export type SpatialHash<T> = typeof(setmetatable(
	{} :: {
		cellSize: number,
		cells: { [string]: { [string]: SpatialHashEntry<T> } },
		entries: { [string]: SpatialHashEntry<T> },
	},
	SpatialHash
))

local DEFAULT_CELL_SIZE = 8

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end

	return value
end

local function ensureAabb(aabbMinRaw: any, aabbMaxRaw: any): (Vector3, Vector3)
	if typeof(aabbMinRaw) ~= "Vector3" or typeof(aabbMaxRaw) ~= "Vector3" then
		return Vector3.zero, Vector3.zero
	end

	local bounds = Bounds.new(aabbMinRaw, aabbMaxRaw)
	return bounds.min, bounds.max
end

local function hashCellKey(cellX: number, cellY: number, cellZ: number): string
	return (`{cellX}:{cellY}:{cellZ}`)
end

local function computeCellIndex(value: number, cellSize: number): number
	return math.floor(value / cellSize)
end

local function overlapRange(minValue: number, maxValue: number, cellSize: number): (number, number)
	local fromCell = computeCellIndex(minValue, cellSize)
	local toCell = computeCellIndex(maxValue, cellSize)
	if toCell < fromCell then
		toCell = fromCell
	end
	return fromCell, toCell
end

function SpatialHash.new<T>(cellSizeRaw: any): SpatialHash<T>
	local self = setmetatable({
		cellSize = sanitizeNumber(cellSizeRaw, DEFAULT_CELL_SIZE, 0.1, 2048),
		cells = {},
		entries = {},
	}, SpatialHash)

	return self :: any
end

function SpatialHash.cellKey(cellX: number, cellY: number, cellZ: number): string
	return hashCellKey(cellX, cellY, cellZ)
end

function SpatialHash.aabbFromCenterSize(centerRaw: any, sizeRaw: any): (Vector3, Vector3)
	local center = if typeof(centerRaw) == "Vector3" then centerRaw else Vector3.zero
	local size = if typeof(sizeRaw) == "Vector3" then sizeRaw else Vector3.zero
	local bounds = Bounds.fromCenterSize(center, size)
	return bounds.min, bounds.max
end

function SpatialHash.aabbIntersects(aMinRaw: any, aMaxRaw: any, bMinRaw: any, bMaxRaw: any): boolean
	if typeof(aMinRaw) ~= "Vector3"
		or typeof(aMaxRaw) ~= "Vector3"
		or typeof(bMinRaw) ~= "Vector3"
		or typeof(bMaxRaw) ~= "Vector3" then
		return false
	end

	return Bounds.intersects(Bounds.new(aMinRaw, aMaxRaw), Bounds.new(bMinRaw, bMaxRaw))
end

function SpatialHash._forEachOverlappingCell(
	self: SpatialHash<any>,
	aabbMinRaw: any,
	aabbMaxRaw: any,
	callback: (cellKey: string, cellX: number, cellY: number, cellZ: number) -> ()
)
	if typeof(callback) ~= "function" then
		return
	end

	local aabbMin, aabbMax = ensureAabb(aabbMinRaw, aabbMaxRaw)
	local cellSize = self.cellSize
	local fromX, toX = overlapRange(aabbMin.X, aabbMax.X, cellSize)
	local fromY, toY = overlapRange(aabbMin.Y, aabbMax.Y, cellSize)
	local fromZ, toZ = overlapRange(aabbMin.Z, aabbMax.Z, cellSize)

	for cellX = fromX, toX do
		for cellY = fromY, toY do
			for cellZ = fromZ, toZ do
				local key = hashCellKey(cellX, cellY, cellZ)
				callback(key, cellX, cellY, cellZ)
			end
		end
	end
end

function SpatialHash.has(self: SpatialHash<any>, idRaw: any): boolean
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return false
	end
	return self.entries[idRaw] ~= nil
end

function SpatialHash.get(self: SpatialHash<any>, idRaw: any): SpatialHashEntry<any>?
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return nil
	end
	return self.entries[idRaw]
end

function SpatialHash.remove(self: SpatialHash<any>, idRaw: any)
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return
	end

	local entry = self.entries[idRaw]
	if entry == nil then
		return
	end

	for cellKey in entry.cellKeys do
		local cell = self.cells[cellKey]
		if cell ~= nil then
			cell[idRaw] = nil
			if next(cell) == nil then
				self.cells[cellKey] = nil
			end
		end
	end

	self.entries[idRaw] = nil
end

function SpatialHash.upsert(
	self: SpatialHash<any>,
	idRaw: any,
	aabbMinRaw: any,
	aabbMaxRaw: any,
	payload: any
): SpatialHashEntry<any>?
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return nil
	end

	local aabbMin, aabbMax = ensureAabb(aabbMinRaw, aabbMaxRaw)
	if payload == nil then
		return nil
	end

	self:remove(idRaw)

	local entry: SpatialHashEntry<any> = {
		id = idRaw,
		payload = payload,
		aabbMin = aabbMin,
		aabbMax = aabbMax,
		cellKeys = {},
	}

	self.entries[idRaw] = entry

	self:_forEachOverlappingCell(aabbMin, aabbMax, function(cellKey: string)
		local cell = self.cells[cellKey]
		if cell == nil then
			cell = {}
			self.cells[cellKey] = cell
		end
		cell[idRaw] = entry
		entry.cellKeys[cellKey] = true
	end)

	return entry
end

function SpatialHash.clear(self: SpatialHash<any>)
	table.clear(self.cells)
	table.clear(self.entries)
end

function SpatialHash.queryAabb(
	self: SpatialHash<any>,
	aabbMinRaw: any,
	aabbMaxRaw: any,
	predicate: ((entry: SpatialHashEntry<any>) -> boolean)?
): { SpatialHashEntry<any> }
	local aabbMin, aabbMax = ensureAabb(aabbMinRaw, aabbMaxRaw)
	local dedupById: { [string]: SpatialHashEntry<any> } = {}

	self:_forEachOverlappingCell(aabbMin, aabbMax, function(cellKey: string)
		local cell = self.cells[cellKey]
		if cell == nil then
			return
		end

		for id, entry in cell do
			if dedupById[id] ~= nil then
				continue
			end

			if not SpatialHash.aabbIntersects(entry.aabbMin, entry.aabbMax, aabbMin, aabbMax) then
				continue
			end

			if predicate ~= nil and not predicate(entry) then
				continue
			end

			dedupById[id] = entry
		end
	end)

	local out = {}
	for _, entry in dedupById do
		table.insert(out, entry)
	end
	return out
end

function SpatialHash.querySphere(
	self: SpatialHash<any>,
	centerRaw: any,
	radiusRaw: any,
	predicate: ((entry: SpatialHashEntry<any>) -> boolean)?
): { SpatialHashEntry<any> }
	local center = if typeof(centerRaw) == "Vector3" then centerRaw else Vector3.zero
	local radius = sanitizeNumber(radiusRaw, 0, 0, nil)
	local half = Vector3.new(radius, radius, radius)
	local aabbMin = center - half
	local aabbMax = center + half
	local radiusSquared = radius * radius

	return self:queryAabb(aabbMin, aabbMax, function(entry: SpatialHashEntry<any>): boolean
		if predicate ~= nil and not predicate(entry) then
			return false
		end

		local bounds = Bounds.new(entry.aabbMin, entry.aabbMax)
		return Bounds.distanceSqToPoint(bounds, center) <= radiusSquared
	end)
end

return SpatialHash
