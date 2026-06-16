local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuffConstants = {}

BuffConstants.KIND_BUFF = "Buff"
BuffConstants.KIND_DEBUFF = "Debuff"

BuffConstants.DEFAULT_DURATION_SECONDS = 0
BuffConstants.MIN_DURATION_SECONDS = 0
BuffConstants.MAX_DURATION_SECONDS = 3600
BuffConstants.DEFAULT_STACKS = 1
BuffConstants.DEFAULT_MAX_STACKS = 1

BuffConstants.STACK_MODE_REFRESH = "Refresh"
BuffConstants.STACK_MODE_EXTEND = "Extend"
BuffConstants.STACK_MODE_IGNORE = "Ignore"

BuffConstants.DEFAULT_DESCRIPTION = ""
BuffConstants.DEFAULT_AFFECTS = ""
BuffConstants.UNKNOWN_BUFF_NAME = "UnknownBuff"

BuffConstants.ACTIVE_CHANGED_CONTEXT_ADDED = "Added"
BuffConstants.ACTIVE_CHANGED_CONTEXT_CHANGED = "Changed"
BuffConstants.ACTIVE_CHANGED_CONTEXT_REMOVED = "Removed"
BuffConstants.ACTIVE_CHANGED_CONTEXT_CLEARED = "Cleared"
BuffConstants.REMOVE_REASON_EXPIRED = "Expired"
BuffConstants.REMOVE_REASON_REMOVED = "Removed"
BuffConstants.REMOVE_REASON_CLEARED = "Cleared"

BuffConstants.DEFINITION_FOLDER_BUFFS = "Buffs"
BuffConstants.DEFINITION_FOLDER_DEBUFFS = "Debuffs"

BuffConstants.SERVER_SERVICE_NAME = "BuffService"
BuffConstants.CLIENT_SERVICE_NAME = "BuffServiceClient"
BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE = "BuffActiveRecords"

BuffConstants.DEFAULT_AREA_RADIUS = 12
BuffConstants.MIN_AREA_RADIUS = 0
BuffConstants.MAX_AREA_RADIUS = 1024
BuffConstants.AREA_SCAN_INTERVAL_SECONDS = 0.5

local KINDS = {
	BuffConstants.KIND_BUFF,
	BuffConstants.KIND_DEBUFF,
}

local STACK_MODES = {
	[BuffConstants.STACK_MODE_REFRESH] = true,
	[BuffConstants.STACK_MODE_EXTEND] = true,
	[BuffConstants.STACK_MODE_IGNORE] = true,
}

function BuffConstants.CloneKinds(): { string }
	return Table.copy(KINDS)
end

function BuffConstants.IsKind(valueRaw: any): boolean
	return valueRaw == BuffConstants.KIND_BUFF or valueRaw == BuffConstants.KIND_DEBUFF
end

function BuffConstants.IsStackMode(valueRaw: any): boolean
	return STACK_MODES[valueRaw] == true
end

BuffConstants.cloneKinds = BuffConstants.CloneKinds
BuffConstants.isKind = BuffConstants.IsKind
BuffConstants.isStackMode = BuffConstants.IsStackMode

return BuffConstants
