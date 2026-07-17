
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")
local ValueObject = Nevermore.Get("ValueObject")

local Blackboard = {}
Blackboard.__index = Blackboard

export type Blackboard = typeof(setmetatable(
	{} :: {
		values: { [string]: any },
		valueObjects: { [string]: any },
		maid: any,
		Changed: any,
		destroyed: boolean,
	},
	Blackboard
))

local function coerceKey(keyRaw: any): string?
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return nil
	end
	return keyRaw
end

function Blackboard.new(valuesRaw: { [string]: any }?): Blackboard
	local self = setmetatable({
		values = if typeof(valuesRaw) == "table" then Table.copy(valuesRaw) else {},
		valueObjects = {},
		maid = Maid.new(),
		Changed = Signal.new(),
		destroyed = false,
	}, Blackboard)

	self.maid:GiveTask(self.Changed)
	return self
end

function Blackboard._syncValueObject(self: Blackboard, key: string, value: any)
	local valueObject = self.valueObjects[key]
	if valueObject == nil then
		return
	end
	valueObject.Value = value
end

function Blackboard.Set(self: Blackboard, keyRaw: any, value: any)
	local key = coerceKey(keyRaw)
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

function Blackboard.Get(self: Blackboard, keyRaw: any): any?
	local key = coerceKey(keyRaw)
	if key == nil or self.destroyed then
		return nil
	end
	return self.values[key]
end

function Blackboard.Has(self: Blackboard, keyRaw: any): boolean
	local key = coerceKey(keyRaw)
	return key ~= nil and not self.destroyed and self.values[key] ~= nil
end

function Blackboard.Remove(self: Blackboard, keyRaw: any): any?
	local key = coerceKey(keyRaw)
	if key == nil or self.destroyed then
		return nil
	end

	local value = self.values[key]
	if value == nil then
		return nil
	end
	self.values[key] = nil
	self:_syncValueObject(key, nil)
	self.Changed:Fire(key, nil, value)
	return value
end

function Blackboard.Clear(self: Blackboard)
	for key, oldValue in Table.copy(self.values) do
		self.values[key] = nil
		self:_syncValueObject(key, nil)
		self.Changed:Fire(key, nil, oldValue)
	end
	table.clear(self.values)
end

function Blackboard.GetSnapshot(self: Blackboard): { [string]: any }
	if self.destroyed then
		return {}
	end
	return Table.copy(self.values)
end

function Blackboard.GetValueObject(self: Blackboard, keyRaw: any): any?
	local key = coerceKey(keyRaw)
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

function Blackboard.Observe(self: Blackboard, keyRaw: any): any?
	local valueObject = self:GetValueObject(keyRaw)
	return if valueObject ~= nil then valueObject:Observe() else nil
end

function Blackboard.ObserveBrio(self: Blackboard, keyRaw: any, predicate: ((any) -> boolean)?): any?
	local valueObject = self:GetValueObject(keyRaw)
	return if valueObject ~= nil then valueObject:ObserveBrio(predicate) else nil
end

function Blackboard.GetChangedSignal(self: Blackboard): any
	return self.Changed
end

function Blackboard.Destroy(self: Blackboard)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:Clear()
	table.clear(self.valueObjects)
	self.maid:DoCleaning()
end
return Blackboard
