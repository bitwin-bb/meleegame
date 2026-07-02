local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")

local BuffConstants = require("BuffConstants")
local BuffService = require("BuffService")
local Table = require("Table")
local buffUtils = require("BuffUtils")

local fallbackTokensByPlayer: { [Player]: { [string]: any } } = {}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeToken(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	return string.gsub(value, "[^%w]", "")
end

local function GetKind(valueRaw: any): string?
	local token = normalizeToken(valueRaw)
	if token == "buff" then
		return BuffConstants.KIND_BUFF
	end
	if token == "debuff" then
		return BuffConstants.KIND_DEBUFF
	end

	return nil
end

local function getBuffRoot(): Instance?
	local gameRoot = script:FindFirstAncestor("game")
	if gameRoot == nil then
		return nil
	end

	local sharedRealmRoot = gameRoot:FindFirstChild("Shared")
	if sharedRealmRoot == nil or not sharedRealmRoot:IsA("Folder") then
		return nil
	end

	local sharedRoot = sharedRealmRoot:FindFirstChild("Source")
	if sharedRoot == nil or not sharedRoot:IsA("Folder") then
		return nil
	end

	local buffRoot = sharedRoot:FindFirstChild("Buff")
	if buffRoot ~= nil and buffRoot:IsA("Folder") then
		return buffRoot
	end

	return nil
end

local function getDefinitionFolder(kind: string): Folder?
	local buffRoot = getBuffRoot()
	if buffRoot == nil then
		return nil
	end

	local folderName = if kind == BuffConstants.KIND_DEBUFF
		then BuffConstants.DEFINITION_FOLDER_DEBUFFS
		else BuffConstants.DEFINITION_FOLDER_BUFFS
	local folder = buffRoot:FindFirstChild(folderName)
	if folder ~= nil and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function readRecordList(definitionRaw: any, kindFallback: string): { any }
	if typeof(definitionRaw) ~= "table" then
		return {}
	end

	if typeof((definitionRaw :: any).GetRecords) == "function" then
		local ok, records = pcall(function()
			return (definitionRaw :: any):GetRecords(kindFallback)
		end)
		if ok and typeof(records) == "table" then
			return records :: { any }
		end
	end

	if typeof((definitionRaw :: any).records) == "table" then
		return (definitionRaw :: any).records :: { any }
	end

	if typeof((definitionRaw :: any).name) == "string" or typeof((definitionRaw :: any).id) == "string" then
		return {
			buffUtils.CreateRecord(kindFallback, definitionRaw, nil, nil, nil, nil, nil),
		}
	end

	return {}
end

local function loadFallbackDefinitions(kind: string): { any }
	local folder = getDefinitionFolder(kind)
	if folder == nil then
		return {}
	end

	local moduleScripts = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			moduleScripts[#moduleScripts + 1] = child
		end
	end
	table.sort(moduleScripts, function(left: ModuleScript, right: ModuleScript)
		return left.Name < right.Name
	end)

	local definitions = {}
	for _, moduleScript in moduleScripts do
		local ok, definitionOrError = pcall(function()
			return require(moduleScript)
		end)
		if not ok then
			warn(`failed to load command test definition {moduleScript.Name}: {tostring(definitionOrError)}`)
			continue
		end

		for _, record in readRecordList(definitionOrError, kind) do
			definitions[#definitions + 1] = buffUtils.ApplyOverrides(record, nil)
		end
	end

	return definitions
end

local function getDefinitions(kind: string): { any }
	local ok, definitions = pcall(function()
		return BuffService:GetDefinitions(kind)
	end)
	if ok and typeof(definitions) == "table" and #definitions > 0 then
		return Table.copy(definitions :: { any })
	end

	return loadFallbackDefinitions(kind)
end

local function GetDefinition(kind: string, nameRaw: any): any?
	local directOk, directDefinition = pcall(function()
		return BuffService:GetDefinition(nameRaw, kind)
	end)
	if directOk and typeof(directDefinition) == "table" then
		return directDefinition
	end

	local target = normalizeToken(nameRaw)
	if target == "" then
		return nil
	end

	for _, definition in getDefinitions(kind) do
		if normalizeToken(definition.name) == target or normalizeToken(definition.id) == target then
			return definition
		end
	end

	return nil
end

local function decodeReplicatedRecords(player: Player): { any }
	local value = player:GetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE)
	if typeof(value) ~= "string" or value == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(value)
	end)
	if ok and typeof(decoded) == "table" then
		return decoded :: { any }
	end

	return {}
end

local function writeReplicatedRecords(player: Player, records: { any })
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(records)
	end)
	if ok then
		player:SetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE, encoded)
	end
