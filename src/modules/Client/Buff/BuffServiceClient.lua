local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local BuffConstants = require("BuffConstants")
local BuffHandlerClient = require("BuffHandlerClient")
local Maid = require("Maid")
local Promise = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local Rx = require("Rx")
local Signal = require("Signal")
local buffUtils = require("buffUtils")

local BuffServiceClient = {}
BuffServiceClient.ServiceName = BuffConstants.CLIENT_SERVICE_NAME

export type BuffRecord = buffUtils.BuffRecord

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> number,
	Destroy: (self: MaidClass) -> (),
	[any]: any,
}

local function createRejectedPromise(message: string)
	return Promise.rejected(message)
end

local function copyOverrides(overridesRaw: any?): { [string]: any }
	local overrides = {}
	if typeof(overridesRaw) == "table" then
		for key, value in overridesRaw :: { [string]: any } do
			overrides[key] = value
		end
	end
	return overrides
end

local function getSnapshotRecords(recordsRaw: any): { any }
	if typeof(recordsRaw) ~= "table" then
		return {}
	end

	local records = recordsRaw :: { [any]: any }
	if typeof(records.records) == "table" then
		records = records.records
	elseif typeof(records.active) == "table" then
		records = records.active
	end

	local output = {}
	for _, record in records do
		if typeof(record) == "table" then
			table.insert(output, record)
		end
	end

	return output
end

local function buildClientRecord(recordRaw: any): BuffRecord
	local record = buffUtils.ApplyOverrides(recordRaw, nil)
	local remainingSeconds = if typeof(recordRaw) == "table" then recordRaw.remainingSeconds else nil

	if typeof(remainingSeconds) == "number" then
		record.appliedAt = os.clock()
		record.expiresAt = record.appliedAt + remainingSeconds
		if record.duration <= 0 then
			record.duration = remainingSeconds
		end
		record.remainingSeconds = nil
	elseif record.duration > 0 then
		record.appliedAt = os.clock()
		record.expiresAt = record.appliedAt + record.duration
	end

	return record
end

local function decodeReplicatedRecords(valueRaw: any): { any }
	if typeof(valueRaw) ~= "string" or valueRaw == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(valueRaw)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return {}
	end

	return decoded :: { any }
end

function BuffServiceClient.Init(self: BuffServiceClient, serviceBag: any)
	assert(not self._serviceBag, "Already initialized")

	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._handler = BuffHandlerClient.new()
	self._localPlayer = Players.LocalPlayer

	self.ActiveChanged = Signal.new()
	self.DefinitionChanged = Signal.new()
	self.BuffAdded = Signal.new()
	self.BuffChanged = Signal.new()
	self.BuffRemoved = Signal.new()

	self._maid:GiveTask(self._handler)
	self._maid:GiveTask(self.ActiveChanged)
	self._maid:GiveTask(self.DefinitionChanged)
	self._maid:GiveTask(self.BuffAdded)
	self._maid:GiveTask(self.BuffChanged)
	self._maid:GiveTask(self.BuffRemoved)

	self._maid:GiveTask(
		Rx.fromSignal(self._handler.activeChanged):Subscribe(function(records: { BuffRecord }, context: string)
			self.ActiveChanged:Fire(records, context)
		end)
	)
	self._maid:GiveTask(
		Rx.fromSignal(self._handler.definitionChanged):Subscribe(function(records: { BuffRecord }, context: string)
			self.DefinitionChanged:Fire(records, context)
		end)
	)
	self._maid:GiveTask(Rx.fromSignal(self._handler.buffAdded):Subscribe(function(record: BuffRecord)
		self.BuffAdded:Fire(record)
	end))
	self._maid:GiveTask(Rx.fromSignal(self._handler.buffChanged):Subscribe(function(record: BuffRecord)
		self.BuffChanged:Fire(record)
	end))
	self._maid:GiveTask(Rx.fromSignal(self._handler.buffRemoved):Subscribe(function(record: BuffRecord, reason: string)
		self.BuffRemoved:Fire(record, reason)
	end))

	if self._localPlayer ~= nil then
		self:ApplySnapshot(self:ReadReplicatedSnapshot())
		self._maid:GiveTask(
			self._localPlayer
				:GetAttributeChangedSignal(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE)
				:Connect(function()
					self:ApplySnapshot(self:ReadReplicatedSnapshot())
				end)
		)
	end
end

function BuffServiceClient.Start(_self: BuffServiceClient) end

function BuffServiceClient.GetHandler(self: BuffServiceClient): any
	return self._handler
