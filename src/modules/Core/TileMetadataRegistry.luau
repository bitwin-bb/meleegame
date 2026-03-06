--!strict

local Codec = require(script.Parent.Codec)

local TileMetadataRegistry = {}
TileMetadataRegistry.__index = TileMetadataRegistry

export type DropDefinition = {
	itemId: string,
	minAmount: number?,
	maxAmount: number?,
	chance: number?,
}

export type TileMetadata = {
	id: string,
	hardness: number,
	drops: { DropDefinition },
	flags: number,
	corruptionSusceptibility: number,
	lightBlocking: number,
	toolTier: number,
	attributes: { [string]: any },
}

export type TileMetadataRegistry = typeof(setmetatable({} :: any, TileMetadataRegistry))

local MAX_FLAGS = 31

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

local function sanitizeDrop(dropRaw: any): DropDefinition?
	if typeof(dropRaw) ~= "table" then
		return nil
	end
	local itemId = if typeof(dropRaw.itemId) == "string" then dropRaw.itemId else ""
	if itemId == "" then
		return nil
	end
	local minAmount = clampInteger(dropRaw.minAmount, 1, 1, 999999)
	local maxAmount = clampInteger(dropRaw.maxAmount, minAmount, minAmount, 999999)
	local chance = clampNumber(dropRaw.chance, 1, 0, 1)
	return {
		itemId = itemId,
		minAmount = minAmount,
		maxAmount = maxAmount,
		chance = chance,
	}
end

local function sortIds(a: string, b: string): boolean
	return a < b
end

function TileMetadataRegistry.new(initialTilesRaw: any?): TileMetadataRegistry
	local self = setmetatable({
		entries = {} :: { [string]: TileMetadata },
		idOrder = {} :: { string },
		flagLayout = {} :: { [string]: number },
		nextFlagIndex = 1,
	}, TileMetadataRegistry)

	if typeof(initialTilesRaw) == "table" then
		for tileId, metadata in initialTilesRaw do
			if typeof(tileId) == "string" then
				self:register(tileId, metadata)
			end
		end
	end

	return self
end

function TileMetadataRegistry.defineFlag(self: TileMetadataRegistry, flagNameRaw: any, bitIndexRaw: any?): number
	if typeof(flagNameRaw) ~= "string" or flagNameRaw == "" then
		return 0
	end
	local existing = self.flagLayout[flagNameRaw]
	if existing ~= nil then
		return existing
	end

	local bitIndex = if bitIndexRaw ~= nil then clampInteger(bitIndexRaw, self.nextFlagIndex, 1, MAX_FLAGS) else self.nextFlagIndex
	self.flagLayout[flagNameRaw] = bitIndex
	if bitIndex >= self.nextFlagIndex then
		self.nextFlagIndex = math.min(MAX_FLAGS + 1, bitIndex + 1)
	end
	return bitIndex
end

function TileMetadataRegistry.encodeFlags(self: TileMetadataRegistry, flagsRaw: any): number
	if typeof(flagsRaw) ~= "table" then
		return 0
	end
	local namedFlags = {}
	for flagName, enabled in flagsRaw do
		if typeof(flagName) == "string" and enabled then
			if self.flagLayout[flagName] == nil then
				self:defineFlag(flagName)
			end
			namedFlags[flagName] = true
		end
	end
	return Codec.packNamedBitmask(self.flagLayout, namedFlags)
end

function TileMetadataRegistry.decodeFlags(self: TileMetadataRegistry, bitmaskRaw: any): { [string]: boolean }
	return Codec.unpackNamedBitmask(self.flagLayout, bitmaskRaw)
end

