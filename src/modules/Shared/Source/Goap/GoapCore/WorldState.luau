
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Signal = packages.Signal
local Table = packages.Table
local ValueObject = packages.ValueObject

local WorldState = {}
WorldState.__index = WorldState

export type WorldState = typeof(setmetatable(
	{} :: {
		values: { [string]: any },
		valueObjects: { [string]: any },
		maid: any,
		Changed: any,
		destroyed: boolean,
	},
	WorldState
))

local function CoerceKey(keyRaw: any): string?
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return nil
	end
	return keyRaw
end

local function readFacts(factsRaw: any): { [string]: any }
	if typeof(factsRaw) ~= "table" then
		return {}
	end
	local toTable = factsRaw.ToTable or factsRaw.toTable
	if typeof(toTable) == "function" then
		local ok, result = pcall(toTable, factsRaw)
		if ok and typeof(result) == "table" then
			return Table.copy(result)
		end
	end
	return Table.copy(factsRaw)
end

function WorldState.new(valuesRaw: any?): WorldState
	local self = setmetatable({
		values = readFacts(valuesRaw),
		valueObjects = {},
		maid = Maid.new(),
		Changed = Signal.new(),
		destroyed = false,
	}, WorldState)

	self.maid:GiveTask(self.Changed)
	return self
end

function WorldState.From(valueRaw: any): WorldState
	if typeof(valueRaw) == "table" and getmetatable(valueRaw) == WorldState then
		return valueRaw:Clone()
	end
	return WorldState.new(valueRaw)
end

function WorldState._syncValueObject(self: WorldState, key: string, value: any)
	local valueObject = self.valueObjects[key]
	if valueObject == nil then
		return
	end
	valueObject.Value = value
end

function WorldState.Set(self: WorldState, keyRaw: any, value: any)
	local key = CoerceKey(keyRaw)
	if key == nil or self.destroyed then
		return
	end
	local oldValue = self.values[key]
	if oldValue == value then
		return
	end
	self.values[key] = value
	self:_syncValueObject(key, value)
	self.Changed:Fire(key, value, oldValue)
end

function WorldState.Get(self: WorldState, keyRaw: any): any?
	local key = CoerceKey(keyRaw)
	if key == nil or self.destroyed then
		return nil
	end
	return self.values[key]
end

function WorldState.Has(self: WorldState, keyRaw: any): boolean
	local key = CoerceKey(keyRaw)
	return key ~= nil and not self.destroyed and self.values[key] ~= nil
end

function WorldState.Remove(self: WorldState, keyRaw: any): any?
	local key = CoerceKey(keyRaw)
	if key == nil or self.destroyed then
		return nil
	end
	local oldValue = self.values[key]
	if oldValue == nil then
		return nil
	end
	self.values[key] = nil
	self:_syncValueObject(key, nil)
	self.Changed:Fire(key, nil, oldValue)
	return oldValue
end

function WorldState.Clear(self: WorldState)
	if self.destroyed then
		return
	end
	for key, oldValue in Table.copy(self.values) do
		self.values[key] = nil
		self:_syncValueObject(key, nil)
		self.Changed:Fire(key, nil, oldValue)
	end
	table.clear(self.values)
end

function WorldState.Clone(self: WorldState): WorldState
	if self.destroyed then
		return WorldState.new()
	end
	return WorldState.new(self.values)
end

function WorldState.Matches(self: WorldState, otherWorldStateRaw: any): boolean
	local otherValues = readFacts(otherWorldStateRaw)
	for key, value in self.values do
		if otherValues[key] ~= value then
			return false
		end
	end
	for key, value in otherValues do
		if self.values[key] ~= value then
			return false
		end
	end
	return true
end

function WorldState.Satisfies(self: WorldState, conditionsRaw: any): boolean
	if self.destroyed then
		return false
	end
	for key, value in readFacts(conditionsRaw) do
		if self.values[key] ~= value then
			return false
		end
	end
	return true
end

function WorldState.Apply(self: WorldState, effectsRaw: any): WorldState
	if self.destroyed then
		return self
	end
	for key, value in readFacts(effectsRaw) do
		self:Set(key, value)
	end
	return self
end

function WorldState.ToTable(self: WorldState): { [string]: any }
	if self.destroyed then
		return {}
	end
	return Table.copy(self.values)
end

function WorldState.GetValueObject(self: WorldState, keyRaw: any): any?
	local key = CoerceKey(keyRaw)
	if key == nil or self.destroyed then
		return nil
	end
	local valueObject = self.valueObjects[key]
	if valueObject == nil then
		valueObject = ValueObject.new(self.values[key])
		self.valueObjects[key] = valueObject
		self.maid:GiveTask(valueObject)
	end
	return valueObject
end

function WorldState.GetChangedSignal(self: WorldState): any
	return self.Changed
end

function WorldState.Destroy(self: WorldState)
	if self.destroyed then
		return
	end
	self:Clear()
	self.destroyed = true
	table.clear(self.valueObjects)
	self.maid:DoCleaning()
end
return WorldState
