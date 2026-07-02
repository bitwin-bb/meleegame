local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")
local Signal = require("Signal")
local Table = require("Table")
local ValueObject = require("ValueObject")

local BuffConstants = require("BuffConstants")
local buffUtils = require("BuffUtils")

local BuffShared = setmetatable({}, BaseObject)
BuffShared.ClassName = "BuffShared"
BuffShared.__index = BuffShared

export type BuffRecord = buffUtils.BuffRecord

local function GetConstructorOptions(serviceBagOrOptionsRaw: any, optionsRaw: any?): (any?, { [string]: any })
	if typeof(optionsRaw) == "table" then
		return serviceBagOrOptionsRaw, optionsRaw :: { [string]: any }
	end

	if typeof(serviceBagOrOptionsRaw) == "table" and serviceBagOrOptionsRaw.definitionOnly ~= nil then
		return nil, serviceBagOrOptionsRaw :: { [string]: any }
	end

	return serviceBagOrOptionsRaw, {}
end

function BuffShared.new(serviceBagOrOptionsRaw: any?, optionsRaw: any?): BuffShared
	local serviceBag, options = GetConstructorOptions(serviceBagOrOptionsRaw, optionsRaw)
	local self = setmetatable(BaseObject.new(), BuffShared)

	self._serviceBag = serviceBag
	self._definitionOnly = options.definitionOnly == true
	self._recordsById = {}
	self._orderedIds = {}
	self._expireTokensById = {}

	self.RecordAdded = Signal.new()
	self.RecordChanged = Signal.new()
	self.RecordRemoved = Signal.new()
	self.RecordsChanged = Signal.new()
	self.Records = ValueObject.new({})

	self._maid:GiveTask(self.RecordAdded)
	self._maid:GiveTask(self.RecordChanged)
	self._maid:GiveTask(self.RecordRemoved)
	self._maid:GiveTask(self.RecordsChanged)
	self._maid:GiveTask(self.Records)

	return self
end

function BuffShared.New(serviceBagOrOptionsRaw: any?, optionsRaw: any?): BuffShared
	return BuffShared.new(serviceBagOrOptionsRaw, optionsRaw)
end

function BuffShared._pushRecordsChanged(self: BuffShared, context: string)
	local records = self:GetRecords()
	self.Records:SetValue(records, context)
	self.RecordsChanged:Fire(records, context)
end

function BuffShared._findId(self: BuffShared, idOrNameRaw: any, kindRaw: any?): string?
	local idOrName = buffUtils.Trim(idOrNameRaw)
	if idOrName == "" then
		return nil
	end

	if self._recordsById[idOrName] ~= nil then
		return idOrName
	end

	local kind = if kindRaw ~= nil then buffUtils.CoerceKind(kindRaw) else nil
	local lowerName = string.lower(idOrName)
	for _, recordId in self._orderedIds do
		local record = self._recordsById[recordId]
		if record ~= nil and string.lower(record.name) == lowerName and (kind == nil or record.kind == kind) then
			return recordId
		end
	end

	return nil
end

function BuffShared._scheduleExpiry(self: BuffShared, record: BuffRecord)
	local timerKey = `Expire:{record.id}`
	self._maid[timerKey] = nil
	self._expireTokensById[record.id] = nil

	if self._definitionOnly or record.duration <= 0 or record.expiresAt == nil then
		return
	end

	local token = {}
	self._expireTokensById[record.id] = token
	self._maid[timerKey] = task.delay(record.duration, function()
		if self._expireTokensById[record.id] ~= token then
			return
		end

		self:Remove(record.id, BuffConstants.REMOVE_REASON_EXPIRED)
	end)
end

function BuffShared._storeRecord(self: BuffShared, recordRaw: BuffRecord): BuffRecord
	local existing = self._recordsById[recordRaw.id]
	local isNew = existing == nil
	local record = if existing ~= nil then buffUtils.MergeRecord(existing, recordRaw) else buffUtils.CloneRecord(recordRaw)
	if self._definitionOnly then
		record.appliedAt = 0
		record.expiresAt = nil
	end

	self._recordsById[record.id] = record
	if isNew then
		table.insert(self._orderedIds, record.id)
	end

	self:_scheduleExpiry(record)

	local clone = buffUtils.CloneRecord(record)
	if isNew then
		self.RecordAdded:Fire(clone)
		self:_pushRecordsChanged(BuffConstants.ACTIVE_CHANGED_CONTEXT_ADDED)
	else
		self.RecordChanged:Fire(clone)
		self:_pushRecordsChanged(BuffConstants.ACTIVE_CHANGED_CONTEXT_CHANGED)
	end

	return clone
end

function BuffShared.AddRecord(self: BuffShared, recordRaw: any, kindFallbackRaw: any?, overridesRaw: any?): BuffRecord
	local record = buffUtils.ApplyOverrides(recordRaw, overridesRaw)
	local source = if typeof(recordRaw) == "table" then recordRaw :: { [string]: any } else {}
	if kindFallbackRaw ~= nil and source.kind == nil and source.type == nil and source.category == nil then
		record.kind = buffUtils.CoerceKind(kindFallbackRaw)
		record.id = buffUtils.CreateId(record.kind, record.name)
	end

	return self:_storeRecord(record)
