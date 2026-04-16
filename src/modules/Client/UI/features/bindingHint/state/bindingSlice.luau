--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type BindingHintEntry = {
	id: string,
	actionName: string?,
	label: string,
	detail: string?,
	promptText: string?,
	promptIcon: string?,
	enabled: boolean,
	priority: number,
}

export type BindingHintState = {
	started: boolean,
	visible: boolean,
	platform: string,
	deviceClass: string,
	hints: { BindingHintEntry },
	updatedAt: number,
}

local DEFAULT_STATE: BindingHintState = {
	started = false,
	visible = false,
	platform = "KeyboardMouse",
	deviceClass = "Desktop",
	hints = {},
	updatedAt = os.clock(),
}

local bindingStateAtom: Charm.Atom<BindingHintState> = Charm.atom(DEFAULT_STATE)

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeInteger(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.floor(valueRaw)
end

local function sanitizeHintEntry(entryRaw: any, index: number): BindingHintEntry?
	if typeof(entryRaw) ~= "table" then
		return nil
	end

	local entry = entryRaw :: { [string]: any }
	local id = trim(entry.id)
	if id == "" then
		id = ("binding_hint_%d"):format(index)
	end

	local label = trim(entry.label)
	if label == "" then
		return nil
	end

	local actionName = trim(entry.actionName)
	local detail = trim(entry.detail)
	local promptText = trim(entry.promptText)
	local promptIcon = trim(entry.promptIcon)

	return {
		id = id,
		actionName = if actionName ~= "" then actionName else nil,
		label = label,
		detail = if detail ~= "" then detail else nil,
		promptText = if promptText ~= "" then promptText else nil,
		promptIcon = if promptIcon ~= "" then promptIcon else nil,
		enabled = sanitizeBoolean(entry.enabled, true),
		priority = sanitizeInteger(entry.priority, index),
	}
end

local function cloneHintEntry(entry: BindingHintEntry): BindingHintEntry
	return {
		id = entry.id,
		actionName = entry.actionName,
		label = entry.label,
		detail = entry.detail,
		promptText = entry.promptText,
		promptIcon = entry.promptIcon,
		enabled = entry.enabled,
		priority = entry.priority,
	}
end

local function cloneHints(hintsRaw: any): { BindingHintEntry }
	local output: { BindingHintEntry } = {}
	local seenIds: { [string]: boolean } = {}
	if typeof(hintsRaw) ~= "table" then
		return output
	end

	for index, hintRaw in hintsRaw do
		local hint = sanitizeHintEntry(hintRaw, index)
		if hint == nil or seenIds[hint.id] == true then
			continue
		end
		seenIds[hint.id] = true
		output[#output + 1] = hint
	end

	table.sort(output, function(lhs: BindingHintEntry, rhs: BindingHintEntry): boolean
		if lhs.priority == rhs.priority then
			if lhs.enabled ~= rhs.enabled then
				return lhs.enabled
			end
			if lhs.label ~= rhs.label then
				return lhs.label < rhs.label
			end
			return lhs.id < rhs.id
		end
		return lhs.priority < rhs.priority
	end)

	return output
end

local function cloneState(state: BindingHintState): BindingHintState
	local hints: { BindingHintEntry } = {}
	for index, hint in state.hints do
		hints[index] = cloneHintEntry(hint)
	end

	return {
		started = state.started,
		visible = state.visible,
		platform = state.platform,
		deviceClass = state.deviceClass,
		hints = hints,
		updatedAt = state.updatedAt,
	}
end

local function hintsEqual(lhs: { BindingHintEntry }, rhs: { BindingHintEntry }): boolean
	if #lhs ~= #rhs then
		return false
	end

	for index = 1, #lhs do
		local a = lhs[index]
		local b = rhs[index]
		if a == nil or b == nil then
			return false
		end
		if a.id ~= b.id
			or a.actionName ~= b.actionName
			or a.label ~= b.label
			or a.detail ~= b.detail
			or a.promptText ~= b.promptText
			or a.promptIcon ~= b.promptIcon
			or a.enabled ~= b.enabled
			or a.priority ~= b.priority
		then
			return false
		end
	end

	return true
end

local function statesEqual(lhs: BindingHintState, rhs: BindingHintState): boolean
	return lhs.started == rhs.started
		and lhs.visible == rhs.visible
		and lhs.platform == rhs.platform
		and lhs.deviceClass == rhs.deviceClass
		and hintsEqual(lhs.hints, rhs.hints)
end

local function getBindingState(): BindingHintState
	return bindingStateAtom()
end

local function setBindingState(stateRaw: any): BindingHintState
	local current = bindingStateAtom()
	local source = if typeof(stateRaw) == "table" then (stateRaw :: { [string]: any }) else {}
	local nextHints = if source.hints ~= nil then cloneHints(source.hints) else cloneHints(current.hints)

	local nextState: BindingHintState = {
		started = sanitizeBoolean(source.started, current.started),
		visible = if source.visible == nil then (#nextHints > 0) else sanitizeBoolean(source.visible, current.visible),
		platform = if trim(source.platform) ~= "" then trim(source.platform) else current.platform,
		deviceClass = if trim(source.deviceClass) ~= "" then trim(source.deviceClass) else current.deviceClass,
		hints = nextHints,
		updatedAt = os.clock(),
	}

	if statesEqual(current, nextState) then
		return current
	end

	bindingStateAtom(nextState)
	return nextState
end

local function resetBindingState(): BindingHintState
	local nextState = cloneState(DEFAULT_STATE)
	nextState.updatedAt = os.clock()
	bindingStateAtom(nextState)
	return nextState
end

return {
	bindingStateAtom = bindingStateAtom,
	getBindingState = getBindingState,
	setBindingState = setBindingState,
	resetBindingState = resetBindingState,
}
