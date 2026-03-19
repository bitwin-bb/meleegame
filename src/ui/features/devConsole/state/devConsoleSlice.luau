--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local Commands = require(ReplicatedStorage.Shared.Services.DevPromptService.Commands)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)

type CommandDefinition = {
	name: string,
	aliases: { string },
	description: string,
	usage: string,
	run: any,
}

type DevPromptState = DevPromptServiceUtils.DevPromptState

export type CommandSuggestion = {
	name: string,
	aliases: { string },
	description: string,
	usage: string,
	replaceTokenIndex: number,
}

export type DevConsoleState = {
	started: boolean,
	ready: boolean,
	visible: boolean,
	promptText: string,
	selectedSuggestionIndex: number?,
	history: { string },
	historyIndex: number?,
	historyDraftText: string?,
	serviceState: DevPromptState,
	suggestions: { CommandSuggestion },
	updatedAt: number,
}

local MAX_SUGGESTIONS = 8
local MAX_HISTORY = 50
local AMOUNT_SUGGESTIONS = { "1", "5", "10", "25", "50", "100", "999999" }
local HEALTH_VALUE_SUGGESTIONS = { "20", "100", "200", "400", "420", "500" }
local MANA_VALUE_SUGGESTIONS = { "20", "40", "100", "200" }
local CLEAR_OPTION_SUGGESTIONS = { "entities" }
local GODMODE_MODE_SUGGESTIONS = { "on", "off", "toggle" }
local DAYLIGHT_MODE_SUGGESTIONS = { "on", "off", "toggle", "time" }
local CLOCK_TIME_SUGGESTIONS = { "0", "4.5", "6", "8.5", "12", "18", "21" }
local WEATHER_TYPE_SUGGESTIONS = { "clear", "rainstorm", "thunderstorm" }
local WEATHER_TRANSITION_SUGGESTIONS = { "0", "1", "3", "6", "10" }
local SPAWN_ENTITY_SUGGESTIONS = { "slime", "green", "greenslime", "eye", "eoc", "eyeofcthulhu" }
local BOSS_SPAWN_AMOUNT_SUGGESTIONS = { "1", "2", "3", "5" }
local DEFAULT_SPAWN_AMOUNT_SUGGESTIONS = { "1", "2", "3", "5", "10", "20" }
local SIMULATION_SPEED_SUGGESTIONS = { "0.5", "1", "1.25", "1.5", "2" }
local AGGRESSIVENESS_SUGGESTIONS = { "0.5", "1", "1.25", "1.5", "2" }

type SuggestionCandidate = {
	value: string,
	aliases: { string },
	description: string,
	usage: string,
	replaceTokenIndex: number,
	priority: number,
}