end

function BuffShared.ApplyRecord(self: BuffShared, recordRaw: any, overridesRaw: any?): BuffRecord
	return self:AddRecord(recordRaw, nil, overridesRaw)
end

function BuffShared.AddBuff(
	self: BuffShared,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	local record = buffUtils.CreateRecord(
		BuffConstants.KIND_BUFF,
		nameRaw,
		durationRaw,
		effectsRaw,
		descriptionRaw,
		affectsRaw,
		optionsRaw
	)
	return self:_storeRecord(record)
end

function BuffShared.AddDebuff(
	self: BuffShared,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	local record = buffUtils.CreateRecord(
		BuffConstants.KIND_DEBUFF,
		nameRaw,
		durationRaw,
		effectsRaw,
		descriptionRaw,
		affectsRaw,
		optionsRaw
	)
	return self:_storeRecord(record)
end

function BuffShared.Remove(self: BuffShared, idOrNameRaw: any, reasonRaw: any?, kindRaw: any?): boolean
	local recordId = self:_findId(idOrNameRaw, kindRaw)
	if recordId == nil then
		return false
	end

	local record = self._recordsById[recordId]
	if record == nil then
		return false
	end

	self._recordsById[recordId] = nil
	self._expireTokensById[recordId] = nil
	self._maid[`Expire:{recordId}`] = nil

	for index, orderedId in self._orderedIds do
		if orderedId == recordId then
			table.remove(self._orderedIds, index)
			break
		end
	end

	local reason = buffUtils.Trim(reasonRaw)
	if reason == "" then
		reason = BuffConstants.REMOVE_REASON_REMOVED
	end

	self.RecordRemoved:Fire(buffUtils.CloneRecord(record), reason)
	self:_pushRecordsChanged(BuffConstants.ACTIVE_CHANGED_CONTEXT_REMOVED)
	return true
end

function BuffShared.Clear(self: BuffShared, kindRaw: any?): number
	local ids = Table.copy(self._orderedIds)
	local removed = 0
	local kind = if kindRaw ~= nil then buffUtils.CoerceKind(kindRaw) else nil

	for _, recordId in ids do
		local record = self._recordsById[recordId]
		if record ~= nil and (kind == nil or record.kind == kind) then
			if self:Remove(recordId, BuffConstants.REMOVE_REASON_CLEARED) then
				removed += 1
			end
		end
	end

	return removed
end

function BuffShared.GetRecord(self: BuffShared, idOrNameRaw: any, kindRaw: any?): BuffRecord?
	local recordId = self:_findId(idOrNameRaw, kindRaw)
	if recordId == nil then
		return nil
	end

	local record = self._recordsById[recordId]
	if record == nil then
		return nil
	end

	return buffUtils.CloneRecord(record)
end

function BuffShared.GetRecords(self: BuffShared, kindRaw: any?): { BuffRecord }
	local kind = if kindRaw ~= nil then buffUtils.CoerceKind(kindRaw) else nil
	local records = {}

	for _, recordId in self._orderedIds do
		local record = self._recordsById[recordId]
		if record ~= nil and (kind == nil or record.kind == kind) then
			table.insert(records, buffUtils.CloneRecord(record))
		end
	end

	return records
end

function BuffShared.HasRecord(self: BuffShared, idOrNameRaw: any, kindRaw: any?): boolean
	return self:_findId(idOrNameRaw, kindRaw) ~= nil
end

function BuffShared.GetRemainingSeconds(self: BuffShared, idOrNameRaw: any, kindRaw: any?): number?
	local recordId = self:_findId(idOrNameRaw, kindRaw)
	if recordId == nil then
		return nil
	end

	return buffUtils.GetRemainingSeconds(self._recordsById[recordId])
end

function BuffShared.ObserveRecords(self: BuffShared)
	return self.Records:Observe()
end

function BuffShared.Destroy(self: BuffShared)
	BaseObject.Destroy(self)
end













type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type ValueObjectClass = {
	SetValue: (self: ValueObjectClass, value: any, ...any) -> (() -> ()),
	GetValue: (self: ValueObjectClass) -> any,
	Observe: (self: ValueObjectClass) -> any,
	Destroy: (self: ValueObjectClass) -> (),
}

type BuffShared = typeof(setmetatable(
	{} :: {
		_serviceBag: any?,
		_definitionOnly: boolean,
		_recordsById: { [string]: BuffRecord },
		_orderedIds: { string },
		_expireTokensById: { [string]: any },
		RecordAdded: SignalObject,
		RecordChanged: SignalObject,
		RecordRemoved: SignalObject,
		RecordsChanged: SignalObject,
		Records: ValueObjectClass,
	},
	BuffShared
))

return BuffShared :: any
