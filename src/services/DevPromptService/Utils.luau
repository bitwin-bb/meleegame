--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)

type PlayerRoleSnapshot = Role.PlayerRoleSnapshot
type RoleId = Role.RoleId

export type ConsoleEntryKind = "system" | "info" | "success" | "warning" | "error" | "command"

export type ConsoleEntry = {
	id: string,
	kind: ConsoleEntryKind,
	text: string,
	timestamp: number,
	userId: number?,
	userName: string?,
	roleId: RoleId?,
}

export type DevPromptState = {
	ownerUserId: number?,
	ownerName: string,
	localRoleId: RoleId,
	canUseCommands: boolean,
	playerRoles: { [string]: PlayerRoleSnapshot },
	entries: { ConsoleEntry },
	isOpen: boolean,
	commandPrefix: string,
	maxEntries: number,
}

local DevPromptServiceUtils = {}

DevPromptServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
DevPromptServiceUtils.NETWORK_METHOD_SUBMIT_COMMAND = "submitCommand"
DevPromptServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
DevPromptServiceUtils.CLIENT_METHOD_RECEIVE_ENTRIES = "receiveEntries"

DevPromptServiceUtils.ROLE_ATTRIBUTE = "DevPromptRoleId"
DevPromptServiceUtils.CAN_USE_COMMANDS_ATTRIBUTE = "DevPromptCanUseCommands"
DevPromptServiceUtils.GODMODE_ATTRIBUTE = "DevPromptGodmode"
DevPromptServiceUtils.FLY_ATTRIBUTE = "DevPromptFlyEnabled"
DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE = "DevPromptFlySpeed"

DevPromptServiceUtils.DEFAULT_COMMAND_PREFIX = ";"
DevPromptServiceUtils.DEFAULT_MAX_ENTRIES = 120
DevPromptServiceUtils.DEFAULT_TOGGLE_KEYCODE_NAME = "F2"
DevPromptServiceUtils.DEFAULT_FLY_SPEED = 72
DevPromptServiceUtils.MIN_FLY_SPEED = 16
DevPromptServiceUtils.MAX_FLY_SPEED = 220

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then math.floor(valueRaw) else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

function DevPromptServiceUtils.trim(valueRaw: any): string
	return trim(valueRaw)
end

function DevPromptServiceUtils.sanitizeUserId(userIdRaw: any): number?
	if typeof(userIdRaw) ~= "number" or userIdRaw ~= userIdRaw then
		return nil
	end
	local userId = math.floor(userIdRaw)
	if userId <= 0 then
		return nil
	end
	return userId
end

function DevPromptServiceUtils.clonePlayerRoleSnapshot(snapshotRaw: any): PlayerRoleSnapshot
	local source = if typeof(snapshotRaw) == "table" then snapshotRaw else {}
	local roleId = Role.getDefinition((source :: any).roleId).id
	local userId = DevPromptServiceUtils.sanitizeUserId((source :: any).userId) or 0
	local userName = trim((source :: any).userName)
	local displayName = trim((source :: any).displayName)
	if userName == "" then
		userName = tostring(userId)
	end
	if displayName == "" then
		displayName = userName
	end
	return {
		userId = userId,
		userName = userName,
		displayName = displayName,
		roleId = roleId,
		roleName = if trim((source :: any).roleName) ~= ""
			then trim((source :: any).roleName)
			else Role.getDefinition(roleId).roleName,
		tagText = if trim((source :: any).tagText) ~= ""
			then trim((source :: any).tagText)
			else Role.getTagText(roleId),
		priority = sanitizeInteger((source :: any).priority, Role.getPriority(roleId), 0, 10000),
		canUseCommands = sanitizeBoolean((source :: any).canUseCommands, Role.canUseCommands(roleId)),
	}
end

function DevPromptServiceUtils.sanitizePlayerRoles(roleMapRaw: any): { [string]: PlayerRoleSnapshot }
	local output = {}
	if typeof(roleMapRaw) ~= "table" then
		return output
	end

	for key, value in roleMapRaw do
		local stringKey = if typeof(key) == "string" then key else tostring(key)
		output[stringKey] = DevPromptServiceUtils.clonePlayerRoleSnapshot(value)
	end
	return output
end

function DevPromptServiceUtils.createConsoleEntry(
	kindRaw: any,
	textRaw: any,
	optionsRaw: any?
): ConsoleEntry
	local kind = if kindRaw == "info"
		or kindRaw == "success"
		or kindRaw == "warning"
		or kindRaw == "error"
		or kindRaw == "command"
		then kindRaw
		else if kindRaw == "system" then "system" else "info"
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local timestampDefault = os.clock()
	local roleId = Role.getDefinition((options :: any).roleId).id
	local userId = DevPromptServiceUtils.sanitizeUserId((options :: any).userId)
	local userName = trim((options :: any).userName)

	return {
		id = trim((options :: any).id) ~= "" and trim((options :: any).id)
			or ("%s_%d_%d"):format(kind, math.floor(timestampDefault * 1000), math.random(1000, 999999)),
		kind = kind,
		text = if typeof(textRaw) == "string" then textRaw else tostring(textRaw),
		timestamp = sanitizeNumber((options :: any).timestamp, timestampDefault, 0, nil),
		userId = userId,
		userName = if userName ~= "" then userName else nil,
		roleId = if roleId ~= "Member" or (options :: any).roleId == "Member" then roleId else nil,
	}
end