type PromptAnalysis = {
	tokens: { string },
	trailingWhitespace: boolean,
	activeTokenIndex: number,
	activeArgIndex: number?,
	currentQuery: string,
	commandDefinition: CommandDefinition?,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return valueRaw
end

local function normalizeToken(valueRaw: any): string
	local value = DevPromptServiceUtils.trim(valueRaw)
	if value == "" then
		return ""
	end
	return string.lower(string.gsub(value, "[%s_%-%.]", ""))
end

local function isEyeSpawnToken(valueRaw: any): boolean
	local token = normalizeToken(valueRaw)
	return token == "eye" or token == "eoc" or token == "eyeofcthulhu"
end

local function cloneStringArray(valuesRaw: any): { string }
	local output = {}
	if typeof(valuesRaw) ~= "table" then
		return output
	end
	for _, value in valuesRaw do
		if typeof(value) == "string" and value ~= "" then
			output[#output + 1] = value
		end
	end
	return output
end

local function cloneSuggestions(source: { CommandSuggestion }): { CommandSuggestion }
	local output = table.create(#source)
	for index, suggestion in source do
		output[index] = {
			name = suggestion.name,
			aliases = cloneStringArray(suggestion.aliases),
			description = suggestion.description,
			usage = suggestion.usage,
			replaceTokenIndex = suggestion.replaceTokenIndex,
		}
	end
	return output
end

local function cloneCommandDefinition(definitionRaw: any): CommandDefinition?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local name = DevPromptServiceUtils.trim((definitionRaw :: any).name)
	if name == "" then
		return nil
	end

	return {
		name = name,
		aliases = cloneStringArray((definitionRaw :: any).aliases),
		description = DevPromptServiceUtils.trim((definitionRaw :: any).description),
		usage = DevPromptServiceUtils.trim((definitionRaw :: any).usage),
		run = (definitionRaw :: any).run,
	}
end

local function sanitizeCommandDefinitions(): ({ CommandDefinition }, { [string]: CommandDefinition })
	local output = {}
	local aliasMap = {}
	local definitions = Commands.getDefinitions()
	for _, definition in definitions do
		local clonedDefinition = cloneCommandDefinition(definition)
		if clonedDefinition == nil then
			continue
		end

		output[#output + 1] = clonedDefinition
		aliasMap[string.lower(clonedDefinition.name)] = clonedDefinition
		for _, alias in clonedDefinition.aliases do
			aliasMap[string.lower(alias)] = clonedDefinition
		end
	end
	table.sort(output, function(a, b)
		return a.name < b.name
	end)
	return output, aliasMap
end

local ALL_COMMAND_DEFINITIONS, COMMAND_ALIAS_MAP = sanitizeCommandDefinitions()

local function sanitizeCommandSuggestions(): { CommandSuggestion }
	local output = table.create(#ALL_COMMAND_DEFINITIONS)
	for index, definition in ALL_COMMAND_DEFINITIONS do
		output[index] = {
			name = definition.name,
			aliases = cloneStringArray(definition.aliases),
			description = definition.description,
			usage = definition.usage,
			replaceTokenIndex = 1,
		}
	end
	return output
end

local ALL_COMMAND_SUGGESTIONS = sanitizeCommandSuggestions()

local function getSortedItemCandidates(usage: string, replaceTokenIndex: number): { SuggestionCandidate }
	local candidates = {}
	local definitionsById = ItemRegistry.getDefinitionsById()
	for itemId, definition in definitionsById do
		local displayName = DevPromptServiceUtils.trim((definition :: any).name)
		local description = DevPromptServiceUtils.trim((definition :: any).description)
		local aliases = {}
		if displayName ~= "" and displayName ~= itemId then
			aliases[#aliases + 1] = displayName
		end

		candidates[#candidates + 1] = {
			value = itemId,
			aliases = aliases,
			description = if description ~= ""
				then description
				else if displayName ~= "" and displayName ~= itemId then displayName else "Item ID",
			usage = usage,
			replaceTokenIndex = replaceTokenIndex,
			priority = 0,
		}
	end

	table.sort(candidates, function(a, b)
		return a.value < b.value
	end)
	return candidates
end

local ALL_ITEM_CANDIDATES = getSortedItemCandidates("", 2)

local function sanitizeSelectedSuggestionIndex(indexRaw: any, suggestionCount: number): number?
	if suggestionCount <= 0 then
		return nil
	end
	if typeof(indexRaw) ~= "number" or indexRaw ~= indexRaw then
		return 1
	end
	return math.clamp(math.floor(indexRaw), 1, suggestionCount)
end

local function resolveCommandDefinition(nameRaw: any): CommandDefinition?
	local normalized = DevPromptServiceUtils.normalizeCommandName(nameRaw)
	if normalized == "" then
		return nil
	end
	return COMMAND_ALIAS_MAP[normalized]
end

local function buildSuggestionScore(value: string, aliases: { string }, query: string): number?
	local loweredName = string.lower(value)
	if loweredName == query then
		return 0
	end
	if string.sub(loweredName, 1, #query) == query then
		return 1
	end

	for _, alias in aliases do
		local loweredAlias = string.lower(alias)
		if loweredAlias == query then
			return 2
		end
		if string.sub(loweredAlias, 1, #query) == query then
			return 3
		end
	end

	if string.find(loweredName, query, 1, true) ~= nil then
		return 4
	end
	for _, alias in aliases do
		if string.find(string.lower(alias), query, 1, true) ~= nil then
			return 5
		end
	end
	return nil
end

local function analyzePrompt(promptTextRaw: any): PromptAnalysis
	local promptText = trim(promptTextRaw)
	local tokens = DevPromptServiceUtils.tokenizeCommandText(promptText)
	local trailingWhitespace = string.match(promptText, "%s$") ~= nil
	local activeTokenIndex = if #tokens <= 0 then 1 else if trailingWhitespace then #tokens + 1 else #tokens
	local currentQuery = if trailingWhitespace or #tokens <= 0 then "" else tokens[#tokens]
	local commandDefinition = if #tokens > 0 then resolveCommandDefinition(tokens[1]) else nil

	return {
		tokens = tokens,
		trailingWhitespace = trailingWhitespace,
		activeTokenIndex = activeTokenIndex,
		activeArgIndex = if activeTokenIndex > 1 then activeTokenIndex - 1 else nil,
		currentQuery = currentQuery,
		commandDefinition = commandDefinition,
	}
end

local function appendChoiceCandidates(
	into: { SuggestionCandidate },
	values: { string },
	description: string,
	usage: string,
	replaceTokenIndex: number,
	priority: number
)
	for _, value in values do
		into[#into + 1] = {
			value = value,
			aliases = {},
			description = description,
			usage = usage,
			replaceTokenIndex = replaceTokenIndex,
			priority = priority,
		}
	end
end

local function appendPlayerCandidates(
	into: { SuggestionCandidate },
	serviceState: DevPromptState,
	usage: string,
	replaceTokenIndex: number,
	priority: number
)
	local seen = {}
	local snapshots = {}
	for _, snapshot in serviceState.playerRoles do
		snapshots[#snapshots + 1] = snapshot
	end
	table.sort(snapshots, function(a, b)
		return a.userName < b.userName
	end)

	for _, snapshot in snapshots do
		if seen[snapshot.userName] == true then
			continue
		end
		seen[snapshot.userName] = true
		local aliases = {}
		if snapshot.displayName ~= snapshot.userName then
			aliases[#aliases + 1] = snapshot.displayName
		end
		into[#into + 1] = {
			value = snapshot.userName,
			aliases = aliases,
			description = "Player name",
			usage = usage,
			replaceTokenIndex = replaceTokenIndex,
			priority = priority,
		}
	end
end

local function appendItemCandidates(
	into: { SuggestionCandidate },
	usage: string,
	replaceTokenIndex: number,
	priority: number
)
	for _, candidate in ALL_ITEM_CANDIDATES do
		into[#into + 1] = {
			value = candidate.value,
			aliases = cloneStringArray(candidate.aliases),
			description = candidate.description,
			usage = usage,
			replaceTokenIndex = replaceTokenIndex,
			priority = priority,
		}
	end
end

local function buildSuggestionsFromCandidates(
	candidates: { SuggestionCandidate },
	query: string
): { CommandSuggestion }
	if #candidates <= 0 then
		return {}
	end

	local ranked = {}

	for _, candidate in candidates do
		local score = buildSuggestionScore(candidate.value, candidate.aliases, query)
		if query == "" then
			score = 1000
		end
		if score ~= nil then
			ranked[#ranked + 1] = {
				candidate = candidate,
				score = score,
			}
		end
	end

	table.sort(ranked, function(a, b)
		if a.score == b.score then
			if a.candidate.priority == b.candidate.priority then
				return a.candidate.value < b.candidate.value
			end
			return a.candidate.priority < b.candidate.priority
		end
		return a.score < b.score
	end)

	local output = {}
	for index, entry in ranked do
		if index > MAX_SUGGESTIONS then
			break
		end
		output[#output + 1] = {
			name = entry.candidate.value,
			aliases = cloneStringArray(entry.candidate.aliases),
			description = entry.candidate.description,
			usage = entry.candidate.usage,
			replaceTokenIndex = entry.candidate.replaceTokenIndex,
		}
	end
	return output
end

local function buildParameterCandidates(
	definition: CommandDefinition,
	analysis: PromptAnalysis,
	serviceState: DevPromptState
): { SuggestionCandidate }
	local activeArgIndex = analysis.activeArgIndex
	if activeArgIndex == nil then
		return {}
	end

	local candidates = {}
	local query = string.lower(analysis.currentQuery)
	local looksNumeric = query ~= "" and string.match(query, "^%-?%d*$") ~= nil

	if definition.name == "help" and activeArgIndex == 1 then
		for _, suggestion in ALL_COMMAND_SUGGESTIONS do
			candidates[#candidates + 1] = {
				value = suggestion.name,
				aliases = cloneStringArray(suggestion.aliases),
				description = suggestion.description,
				usage = suggestion.usage,
				replaceTokenIndex = analysis.activeTokenIndex,
				priority = 0,
			}
		end
	elseif definition.name == "clear" and activeArgIndex == 1 then
		appendChoiceCandidates(candidates, CLEAR_OPTION_SUGGESTIONS, "Clear all active entities", definition.usage, analysis.activeTokenIndex, 0)
	elseif definition.name == "role" and activeArgIndex == 1 then
		appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
	elseif definition.name == "sethealth" then
		if activeArgIndex == 1 then
			appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(
				candidates,
				HEALTH_VALUE_SUGGESTIONS,
				"Max health amount",
				definition.usage,
				analysis.activeTokenIndex,
				1
			)
			if looksNumeric then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Max health amount" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 2 then
			appendChoiceCandidates(
				candidates,
				HEALTH_VALUE_SUGGESTIONS,
				"Max health amount",
				definition.usage,
				analysis.activeTokenIndex,
				0
			)
		end
	elseif definition.name == "setmana" then
		if activeArgIndex == 1 then
			appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(
				candidates,
				MANA_VALUE_SUGGESTIONS,
				"Max mana amount",
				definition.usage,
				analysis.activeTokenIndex,
				1
			)
			if looksNumeric then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Max mana amount" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 2 then
			appendChoiceCandidates(
				candidates,
				MANA_VALUE_SUGGESTIONS,
				"Max mana amount",
				definition.usage,
				analysis.activeTokenIndex,
				0
			)
		end
	elseif definition.name == "heal" then
		if activeArgIndex == 1 then
			appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(candidates, AMOUNT_SUGGESTIONS, "Heal amount", definition.usage, analysis.activeTokenIndex, 1)
			if looksNumeric then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Heal amount" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 2 then
			appendChoiceCandidates(candidates, AMOUNT_SUGGESTIONS, "Heal amount", definition.usage, analysis.activeTokenIndex, 0)
		end
	elseif definition.name == "give" then
		if activeArgIndex == 1 then
			appendItemCandidates(candidates, definition.usage, analysis.activeTokenIndex, 0)
		elseif activeArgIndex == 2 then
			appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(candidates, AMOUNT_SUGGESTIONS, "Item amount", definition.usage, analysis.activeTokenIndex, 1)
			if looksNumeric then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Item amount" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 3 then
			appendChoiceCandidates(candidates, AMOUNT_SUGGESTIONS, "Item amount", definition.usage, analysis.activeTokenIndex, 0)
		end
	elseif definition.name == "spawn" then
		local spawnEntityToken = normalizeToken(analysis.tokens[2])
		if activeArgIndex == 1 then
			appendChoiceCandidates(candidates, SPAWN_ENTITY_SUGGESTIONS, "Spawnable entity", definition.usage, analysis.activeTokenIndex, 0)
		elseif activeArgIndex == 2 then
			local amountSuggestions = if isEyeSpawnToken(spawnEntityToken)
				then BOSS_SPAWN_AMOUNT_SUGGESTIONS
				else DEFAULT_SPAWN_AMOUNT_SUGGESTIONS
			appendChoiceCandidates(candidates, amountSuggestions, "Spawn amount", definition.usage, analysis.activeTokenIndex, 0)
		elseif activeArgIndex == 3 and isEyeSpawnToken(spawnEntityToken) then
			appendChoiceCandidates(
				candidates,
				SIMULATION_SPEED_SUGGESTIONS,
				"Simulation speed",
				definition.usage,
				analysis.activeTokenIndex,
				0
			)
		elseif activeArgIndex == 4 and isEyeSpawnToken(spawnEntityToken) then
			appendChoiceCandidates(
				candidates,
				AGGRESSIVENESS_SUGGESTIONS,
				"Aggressiveness",
				definition.usage,
				analysis.activeTokenIndex,
				0
			)
		end
	elseif definition.name == "weather" then
		if activeArgIndex == 1 then
			appendChoiceCandidates(candidates, WEATHER_TYPE_SUGGESTIONS, "Weather preset", definition.usage, analysis.activeTokenIndex, 0)
		elseif activeArgIndex == 2 then
			appendChoiceCandidates(
				candidates,
				WEATHER_TRANSITION_SUGGESTIONS,
				"Transition seconds",
				definition.usage,
				analysis.activeTokenIndex,
				0
			)
		end
	elseif definition.name == "daylight" then
		local modeToken = normalizeToken(analysis.tokens[2])
		if activeArgIndex == 1 then
			appendChoiceCandidates(candidates, DAYLIGHT_MODE_SUGGESTIONS, "Daylight mode", definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(candidates, CLOCK_TIME_SUGGESTIONS, "Clock time", definition.usage, analysis.activeTokenIndex, 1)
			if looksNumeric then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Clock time" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 2 and (modeToken == "time" or modeToken == "clock" or modeToken == "set") then
			appendChoiceCandidates(candidates, CLOCK_TIME_SUGGESTIONS, "Clock time", definition.usage, analysis.activeTokenIndex, 0)
		end
	elseif definition.name == "godmode" then
		if activeArgIndex == 1 then
			appendPlayerCandidates(candidates, serviceState, definition.usage, analysis.activeTokenIndex, 0)
			appendChoiceCandidates(candidates, GODMODE_MODE_SUGGESTIONS, "Godmode mode", definition.usage, analysis.activeTokenIndex, 1)
			if query == "on" or query == "off" or query == "toggle" then
				for _, candidate in candidates do
					candidate.priority = if candidate.description == "Godmode mode" then 0 else candidate.priority + 1
				end
			end
		elseif activeArgIndex == 2 then
			appendChoiceCandidates(candidates, GODMODE_MODE_SUGGESTIONS, "Godmode mode", definition.usage, analysis.activeTokenIndex, 0)
		end
	end

	return candidates
end

local function buildSuggestions(promptTextRaw: any, serviceState: DevPromptState): { CommandSuggestion }
	local analysis = analyzePrompt(promptTextRaw)
	local query = string.lower(analysis.currentQuery)

	if analysis.activeTokenIndex == 1 then
		if query == "" then
			return {}
		end
		local candidates = {}
		for _, suggestion in ALL_COMMAND_SUGGESTIONS do
			candidates[#candidates + 1] = {
				value = suggestion.name,
				aliases = cloneStringArray(suggestion.aliases),
				description = suggestion.description,
				usage = suggestion.usage,
				replaceTokenIndex = 1,
				priority = 0,
			}
		end
		return buildSuggestionsFromCandidates(candidates, query)
	end

	if analysis.commandDefinition == nil then
		return {}
	end

	return buildSuggestionsFromCandidates(buildParameterCandidates(analysis.commandDefinition, analysis, serviceState), query)
end

local function createDefaultState(): DevConsoleState
	return {
		started = false,
		ready = false,
		visible = false,
		promptText = "",
		selectedSuggestionIndex = nil,
		history = {},
		historyIndex = nil,
		historyDraftText = nil,
		serviceState = DevPromptServiceUtils.createDefaultState(),
		suggestions = buildSuggestions("", DevPromptServiceUtils.createDefaultState()),
		updatedAt = os.clock(),
	}
end

local devConsoleStateAtom: Charm.Atom<DevConsoleState> = Charm.atom(createDefaultState())

local function getDevConsoleState(): DevConsoleState
	return devConsoleStateAtom()
end

local function applyStateMutations(sourceRaw: any): DevConsoleState
	local current = devConsoleStateAtom()
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {}

	local promptText = if source.promptText ~= nil then trim((source :: any).promptText) else current.promptText
	local serviceState = if source.serviceState ~= nil
		then DevPromptServiceUtils.cloneState((source :: any).serviceState)
		else current.serviceState
	local suggestions = if source.suggestions ~= nil
		then cloneSuggestions((source :: any).suggestions)
		else buildSuggestions(promptText, serviceState)

	local nextState: DevConsoleState = {
		started = if source.started ~= nil then (source :: any).started == true else current.started,
		ready = if source.ready ~= nil then (source :: any).ready == true else current.ready,
		visible = if source.visible ~= nil then (source :: any).visible == true else current.visible,
		promptText = promptText,
		selectedSuggestionIndex = sanitizeSelectedSuggestionIndex(
			if source.selectedSuggestionIndex ~= nil
				then (source :: any).selectedSuggestionIndex
				else current.selectedSuggestionIndex,
			#suggestions
		),
		history = if source.history ~= nil then cloneStringArray((source :: any).history) else cloneStringArray(current.history),
		historyIndex = if source.historyIndex == nil
			then current.historyIndex
			else sanitizeSelectedSuggestionIndex((source :: any).historyIndex, #(if source.history ~= nil
				then cloneStringArray((source :: any).history)
				else current.history)),
		historyDraftText = if source.historyDraftText ~= nil then trim((source :: any).historyDraftText) else current.historyDraftText,
		serviceState = serviceState,
		suggestions = suggestions,
		updatedAt = os.clock(),
	}

	devConsoleStateAtom(nextState)
	return nextState
end

local function applyServiceState(serviceStateRaw: any): DevConsoleState
	local current = devConsoleStateAtom()
	local nextServiceState = DevPromptServiceUtils.cloneState(serviceStateRaw)
	return applyStateMutations({
		serviceState = nextServiceState,
		visible = nextServiceState.isOpen,
		ready = true,
		started = true,
		promptText = current.promptText,
		history = current.history,
		historyIndex = current.historyIndex,
		historyDraftText = current.historyDraftText,
	})
end

local function setStarted(startedRaw: any): DevConsoleState
	return applyStateMutations({
		started = startedRaw == true,
	})
end

local function setReady(readyRaw: any): DevConsoleState
	return applyStateMutations({
		ready = readyRaw == true,
	})
end

local function setPromptText(promptTextRaw: any): DevConsoleState
	return applyStateMutations({
		promptText = promptTextRaw,
		selectedSuggestionIndex = 1,
		historyIndex = nil,
		historyDraftText = nil,
	})
end

local function clearPromptText(): DevConsoleState
	return applyStateMutations({
		promptText = "",
		selectedSuggestionIndex = 1,
		historyIndex = nil,
		historyDraftText = nil,
	})
end

local function cycleSuggestion(deltaRaw: any): DevConsoleState
	local current = devConsoleStateAtom()
	local suggestionCount = #current.suggestions
	if suggestionCount <= 0 then
		return current
	end
	local delta = if typeof(deltaRaw) == "number" and deltaRaw == deltaRaw then math.floor(deltaRaw) else 0
	if delta == 0 then
		return current
	end
	local currentIndex = current.selectedSuggestionIndex or 1
	local nextIndex = ((currentIndex - 1 + delta) % suggestionCount) + 1
	return applyStateMutations({
		selectedSuggestionIndex = nextIndex,
	})
end

local function applySelectedSuggestion(indexRaw: any?): DevConsoleState
	local current = devConsoleStateAtom()
	local suggestionIndex = sanitizeSelectedSuggestionIndex(
		if indexRaw ~= nil then indexRaw else current.selectedSuggestionIndex,
		#current.suggestions
	)
	if suggestionIndex == nil then
		return current
	end

	local suggestion = current.suggestions[suggestionIndex]
	if suggestion == nil then
		return current
	end

	local analysis = analyzePrompt(current.promptText)
	local tokens = cloneStringArray(analysis.tokens)
	local replaceTokenIndex = math.max(1, suggestion.replaceTokenIndex)
	if replaceTokenIndex <= #tokens then
		tokens[replaceTokenIndex] = suggestion.name
	else
		tokens[#tokens + 1] = suggestion.name
	end

	local rebuilt = table.concat(tokens, " ")
	if rebuilt ~= "" then
		rebuilt ..= " "
	end

	return applyStateMutations({
		promptText = rebuilt,
		selectedSuggestionIndex = suggestionIndex,
		historyIndex = nil,
		historyDraftText = nil,
	})
end

local function pushHistory(commandTextRaw: any): DevConsoleState
	local commandText = DevPromptServiceUtils.trim(commandTextRaw)
	if commandText == "" then
		return devConsoleStateAtom()
	end

	local current = devConsoleStateAtom()
	local nextHistory = cloneStringArray(current.history)
	if #nextHistory <= 0 or nextHistory[#nextHistory] ~= commandText then
		nextHistory[#nextHistory + 1] = commandText
	end
	while #nextHistory > MAX_HISTORY do
		table.remove(nextHistory, 1)
	end

	return applyStateMutations({
		history = nextHistory,
		historyIndex = nil,
		historyDraftText = nil,
	})
end

local function cycleHistory(deltaRaw: any): DevConsoleState
	local current = devConsoleStateAtom()
	local historyCount = #current.history
	if historyCount <= 0 then
		return current
	end

	local delta = if typeof(deltaRaw) == "number" and deltaRaw == deltaRaw then math.floor(deltaRaw) else 0
	if delta == 0 then
		return current
	end

	local currentIndex = current.historyIndex
	local draftText = current.historyDraftText
	if currentIndex == nil then
		if delta > 0 then
			return current
		end
		currentIndex = historyCount + 1
		draftText = current.promptText
	end

	local nextIndex = math.clamp(currentIndex + delta, 1, historyCount + 1)
	if nextIndex == historyCount + 1 then
		return applyStateMutations({
			promptText = if draftText ~= nil then draftText else "",
			historyIndex = nil,
			historyDraftText = nil,
			selectedSuggestionIndex = 1,
		})
	end

	return applyStateMutations({
		promptText = current.history[nextIndex],
		historyIndex = nextIndex,
		historyDraftText = if draftText ~= nil then draftText else current.promptText,
		selectedSuggestionIndex = 1,
	})
end

local function resetDevConsoleState(): DevConsoleState
	local nextState = createDefaultState()
	devConsoleStateAtom(nextState)
	return nextState
end

local function getPromptText(): string
	return devConsoleStateAtom().promptText
end

local function getSelectedSuggestion(): CommandSuggestion?
	local current = devConsoleStateAtom()
	local suggestionIndex = current.selectedSuggestionIndex
	if suggestionIndex == nil then
		return nil
	end
	return current.suggestions[suggestionIndex]
end

return {
	devConsoleStateAtom = devConsoleStateAtom,
	getDevConsoleState = getDevConsoleState,
	applyServiceState = applyServiceState,
	setStarted = setStarted,
	setReady = setReady,
	setPromptText = setPromptText,
	clearPromptText = clearPromptText,
	cycleSuggestion = cycleSuggestion,
	applySelectedSuggestion = applySelectedSuggestion,
	pushHistory = pushHistory,
	cycleHistory = cycleHistory,
	resetDevConsoleState = resetDevConsoleState,
	getPromptText = getPromptText,
	getSelectedSuggestion = getSelectedSuggestion,
}