function TileMetadataRegistry.register(self: TileMetadataRegistry, tileIdRaw: any, metadataRaw: any): boolean
	if typeof(tileIdRaw) ~= "string" or tileIdRaw == "" then
		return false
	end
	if typeof(metadataRaw) ~= "table" then
		return false
	end

	local drops = {}
	if typeof(metadataRaw.drops) == "table" then
		for _, rawDrop in metadataRaw.drops do
			local drop = sanitizeDrop(rawDrop)
			if drop ~= nil then
				drops[#drops + 1] = drop
			end
		end
	end

	local flags = 0
	if typeof(metadataRaw.flags) == "number" then
		flags = clampInteger(metadataRaw.flags, 0, 0, 2147483647)
	elseif typeof(metadataRaw.flags) == "table" then
		flags = self:encodeFlags(metadataRaw.flags)
	end

	local entry = {
		id = tileIdRaw,
		hardness = clampNumber(metadataRaw.hardness, 1, 0, 1000000),
		drops = drops,
		flags = flags,
		corruptionSusceptibility = clampNumber(metadataRaw.corruptionSusceptibility, 0, 0, 1),
		lightBlocking = clampNumber(metadataRaw.lightBlocking, 0, 0, 1),
		toolTier = clampInteger(metadataRaw.toolTier, 0, 0, 100),
		attributes = if typeof(metadataRaw.attributes) == "table" then table.clone(metadataRaw.attributes) else {},
	} :: TileMetadata

	local hadExisting = self.entries[tileIdRaw] ~= nil
	self.entries[tileIdRaw] = entry
	if not hadExisting then
		self.idOrder[#self.idOrder + 1] = tileIdRaw
		table.sort(self.idOrder, sortIds)
	end
	return true
end

function TileMetadataRegistry.registerBatch(self: TileMetadataRegistry, entriesRaw: any)
	if typeof(entriesRaw) ~= "table" then
		return
	end
	for tileId, metadata in entriesRaw do
		if typeof(tileId) == "string" then
			self:register(tileId, metadata)
		end
	end
end

function TileMetadataRegistry.get(self: TileMetadataRegistry, tileIdRaw: any): TileMetadata?
	if typeof(tileIdRaw) ~= "string" then
		return nil
	end
	return self.entries[tileIdRaw]
end

function TileMetadataRegistry.require(self: TileMetadataRegistry, tileIdRaw: any): TileMetadata
	local metadata = self:get(tileIdRaw)
	if metadata == nil then
		error(string.format("TileMetadataRegistry missing tile '%s'", tostring(tileIdRaw)))
	end
	return metadata
end

function TileMetadataRegistry.hasFlag(self: TileMetadataRegistry, tileIdRaw: any, flagNameRaw: any): boolean
	if typeof(tileIdRaw) ~= "string" or typeof(flagNameRaw) ~= "string" then
		return false
	end
	local metadata = self.entries[tileIdRaw]
	if metadata == nil then
		return false
	end
	local bitIndex = self.flagLayout[flagNameRaw]
	if bitIndex == nil then
		return false
	end
	local mask = bit32.lshift(1, bitIndex - 1)
	return bit32.band(metadata.flags, mask) ~= 0
end

function TileMetadataRegistry.listIds(self: TileMetadataRegistry): { string }
	return table.clone(self.idOrder)
end

function TileMetadataRegistry.getDrops(self: TileMetadataRegistry, tileIdRaw: any, rngRaw: any?): { [string]: number }
	local out = {}
	local metadata = self:get(tileIdRaw)
	if metadata == nil then
		return out
	end
	if #metadata.drops == 0 then
		return out
	end

	local rng = rngRaw
	for _, drop in metadata.drops do
		local chance = clampNumber(drop.chance, 1, 0, 1)
		local roll = 0
		if rng ~= nil and typeof((rng :: any).nextNumber) == "function" then
			roll = (rng :: any):nextNumber()
		else
			roll = if chance >= 1 then 0 else 1
		end
		if roll <= chance then
			local minAmount = clampInteger(drop.minAmount, 1, 1, 999999)
			local maxAmount = clampInteger(drop.maxAmount, minAmount, minAmount, 999999)
			local amount = minAmount
			if maxAmount > minAmount then
				if rng ~= nil and typeof((rng :: any).nextInteger) == "function" then
					amount = (rng :: any):nextInteger(minAmount, maxAmount)
				else
					amount = minAmount
				end
			end
			out[drop.itemId] = (out[drop.itemId] or 0) + amount
		end
	end

	return out
end

function TileMetadataRegistry.snapshot(self: TileMetadataRegistry): { [string]: TileMetadata }
	local out = {}
	for _, tileId in self.idOrder do
		local metadata = self.entries[tileId]
		if metadata ~= nil then
			out[tileId] = {
				id = metadata.id,
				hardness = metadata.hardness,
				drops = table.clone(metadata.drops),
				flags = metadata.flags,
				corruptionSusceptibility = metadata.corruptionSusceptibility,
				lightBlocking = metadata.lightBlocking,
				toolTier = metadata.toolTier,
				attributes = table.clone(metadata.attributes),
			}
		end
	end
	return out
end

return TileMetadataRegistry
