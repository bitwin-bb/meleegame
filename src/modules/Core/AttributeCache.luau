--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Codec = require(script.Parent.Codec)
local Signal = require(ReplicatedStorage.Packages.Signal)

local AttributeCache = {}
AttributeCache.__index = AttributeCache

export type ModifierMode = "Add" | "Multiply" | "Override"

export type ModifierRecord = {
	id: string,
	mode: ModifierMode,
	value: any,
	priority: number,
	expiresAt: number?,
}

export type ChangeListener = (instance: Instance, attribute: string, newValue: any, oldValue: any) -> ()

export type DiffRecord = {
	instance: Instance,
	attribute: string,
	oldValue: any,
	newValue: any,
	timestamp: number,
}

export type ReplicationChange = {
	instance: Instance,
	attributes: { [string]: any },
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type AttributeChangedSignal = {
	Connect: (self: AttributeChangedSignal, callback: ChangeListener) -> SignalConnection,
	Fire: (self: AttributeChangedSignal, instance: Instance, attribute: string, newValue: any, oldValue: any) -> (),
	DisconnectAll: (self: AttributeChangedSignal) -> (),
	Destroy: (self: AttributeChangedSignal) -> (),
}

export type InstanceRecord = {
	cache: { [string]: any },
	base: { [string]: any },
	modifiers: { [string]: { [string]: ModifierRecord } },
	dirty: { [string]: { oldValue: any, newValue: any } },
	dirtyOrder: { string },
	listenerSignals: { [string]: AttributeChangedSignal },
	suppress: { [string]: boolean },
	connection: RBXScriptConnection?,
	bindOrder: number,
}

export type AttributeCache = typeof(setmetatable({} :: any, AttributeCache))

local DEFAULT_GROUP = "*"

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

local function normalizeAttribute(attributeRaw: any): string?
	if typeof(attributeRaw) ~= "string" or attributeRaw == "" then
		return nil
	end
	return attributeRaw
end

local function resolveNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	return valueRaw
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

function AttributeCache.new(): AttributeCache
	local self = setmetatable({
		records = {} :: { [Instance]: InstanceRecord },
		instanceDirtySet = {} :: { [Instance]: boolean },
		dirtyInstances = {} :: { Instance },
		timedModifiers = {} :: { { instance: Instance, attribute: string, modifierId: string, expiresAt: number } },
		now = 0,
		nextBindOrder = 0,
	}, AttributeCache)
	return self
end

function AttributeCache._getListenerSignal(self: AttributeCache, record: InstanceRecord, attribute: string): AttributeChangedSignal
	local signal = record.listenerSignals[attribute]
	if signal ~= nil then
		return signal
	end
	signal = Signal.new() :: AttributeChangedSignal
	record.listenerSignals[attribute] = signal
	return signal
end

function AttributeCache._getRecord(self: AttributeCache, instance: Instance): InstanceRecord?
	return self.records[instance]
end

function AttributeCache._registerDirtyInstance(self: AttributeCache, instance: Instance)
	if self.instanceDirtySet[instance] then
		return
	end
	self.instanceDirtySet[instance] = true
	self.dirtyInstances[#self.dirtyInstances + 1] = instance
end

function AttributeCache._notifyListeners(self: AttributeCache, record: InstanceRecord, instance: Instance, attribute: string, newValue: any, oldValue: any)
	local byAttribute = record.listenerSignals[attribute]
	if byAttribute ~= nil then
		byAttribute:Fire(instance, attribute, newValue, oldValue)
	end
	local wildcard = record.listenerSignals[DEFAULT_GROUP]
	if wildcard ~= nil then
		wildcard:Fire(instance, attribute, newValue, oldValue)
	end
end

function AttributeCache._recordDiff(self: AttributeCache, instance: Instance, record: InstanceRecord, attribute: string, oldValue: any, newValue: any)
	if oldValue == newValue then
		return
	end
	local existing = record.dirty[attribute]
	if existing == nil then
		record.dirty[attribute] = {
			oldValue = oldValue,
			newValue = newValue,
		}
		record.dirtyOrder[#record.dirtyOrder + 1] = attribute
	else
		existing.newValue = newValue
	end
	self:_registerDirtyInstance(instance)
	self:_notifyListeners(record, instance, attribute, newValue, oldValue)
end

function AttributeCache._resolveAttribute(self: AttributeCache, record: InstanceRecord, attribute: string): any
	local baseValue = record.base[attribute]
	local modifierBucket = record.modifiers[attribute]
	if modifierBucket == nil or next(modifierBucket) == nil then
		return baseValue
	end

	local hasNumericOps = false
	local addTotal = 0
	local multiplyTotal = 1
	local overrideValue = nil
	local overridePriority = -1000000

	for _, modifier in modifierBucket do
		if modifier.mode == "Add" then
			if typeof(modifier.value) == "number" then
				hasNumericOps = true
				addTotal += modifier.value
			end
		elseif modifier.mode == "Multiply" then
			if typeof(modifier.value) == "number" then
				hasNumericOps = true
				multiplyTotal *= modifier.value
			end
		elseif modifier.mode == "Override" then
			if modifier.priority >= overridePriority then
				overridePriority = modifier.priority
				overrideValue = modifier.value
			end
		end
	end

	if overrideValue ~= nil then
		return overrideValue
	end

	if hasNumericOps then
		local numericBase = resolveNumber(baseValue, 0)
		return numericBase * multiplyTotal + addTotal
	end

	return baseValue
end

function AttributeCache._applyResolved(self: AttributeCache, instance: Instance, record: InstanceRecord, attribute: string)
	local oldValue = record.cache[attribute]
	local resolved = self:_resolveAttribute(record, attribute)
	record.cache[attribute] = resolved

	local currentValue = instance:GetAttribute(attribute)
	if currentValue ~= resolved then
		record.suppress[attribute] = true
		local ok, err = pcall(function()
			instance:SetAttribute(attribute, resolved)
		end)
		if not ok then
			record.suppress[attribute] = nil
			warn(string.format("[AttributeCache] SetAttribute failed (%s.%s): %s", instance:GetFullName(), attribute, tostring(err)))
		end
	end
	self:_recordDiff(instance, record, attribute, oldValue, resolved)
end

function AttributeCache.bind(self: AttributeCache, instanceRaw: any): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end
	local instance = instanceRaw :: Instance
	if self.records[instance] ~= nil then
		return true
	end

	local attributes = instance:GetAttributes()
	self.nextBindOrder += 1
	local record = {
		cache = table.clone(attributes),
		base = table.clone(attributes),
		modifiers = {},
		dirty = {},
		dirtyOrder = {},
		listenerSignals = {},
		suppress = {},
		connection = nil,
		bindOrder = self.nextBindOrder,
	} :: InstanceRecord

	record.connection = instance.AttributeChanged:Connect(function(attributeName)
		local runtimeRecord = self.records[instance]
		if runtimeRecord == nil then
			return
		end
		local attribute = normalizeAttribute(attributeName)
		if attribute == nil then
			return
		end
		if runtimeRecord.suppress[attribute] then
			runtimeRecord.suppress[attribute] = nil
			return
		end
		local oldValue = runtimeRecord.cache[attribute]
		local nextValue = instance:GetAttribute(attribute)
		runtimeRecord.base[attribute] = nextValue
		if runtimeRecord.modifiers[attribute] ~= nil then
			self:_applyResolved(instance, runtimeRecord, attribute)
			return
		end
		runtimeRecord.cache[attribute] = nextValue
		self:_recordDiff(instance, runtimeRecord, attribute, oldValue, nextValue)
	end)

	self.records[instance] = record
	return true
end

function AttributeCache.unbind(self: AttributeCache, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local record = self.records[instance]
	if record == nil then
		return
	end
	if record.connection ~= nil then
		record.connection:Disconnect()
		record.connection = nil
	end
	for _, signal in record.listenerSignals do
		signal:DisconnectAll()
		signal:Destroy()
	end
	table.clear(record.listenerSignals)
	self.records[instance] = nil
	self.instanceDirtySet[instance] = nil
	for index = #self.dirtyInstances, 1, -1 do
		if self.dirtyInstances[index] == instance then
			table.remove(self.dirtyInstances, index)
			break
		end
	end
end

function AttributeCache.get(self: AttributeCache, instanceRaw: any, attributeRaw: any, defaultValue: any?): any
	if typeof(instanceRaw) ~= "Instance" then
		return defaultValue
	end
	local attribute = normalizeAttribute(attributeRaw)
	if attribute == nil then
		return defaultValue
	end
	self:bind(instanceRaw)
	local record = self.records[instanceRaw]
	if record == nil then
		return defaultValue
	end
	local value = record.cache[attribute]
	if value == nil then
		return defaultValue
	end
	return value
end

function AttributeCache.set(self: AttributeCache, instanceRaw: any, attributeRaw: any, value: any): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end
	local attribute = normalizeAttribute(attributeRaw)
	if attribute == nil then
		return false
	end
	self:bind(instanceRaw)
	local record = self.records[instanceRaw]
	if record == nil then
		return false
	end
	record.base[attribute] = value
	self:_applyResolved(instanceRaw, record, attribute)
	return true
end

function AttributeCache.increment(self: AttributeCache, instanceRaw: any, attributeRaw: any, amountRaw: any): number
	local amount = if typeof(amountRaw) == "number" then amountRaw else 0
	local currentValue = self:get(instanceRaw, attributeRaw, 0)
	local nextValue = resolveNumber(currentValue, 0) + amount
	self:set(instanceRaw, attributeRaw, nextValue)
	return nextValue
end

function AttributeCache.onChanged(self: AttributeCache, instanceRaw: any, attributeRaw: any, listener: ChangeListener): () -> ()
	if typeof(instanceRaw) ~= "Instance" then
		return function() end
	end
	if typeof(listener) ~= "function" then
		return function() end
	end
	self:bind(instanceRaw)
	local record = self.records[instanceRaw]
	if record == nil then
		return function() end
	end

	local attribute = normalizeAttribute(attributeRaw) or DEFAULT_GROUP
	local connection = self:_getListenerSignal(record, attribute):Connect(listener)

	return function()
		connection:Disconnect()
	end
end

function AttributeCache.applyModifier(
	self: AttributeCache,
	instanceRaw: any,
	attributeRaw: any,
	modifierIdRaw: any,
	modeRaw: any,
	value: any,
	priorityRaw: any?,
	durationRaw: any?
): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end
	local attribute = normalizeAttribute(attributeRaw)
	if attribute == nil then
		return false
	end
	if typeof(modifierIdRaw) ~= "string" or modifierIdRaw == "" then
		return false
	end
	local mode = modeRaw :: ModifierMode
	if mode ~= "Add" and mode ~= "Multiply" and mode ~= "Override" then
		return false
	end

	self:bind(instanceRaw)
	local record = self.records[instanceRaw]
	if record == nil then
		return false
	end

	if record.modifiers[attribute] == nil then
		record.modifiers[attribute] = {}
	end
	local modifierBucket = record.modifiers[attribute]
	local duration = if typeof(durationRaw) == "number" and durationRaw > 0 then durationRaw else nil
	local expiresAt = if duration ~= nil then self.now + duration else nil

	modifierBucket[modifierIdRaw] = {
		id = modifierIdRaw,
		mode = mode,
		value = value,
		priority = clampInteger(priorityRaw, 0, -1000000, 1000000),
		expiresAt = expiresAt,
	}

	if expiresAt ~= nil then
		self.timedModifiers[#self.timedModifiers + 1] = {
			instance = instanceRaw,
			attribute = attribute,
			modifierId = modifierIdRaw,
			expiresAt = expiresAt,
		}
	end

	self:_applyResolved(instanceRaw, record, attribute)
	return true
end

function AttributeCache.removeModifier(self: AttributeCache, instanceRaw: any, attributeRaw: any, modifierIdRaw: any): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end
	local attribute = normalizeAttribute(attributeRaw)
	if attribute == nil then
		return false
	end
	if typeof(modifierIdRaw) ~= "string" then
		return false
	end

	local record = self.records[instanceRaw]
	if record == nil then
		return false
	end
	local modifierBucket = record.modifiers[attribute]
	if modifierBucket == nil or modifierBucket[modifierIdRaw] == nil then
		return false
	end
	modifierBucket[modifierIdRaw] = nil
	if next(modifierBucket) == nil then
		record.modifiers[attribute] = nil
	end
	self:_applyResolved(instanceRaw, record, attribute)
	return true
end

function AttributeCache.clearModifiers(self: AttributeCache, instanceRaw: any, attributeRaw: any?)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local record = self.records[instanceRaw]
	if record == nil then
		return
	end
	if attributeRaw == nil then
		local attributes = {}
		for attribute in record.modifiers do
			attributes[#attributes + 1] = attribute
		end
		for _, attribute in attributes do
			record.modifiers[attribute] = nil
			self:_applyResolved(instanceRaw, record, attribute)
		end
		return
	end
	local attribute = normalizeAttribute(attributeRaw)
	if attribute == nil then
		return
	end
	if record.modifiers[attribute] ~= nil then
		record.modifiers[attribute] = nil
		self:_applyResolved(instanceRaw, record, attribute)
	end
end

function AttributeCache.update(self: AttributeCache, dtRaw: any)
	local dt = if typeof(dtRaw) == "number" and dtRaw > 0 then dtRaw else 0
	if dt <= 0 then
		return
	end
	self.now += dt

	for index = #self.timedModifiers, 1, -1 do
		local timer = self.timedModifiers[index]
		if timer.expiresAt > self.now then
			continue
		end
		local record = self.records[timer.instance]
		if record ~= nil then
			local modifierBucket = record.modifiers[timer.attribute]
			if modifierBucket ~= nil then
				local modifier = modifierBucket[timer.modifierId]
				if modifier ~= nil and modifier.expiresAt == timer.expiresAt then
					modifierBucket[timer.modifierId] = nil
					if next(modifierBucket) == nil then
						record.modifiers[timer.attribute] = nil
					end
					self:_applyResolved(timer.instance, record, timer.attribute)
				end
			end
		end
		table.remove(self.timedModifiers, index)
	end
end

function AttributeCache.consumeDiffs(self: AttributeCache, maxRecordsRaw: any?): { DiffRecord }
	local maxRecords = if maxRecordsRaw ~= nil then clampInteger(maxRecordsRaw, 1000000, 1, 1000000) else 1000000
	local out = {}
	local remainingDirtyInstances = {}

	for dirtyIndex = 1, #self.dirtyInstances do
		local instance = self.dirtyInstances[dirtyIndex]
		local record = self.records[instance]
		if record == nil then
			self.instanceDirtySet[instance] = nil
			continue
		end
		local nextDirtyOrder = {}
		for attrIndex = 1, #record.dirtyOrder do
			local attribute = record.dirtyOrder[attrIndex]
			local diff = record.dirty[attribute]
			if diff == nil then
				continue
			end
			if #out < maxRecords then
				out[#out + 1] = {
					instance = instance,
					attribute = attribute,
					oldValue = diff.oldValue,
					newValue = diff.newValue,
					timestamp = self.now,
				}
				record.dirty[attribute] = nil
			else
				nextDirtyOrder[#nextDirtyOrder + 1] = attribute
			end
		end

		if #nextDirtyOrder > 0 then
			record.dirtyOrder = nextDirtyOrder
			self.instanceDirtySet[instance] = true
			remainingDirtyInstances[#remainingDirtyInstances + 1] = instance
		else
			clearArray(record.dirtyOrder)
			self.instanceDirtySet[instance] = nil
		end
	end

	self.dirtyInstances = remainingDirtyInstances
	return out
end

function AttributeCache.buildReplicationBatch(self: AttributeCache, maxAttributesRaw: any?): { ReplicationChange }
	local diffs = self:consumeDiffs(maxAttributesRaw)
	if #diffs == 0 then
		return {}
	end
	local grouped = {} :: { [Instance]: ReplicationChange }
	local order = {} :: { Instance }
	for index = 1, #diffs do
		local diff = diffs[index]
		local entry = grouped[diff.instance]
		if entry == nil then
			entry = {
				instance = diff.instance,
				attributes = {},
			}
			grouped[diff.instance] = entry
			order[#order + 1] = diff.instance
		end
		entry.attributes[diff.attribute] = diff.newValue
	end

	local out = table.create(#order)
	for index = 1, #order do
		out[index] = grouped[order[index]]
	end
	return out
end

function AttributeCache.serializeReplicationBatch(self: AttributeCache, batchRaw: any): string
	if typeof(batchRaw) ~= "table" then
		return Codec.serializeCompressed({})
	end

	local normalized = {}
	for _, entry in batchRaw do
		if typeof(entry) ~= "table" or typeof(entry.instance) ~= "Instance" or typeof(entry.attributes) ~= "table" then
			continue
		end
		normalized[#normalized + 1] = {
			instancePath = entry.instance:GetFullName(),
			attributes = entry.attributes,
		}
	end

	return Codec.serializeCompressed(normalized)
end

function AttributeCache.deserializeReplicationBatch(self: AttributeCache, payloadRaw: any): { any }
	if typeof(payloadRaw) ~= "string" then
		return {}
	end
	local ok, decoded = pcall(function()
		return Codec.deserializeCompressed(payloadRaw)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return {}
	end
	return decoded
end

function AttributeCache.destroy(self: AttributeCache)
	local instances = {}
	for instance in self.records do
		instances[#instances + 1] = instance
	end
	for _, instance in instances do
		self:unbind(instance)
	end
	table.clear(self.records)
	table.clear(self.instanceDirtySet)
	clearArray(self.dirtyInstances)
	clearArray(self.timedModifiers)
	self.now = 0
end

return AttributeCache