end

function BuffServiceClient.ReadReplicatedSnapshot(self: BuffServiceClient): { any }
	if self._localPlayer == nil then
		return {}
	end

	return decodeReplicatedRecords(self._localPlayer:GetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE))
end

function BuffServiceClient.ApplySnapshot(self: BuffServiceClient, recordsRaw: any): number
	local records = getSnapshotRecords(recordsRaw)
	local applied = 0

	self._handler:Clear()
	for _, recordRaw in records do
		local remainingSeconds = if typeof(recordRaw) == "table" then recordRaw.remainingSeconds else nil
		if typeof(remainingSeconds) == "number" and remainingSeconds <= 0 then
			continue
		end

		self._handler.active:AddRecord(buildClientRecord(recordRaw))
		applied += 1
	end

	return applied
end

function BuffServiceClient.ApplyState(self: BuffServiceClient, recordsRaw: any): number
	return self:ApplySnapshot(recordsRaw)
end

function BuffServiceClient.ApplyBuff(self: BuffServiceClient, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self._handler:ApplyBuff(nameRaw, overridesRaw)
end

function BuffServiceClient.ApplyDebuff(self: BuffServiceClient, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self._handler:ApplyDebuff(nameRaw, overridesRaw)
end

function BuffServiceClient.PromiseApplyBuff(self: BuffServiceClient, nameRaw: any, overridesRaw: any?)
	local record = self:ApplyBuff(nameRaw, overridesRaw)
	if record == nil then
		return createRejectedPromise("buff could not be applied")
	end
	return fulfilledPromise(record)
end

function BuffServiceClient.PromiseApplyDebuff(self: BuffServiceClient, nameRaw: any, overridesRaw: any?)
	local record = self:ApplyDebuff(nameRaw, overridesRaw)
	if record == nil then
		return createRejectedPromise("debuff could not be applied")
	end
	return fulfilledPromise(record)
end

function BuffServiceClient.AddBuff(
	self: BuffServiceClient,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	return self._handler:AddBuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffServiceClient.AddDebuff(
	self: BuffServiceClient,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	return self._handler:AddDebuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffServiceClient.ApplyRecord(self: BuffServiceClient, recordRaw: any, overridesRaw: any?): BuffRecord?
	if typeof(recordRaw) ~= "table" then
		return nil
	end

	local overrides = copyOverrides(overridesRaw)
	if overrides.appliedAt == nil then
		overrides.appliedAt = os.clock()
	end

	return self._handler.active:AddRecord(recordRaw, nil, overrides)
end

function BuffServiceClient.Remove(self: BuffServiceClient, idOrNameRaw: any, reasonRaw: any?, kindRaw: any?): boolean
	return self._handler:Remove(idOrNameRaw, reasonRaw, kindRaw)
end

function BuffServiceClient.PromiseRemove(self: BuffServiceClient, idOrNameRaw: any, reasonRaw: any?, kindRaw: any?)
	if not self:Remove(idOrNameRaw, reasonRaw, kindRaw) then
		return createRejectedPromise("buff could not be removed")
	end
	return fulfilledPromise(true)
end

function BuffServiceClient.Clear(self: BuffServiceClient, kindRaw: any?): number
	return self._handler:Clear(kindRaw)
end

function BuffServiceClient.GetActive(self: BuffServiceClient, kindRaw: any?): { BuffRecord }
	return self._handler:GetActive(kindRaw)
end

function BuffServiceClient.GetDefinitions(self: BuffServiceClient, kindRaw: any?): { BuffRecord }
	return self._handler:GetDefinitions(kindRaw)
end

function BuffServiceClient.GetRemainingSeconds(self: BuffServiceClient, idOrNameRaw: any, kindRaw: any?): number?
	return self._handler:GetRemainingSeconds(idOrNameRaw, kindRaw)
end

function BuffServiceClient.ObserveActive(self: BuffServiceClient)
	return self._handler.active:ObserveRecords()
end

function BuffServiceClient.Destroy(self: BuffServiceClient)
	if self._maid ~= nil then
		self._maid:Destroy()
	end

	self._serviceBag = nil
end
type BuffServiceClient = typeof(BuffServiceClient) & {
	_serviceBag: any,
	_maid: MaidClass,
	_handler: any,
	_localPlayer: Player?,
	ActiveChanged: SignalObject,
	DefinitionChanged: SignalObject,
	BuffAdded: SignalObject,
	BuffChanged: SignalObject,
	BuffRemoved: SignalObject,
}

return BuffServiceClient :: BuffServiceClient
