local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CropTypes = require("CropTypes")

local CropStateStore = {}
CropStateStore.__index = CropStateStore

local function removeIndexEntry(index: { [string]: { [string]: boolean } }, groupKey: string, key: string)
	local entries = index[groupKey]
	if entries == nil then
		return
	end
	entries[key] = nil
	if next(entries) == nil then
		index[groupKey] = nil
	end
end

local function addIndexEntry(index: { [string]: { [string]: boolean } }, groupKey: string, key: string)
	local entries = index[groupKey]
	if entries == nil then
		entries = {}
		index[groupKey] = entries
	end
	entries[key] = true
end

function CropStateStore.New(chunkSizeRaw: any): any
	local chunkSize = if typeof(chunkSizeRaw) == "number" then math.max(1, math.floor(chunkSizeRaw)) else 32
	return setmetatable({
		_chunkSize = chunkSize,
		_statesByKey = {},
		_keysByChunk = {},
		_keysByRoot = {},
		_count = 0,
	}, CropStateStore)
end

function CropStateStore._removeIndexes(self: any, key: string, state: any)
	local chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, self._chunkSize)
	local rootKey = state.rootKey or key
	removeIndexEntry(self._keysByChunk, chunkKey, key)
	removeIndexEntry(self._keysByRoot, rootKey, key)
end

function CropStateStore._addIndexes(self: any, key: string, state: any)
	local chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, self._chunkSize)
	local rootKey = state.rootKey or key
	addIndexEntry(self._keysByChunk, chunkKey, key)
	addIndexEntry(self._keysByRoot, rootKey, key)
end

function CropStateStore.Get(self: any, tileXRaw: any, tileYRaw: any): any?
	if typeof(tileXRaw) ~= "number" or typeof(tileYRaw) ~= "number" then
		return nil
	end
	return CropTypes.CloneState(self._statesByKey[CropTypes.GetTileKey(math.floor(tileXRaw), math.floor(tileYRaw))])
end

function CropStateStore.GetByKey(self: any, keyRaw: any): any?
	if typeof(keyRaw) ~= "string" then
		return nil
	end
	return CropTypes.CloneState(self._statesByKey[keyRaw])
end

function CropStateStore.Set(self: any, stateRaw: any): (boolean, any?)
	local state = CropTypes.CloneState(stateRaw)
	if state == nil then
		return false, nil
	end

	local key = CropTypes.GetTileKey(state.tileX, state.tileY)
	local previous = self._statesByKey[key]
	if previous ~= nil then
		self:_removeIndexes(key, previous)
	else
		self._count += 1
	end

	if state.rootKey == nil then
		state.rootKey = key
	end
	self._statesByKey[key] = state
	self:_addIndexes(key, state)
	return true, CropTypes.CloneState(previous)
end

function CropStateStore.RemoveByKey(self: any, keyRaw: any): any?
	if typeof(keyRaw) ~= "string" then
		return nil
	end

	local previous = self._statesByKey[keyRaw]
	if previous == nil then
		return nil
	end
	self:_removeIndexes(keyRaw, previous)
	self._statesByKey[keyRaw] = nil
	self._count = math.max(0, self._count - 1)
	return CropTypes.CloneState(previous)
end

function CropStateStore.Remove(self: any, tileXRaw: any, tileYRaw: any): any?
	if typeof(tileXRaw) ~= "number" or typeof(tileYRaw) ~= "number" then
		return nil
	end
	return self:RemoveByKey(CropTypes.GetTileKey(math.floor(tileXRaw), math.floor(tileYRaw)))
end

function CropStateStore.RemoveRoot(self: any, rootKeyRaw: any): { any }
	if typeof(rootKeyRaw) ~= "string" then
		return {}
	end

	local rootEntries = self._keysByRoot[rootKeyRaw]
	if rootEntries == nil then
		return {}
	end
	local keys = {}
	for key in rootEntries do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local removed = {}
	for _, key in keys do
		local state = self:RemoveByKey(key)
		if state ~= nil then
			removed[#removed + 1] = state
		end
	end
	return removed
end

function CropStateStore.GetRootStates(self: any, rootKeyRaw: any): { any }
	if typeof(rootKeyRaw) ~= "string" then
		return {}
	end
	local entries = self._keysByRoot[rootKeyRaw]
	if entries == nil then
		return {}
	end

	local keys = {}
	for key in entries do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local states = {}
	for _, key in keys do
		local state = CropTypes.CloneState(self._statesByKey[key])
		if state ~= nil then
			states[#states + 1] = state
		end
	end
	return states
end

function CropStateStore.GetChunkStates(self: any, chunkKeyRaw: any): { any }
	if typeof(chunkKeyRaw) ~= "string" then
		return {}
	end
	local entries = self._keysByChunk[chunkKeyRaw]
	if entries == nil then
		return {}
	end

	local keys = {}
	for key in entries do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local states = {}
	for _, key in keys do
		local state = CropTypes.CloneState(self._statesByKey[key])
		if state ~= nil then
			states[#states + 1] = state
		end
	end
	return states
end

function CropStateStore.GetAll(self: any): { any }
	local keys = {}
	for key in self._statesByKey do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local states = {}
	for _, key in keys do
		local state = CropTypes.CloneState(self._statesByKey[key])
		if state ~= nil then
			states[#states + 1] = state
		end
	end
	return states
end

function CropStateStore.GetCount(self: any): number
	return self._count
end

function CropStateStore.Clear(self: any)
	table.clear(self._statesByKey)
	table.clear(self._keysByChunk)
	table.clear(self._keysByRoot)
	self._count = 0
end

function CropStateStore.Destroy(self: any)
	self:Clear()
end

return Table.readonly(CropStateStore)