function DevPromptServiceUtils.cloneConsoleEntry(entryRaw: any): ConsoleEntry
	local fallback = DevPromptServiceUtils.createConsoleEntry("info", "")
	local source = if typeof(entryRaw) == "table" then entryRaw else fallback
	local roleIdRaw = (source :: any).roleId
	local roleId = if roleIdRaw == nil then nil else Role.getDefinition(roleIdRaw).id
	return {
		id = trim((source :: any).id) ~= "" and trim((source :: any).id) or fallback.id,
		kind = if (source :: any).kind == "system"
			or (source :: any).kind == "info"
			or (source :: any).kind == "success"
			or (source :: any).kind == "warning"
			or (source :: any).kind == "error"
			or (source :: any).kind == "command"
			then (source :: any).kind
			else fallback.kind,
		text = if typeof((source :: any).text) == "string" then (source :: any).text else fallback.text,
		timestamp = sanitizeNumber((source :: any).timestamp, fallback.timestamp, 0, nil),
		userId = DevPromptServiceUtils.sanitizeUserId((source :: any).userId),
		userName = if trim((source :: any).userName) ~= "" then trim((source :: any).userName) else nil,
		roleId = roleId,
	}
end

function DevPromptServiceUtils.cloneEntries(entriesRaw: any): { ConsoleEntry }
	local output = {}
	if typeof(entriesRaw) ~= "table" then
		return output
	end
	for _, entry in entriesRaw do
		output[#output + 1] = DevPromptServiceUtils.cloneConsoleEntry(entry)
	end
	return output
end

function DevPromptServiceUtils.limitEntries(entriesRaw: { ConsoleEntry }, maxEntriesRaw: any): { ConsoleEntry }
	local entries = DevPromptServiceUtils.cloneEntries(entriesRaw)
	local maxEntries = sanitizeInteger(maxEntriesRaw, DevPromptServiceUtils.DEFAULT_MAX_ENTRIES, 1, 1000)
	if #entries <= maxEntries then
		return entries
	end
	local startIndex = #entries - maxEntries + 1
	local output = table.create(maxEntries)
	local outputIndex = 0
	for index = startIndex, #entries do
		outputIndex += 1
		output[outputIndex] = entries[index]
	end
	return output
end

function DevPromptServiceUtils.createDefaultState(): DevPromptState
	return {
		ownerUserId = nil,
		ownerName = "",
		localRoleId = "Member",
		canUseCommands = false,
		playerRoles = {},
		entries = {},
		isOpen = false,
		commandPrefix = DevPromptServiceUtils.DEFAULT_COMMAND_PREFIX,
		maxEntries = DevPromptServiceUtils.DEFAULT_MAX_ENTRIES,
	}
end

function DevPromptServiceUtils.sanitizeState(stateRaw: any, fallbackRaw: any?): DevPromptState
	local fallback = if fallbackRaw ~= nil
		then (fallbackRaw :: DevPromptState)
		else DevPromptServiceUtils.createDefaultState()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}

	local localRoleId = Role.getDefinition((source :: any).localRoleId).id
	return {
		ownerUserId = DevPromptServiceUtils.sanitizeUserId((source :: any).ownerUserId) or fallback.ownerUserId,
		ownerName = if trim((source :: any).ownerName) ~= "" then trim((source :: any).ownerName) else fallback.ownerName,
		localRoleId = localRoleId,
		canUseCommands = sanitizeBoolean((source :: any).canUseCommands, fallback.canUseCommands),
		playerRoles = DevPromptServiceUtils.sanitizePlayerRoles((source :: any).playerRoles),
		entries = DevPromptServiceUtils.limitEntries(
			DevPromptServiceUtils.cloneEntries((source :: any).entries),
			(source :: any).maxEntries
		),
		isOpen = sanitizeBoolean((source :: any).isOpen, fallback.isOpen),
		commandPrefix = if trim((source :: any).commandPrefix) ~= ""
			then trim((source :: any).commandPrefix)
			else fallback.commandPrefix,
		maxEntries = sanitizeInteger((source :: any).maxEntries, fallback.maxEntries, 1, 1000),
	}
end

function DevPromptServiceUtils.cloneState(stateRaw: any): DevPromptState
	return DevPromptServiceUtils.sanitizeState(stateRaw, DevPromptServiceUtils.createDefaultState())
end

function DevPromptServiceUtils.normalizeCommandName(nameRaw: any): string
	local name = trim(nameRaw)
	if name == "" then
		return ""
	end
	return string.lower(name)
end

function DevPromptServiceUtils.stripCommandPrefix(textRaw: any, prefixRaw: any): string
	local text = trim(textRaw)
	local prefix = trim(prefixRaw)
	if prefix == "" or text == "" then
		return text
	end
	if string.sub(text, 1, #prefix) == prefix then
		return trim(string.sub(text, #prefix + 1))
	end
	return text
end

function DevPromptServiceUtils.tokenizeCommandText(textRaw: any): { string }
	local text = trim(textRaw)
	local tokens = {}
	if text == "" then
		return tokens
	end

	local cursor = {}
	local quote: string? = nil
	local escapeNext = false

	local function flushToken()
		if #cursor <= 0 then
			return
		end
		tokens[#tokens + 1] = table.concat(cursor)
		table.clear(cursor)
	end

	for index = 1, #text do
		local character = string.sub(text, index, index)
		if escapeNext then
			cursor[#cursor + 1] = character
			escapeNext = false
		elseif character == "\\" then
			escapeNext = true
		elseif quote ~= nil then
			if character == quote then
				quote = nil
			else
				cursor[#cursor + 1] = character
			end
		elseif character == '"' or character == "'" then
			quote = character
		elseif string.match(character, "%s") ~= nil then
			flushToken()
		else
			cursor[#cursor + 1] = character
		end
	end

	flushToken()
	return tokens
end

return DevPromptServiceUtils
