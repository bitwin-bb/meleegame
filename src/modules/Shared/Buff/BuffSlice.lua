local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffConstants = require("BuffConstants")
local Charm = require(ReplicatedStorage.Packages.Charm)
local buffUtils = require("buffUtils")

export type BuffRecord = buffUtils.BuffRecord

export type BuffState = {
	records: { BuffRecord },
	updatedAt: number,
	source: string?,
}

local function createDefaultState(): BuffState
	return {
		records = {},
		updatedAt = 0,
		source = nil,
	}
end

local function getTableSource(recordsRaw: any): { [any]: any }?
	if typeof(recordsRaw) ~= "table" then
		return nil
	end

	local source = recordsRaw :: { [any]: any }
	if typeof(source.records) == "table" then
		return source.records :: { [any]: any }
	end
	if typeof(source.active) == "table" then
		return source.active :: { [any]: any }
	end
	if typeof(source.name) == "string" or typeof(source.id) == "string" then
		return {
			source,
		}
	end

	return source
end

local function cloneState(state: BuffState): BuffState
	return {
		records = buffUtils.cloneRecords(state.records),
		updatedAt = state.updatedAt,
		source = state.source,
	}
end

local function sanitizeRecord(recordRaw: any): BuffRecord?
	if typeof(recordRaw) ~= "table" then
		return nil
	end

	local source = recordRaw :: { [string]: any }
	local remainingSeconds = source.remainingSeconds
	local record = buffUtils.applyOverrides(recordRaw, nil)

	if typeof(remainingSeconds) == "number" then
		if remainingSeconds <= 0 then
			return nil
		end

		record.appliedAt = os.clock()
		record.expiresAt = record.appliedAt + remainingSeconds
		if record.duration <= 0 then
			record.duration = remainingSeconds
		end
		record.remainingSeconds = nil
	elseif buffUtils.isExpired(record) then
		return nil
	end

	return record
end

local function sanitizeRecords(recordsRaw: any): { BuffRecord }
	local source = getTableSource(recordsRaw)
	if source == nil then
		return {}
	end

	local records = {}
	for _, recordRaw in source do
		local record = sanitizeRecord(recordRaw)
		if record ~= nil then
			records[#records + 1] = record
		end
	end

	return records
end

local function sanitizeState(stateRaw: any, fallbackState: BuffState?): BuffState
	local sourceTable = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {}
	local updatedAt = sourceTable.updatedAt
	local source = sourceTable.source

	if typeof(updatedAt) ~= "number" then
		updatedAt = os.clock()
	end
	if typeof(source) ~= "string" or source == "" then
		source = if fallbackState ~= nil then fallbackState.source else nil
	end

	return {
		records = sanitizeRecords(stateRaw),
		updatedAt = updatedAt,
		source = source,
	}
end

local function filterActiveRecords(records: { BuffRecord }): { BuffRecord }
	local activeRecords = {}
	for _, record in records do
		if record.hidden ~= true and not buffUtils.isExpired(record) then
			activeRecords[#activeRecords + 1] = buffUtils.cloneRecord(record)
		end
	end
	return activeRecords
end

local function filterRecordsByKind(records: { BuffRecord }, kind: string): { BuffRecord }
	local filtered = {}
	for _, record in records do
		if record.kind == kind then
			filtered[#filtered + 1] = buffUtils.cloneRecord(record)
		end
	end
	return filtered
end

local buffStateAtom: Charm.Atom<BuffState> = Charm.atom(createDefaultState())
local buffReadyAtom: Charm.Atom<boolean> = Charm.atom(false)

local recordsAtom: Charm.Selector<{ BuffRecord }> = Charm.computed(function(): { BuffRecord }
	return buffUtils.cloneRecords(buffStateAtom().records)
end)

local activeRecordsAtom: Charm.Selector<{ BuffRecord }> = Charm.computed(function(): { BuffRecord }
	return filterActiveRecords(buffStateAtom().records)
end)

local buffsAtom: Charm.Selector<{ BuffRecord }> = Charm.computed(function(): { BuffRecord }
	return filterRecordsByKind(activeRecordsAtom(), BuffConstants.KIND_BUFF)
end)

local debuffsAtom: Charm.Selector<{ BuffRecord }> = Charm.computed(function(): { BuffRecord }
	return filterRecordsByKind(activeRecordsAtom(), BuffConstants.KIND_DEBUFF)
end)

local recordCountAtom: Charm.Selector<number> = Charm.computed(function(): number
	return #activeRecordsAtom()
end)

local function getBuffState(): BuffState
	return cloneState(buffStateAtom())
end

local function getRecords(): { BuffRecord }
	return recordsAtom()
end

local function getActiveRecords(): { BuffRecord }
	return activeRecordsAtom()
end

local function setBuffState(stateRaw: any): BuffState
	local nextState = sanitizeState(stateRaw, buffStateAtom())
	buffStateAtom(nextState)
	return cloneState(nextState)
end

local function setBuffRecords(recordsRaw: any, sourceRaw: any?): BuffState
	local nextState: BuffState = {
		records = sanitizeRecords(recordsRaw),
		updatedAt = os.clock(),
		source = if typeof(sourceRaw) == "string" and sourceRaw ~= "" then sourceRaw else nil,
	}
	buffStateAtom(nextState)
	return cloneState(nextState)
end

local function clearBuffRecords(): BuffState
	local nextState = createDefaultState()
	nextState.updatedAt = os.clock()
	buffStateAtom(nextState)
	return cloneState(nextState)
end

local function isBuffReady(): boolean
	return buffReadyAtom()
end

local function setBuffReady(isReadyRaw: any): boolean
	local nextReady = isReadyRaw == true
	buffReadyAtom(nextReady)
	return nextReady
end

return {
	buffStateAtom = buffStateAtom,
	buffReadyAtom = buffReadyAtom,
	recordsAtom = recordsAtom,
	activeRecordsAtom = activeRecordsAtom,
	buffsAtom = buffsAtom,
	debuffsAtom = debuffsAtom,
	recordCountAtom = recordCountAtom,
	createDefaultState = createDefaultState,
	sanitizeRecords = sanitizeRecords,
	sanitizeState = sanitizeState,
	getBuffState = getBuffState,
	getRecords = getRecords,
	getActiveRecords = getActiveRecords,
	setBuffState = setBuffState,
	setBuffRecords = setBuffRecords,
	clearBuffRecords = clearBuffRecords,
	isBuffReady = isBuffReady,
	setBuffReady = setBuffReady,
}