end

local function removeReplicatedRecord(player: Player, recordId: string)
	local records = decodeReplicatedRecords(player)
	for index = #records, 1, -1 do
		local record = records[index]
		if typeof(record) == "table" and (record :: { [string]: any }).id == recordId then
			table.remove(records, index)
		end
	end

	writeReplicatedRecords(player, records)
end

local function upsertReplicatedRecord(player: Player, record: any)
	local records = decodeReplicatedRecords(player)
	local replicatedRecord = buffUtils.CreateReplicatedRecord(record, os.clock())
	local replaced = false

	for index, existingRecord in records do
		if typeof(existingRecord) == "table" and (existingRecord :: { [string]: any }).id == replicatedRecord.id then
			records[index] = replicatedRecord
			replaced = true
			break
		end
	end

	if not replaced then
		records[#records + 1] = replicatedRecord
	end

	writeReplicatedRecords(player, records)
end

local function scheduleFallbackExpiry(player: Player, record: any)
	if typeof(record) ~= "table" then
		return
	end
	if typeof((record :: { [string]: any }).duration) ~= "number" or record.duration <= 0 then
		return
	end

	local bucket = fallbackTokensByPlayer[player]
	if bucket == nil then
		bucket = {}
		fallbackTokensByPlayer[player] = bucket
	end

	local token = {}
	bucket[record.id] = token
	task.delay(record.duration, function()
		if fallbackTokensByPlayer[player] == nil or fallbackTokensByPlayer[player][record.id] ~= token then
			return
		end
		if player.Parent ~= nil then
			removeReplicatedRecord(player, record.id)
		end
		fallbackTokensByPlayer[player][record.id] = nil
	end)
end

local function applyReplicatedFallback(player: Player, definition: any): any?
	local record = buffUtils.ApplyOverrides(definition, {
		appliedAt = os.clock(),
		source = "DebugCommand",
	})
	upsertReplicatedRecord(player, record)
	scheduleFallbackExpiry(player, record)
	return record
end

local function applyDefinition(player: Player, definition: any): (any?, boolean)
	local ok, record = pcall(function()
		return BuffService:ApplyRecord(player, definition, {
			source = "DebugCommand",
		})
	end)
	if ok and record ~= nil then
		return record, false
	end

	return applyReplicatedFallback(player, definition), true
end

local function getAvailableNames(kind: string): { string }
	local names = {}
	for _, definition in getDefinitions(kind) do
		local name = trim(definition.name)
		if name ~= "" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

return function(context, subcommandRaw: string, nameRaw: string)
	local player = context.Executor
	if player == nil then
		return "No command executor was found."
	end

	local kind = GetKind(subcommandRaw)
	if kind == nil then
		return "Use test buff <name> or test debuff <name>."
	end

	local definition = GetDefinition(kind, nameRaw)
	if definition == nil then
		local names = getAvailableNames(kind)
		if #names > 0 then
			return `{kind} "{trim(nameRaw)}" was not found. Available: {table.concat(names, ", ")}.`
		end

		return `{kind} "{trim(nameRaw)}" was not found, and no {kind} definitions were loaded.`
	end

	local record, usedFallback = applyDefinition(player, definition)
	if record == nil then
		return `Could not apply {kind} "{definition.name}" to {player.Name}.`
	end

	local suffix = if usedFallback then " through replicated test fallback" else ""
	return `Applied {kind} "{record.name}" to {player.Name}{suffix}.`
end
