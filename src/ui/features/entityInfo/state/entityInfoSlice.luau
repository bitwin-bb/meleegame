--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type EntityInfoState = {
	visible: boolean,
	hoverId: string?,
	runtimeId: string?,
	displayName: string,
	hp: number,
	maxHp: number,
	mousePosition: Vector2,
	updatedAt: number,
}

export type ShowEntityPayload = {
	hoverId: string?,
	runtimeId: string?,
	displayName: string?,
	hp: number?,
	maxHp: number?,
	mousePosition: Vector2?,
}

local DEFAULT_MOUSE_POSITION = Vector2.new(0, 0)
local DEFAULT_STATE: EntityInfoState = {
	visible = false,
	hoverId = nil,
	runtimeId = nil,
	displayName = "",
	hp = 0,
	maxHp = 0,
	mousePosition = DEFAULT_MOUSE_POSITION,
	updatedAt = os.clock(),
}

local entityInfoStateAtom: Charm.Atom<EntityInfoState> = Charm.atom(DEFAULT_STATE)

local function sanitizeOptionalId(valueRaw: any): string?
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return nil
end

local function sanitizeDisplayName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function sanitizeMousePosition(valueRaw: any, fallback: Vector2): Vector2
	if typeof(valueRaw) == "Vector2" then
		return valueRaw
	end
	return fallback
end

local function sanitizeMaxHp(valueRaw: any, fallback: number): number
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return math.max(0, math.floor(valueRaw + 0.5))
	end
	return fallback
end

local function sanitizeHp(valueRaw: any, maxHp: number, fallback: number): number
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return math.clamp(math.floor(valueRaw + 0.5), 0, math.max(0, maxHp))
	end
	return math.clamp(math.floor(fallback + 0.5), 0, math.max(0, maxHp))
end

local function getEntityInfoState(): EntityInfoState
	return entityInfoStateAtom()
end

local function setEntityInfoState(stateRaw: any): EntityInfoState
	local current = entityInfoStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}

	local maxHp = sanitizeMaxHp((source :: any).maxHp, current.maxHp)
	local nextState: EntityInfoState = {
		visible = (source :: any).visible == true,
		hoverId = sanitizeOptionalId((source :: any).hoverId),
		runtimeId = sanitizeOptionalId((source :: any).runtimeId),
		displayName = sanitizeDisplayName((source :: any).displayName, current.displayName),
		hp = sanitizeHp((source :: any).hp, maxHp, current.hp),
		maxHp = maxHp,
		mousePosition = sanitizeMousePosition((source :: any).mousePosition, current.mousePosition),
		updatedAt = os.clock(),
	}

	if nextState.visible ~= true then
		nextState.hoverId = nil
		nextState.runtimeId = nil
	end

	entityInfoStateAtom(nextState)
	return nextState
end

local function showEntityInfo(payloadRaw: any): EntityInfoState
	local current = entityInfoStateAtom()
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {}
	local maxHp = sanitizeMaxHp((payload :: any).maxHp, current.maxHp)
	local nextState: EntityInfoState = {
		visible = true,
		hoverId = sanitizeOptionalId((payload :: any).hoverId),
		runtimeId = sanitizeOptionalId((payload :: any).runtimeId),
		displayName = sanitizeDisplayName((payload :: any).displayName, current.displayName),
		hp = sanitizeHp((payload :: any).hp, maxHp, current.hp),
		maxHp = maxHp,
		mousePosition = sanitizeMousePosition((payload :: any).mousePosition, current.mousePosition),
		updatedAt = os.clock(),
	}

	entityInfoStateAtom(nextState)
	return nextState
end

local function updateMousePosition(mousePositionRaw: any): EntityInfoState
	local current = entityInfoStateAtom()
	local nextMousePosition = sanitizeMousePosition(mousePositionRaw, current.mousePosition)
	if nextMousePosition == current.mousePosition then
		return current
	end

	local nextState: EntityInfoState = {
		visible = current.visible,
		hoverId = current.hoverId,
		runtimeId = current.runtimeId,
		displayName = current.displayName,
		hp = current.hp,
		maxHp = current.maxHp,
		mousePosition = nextMousePosition,
		updatedAt = os.clock(),
	}
	entityInfoStateAtom(nextState)
	return nextState
end

local function hideEntityInfo(hoverIdRaw: any): EntityInfoState
	local current = entityInfoStateAtom()
	local hoverId = sanitizeOptionalId(hoverIdRaw)
	if hoverId ~= nil and current.hoverId ~= nil and current.hoverId ~= hoverId then
		return current
	end
	if current.visible ~= true and current.runtimeId == nil then
		return current
	end

	local nextState: EntityInfoState = {
		visible = false,
		hoverId = nil,
		runtimeId = nil,
		displayName = "",
		hp = 0,
		maxHp = 0,
		mousePosition = current.mousePosition,
		updatedAt = os.clock(),
	}
	entityInfoStateAtom(nextState)
	return nextState
end

local function resetEntityInfoState(): EntityInfoState
	local current = entityInfoStateAtom()
	local nextState: EntityInfoState = {
		visible = false,
		hoverId = nil,
		runtimeId = nil,
		displayName = "",
		hp = 0,
		maxHp = 0,
		mousePosition = current.mousePosition,
		updatedAt = os.clock(),
	}
	entityInfoStateAtom(nextState)
	return nextState
end

local function formatHpText(state: EntityInfoState): string
	return string.format("%d/%d", math.max(0, state.hp), math.max(0, state.maxHp))
end

return {
	entityInfoStateAtom = entityInfoStateAtom,
	getEntityInfoState = getEntityInfoState,
	setEntityInfoState = setEntityInfoState,
	showEntityInfo = showEntityInfo,
	updateMousePosition = updateMousePosition,
	hideEntityInfo = hideEntityInfo,
	resetEntityInfoState = resetEntityInfoState,
	formatHpText = formatHpText,
}
