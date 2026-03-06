--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type HoverInfoState = {
	visible: boolean,
	hoverId: string?,
	text: string,
	mousePosition: Vector2,
}

local DEFAULT_MOUSE_POSITION = Vector2.new(0, 0)
local DEFAULT_STATE: HoverInfoState = {
	visible = false,
	hoverId = nil,
	text = "",
	mousePosition = DEFAULT_MOUSE_POSITION,
}

local infoStateAtom: Charm.Atom<HoverInfoState> = Charm.atom(DEFAULT_STATE)

local function sanitizeHoverId(value: any): string
	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return "default"
end

local function sanitizeText(value: any): string
	if typeof(value) == "string" then
		return value
	end

	return ""
end

local function sanitizeMousePosition(value: any): Vector2
	if typeof(value) == "Vector2" then
		return value
	end

	return infoStateAtom().mousePosition
end

local function getInfoState(): HoverInfoState
	return infoStateAtom()
end

local function setInfoState(stateRaw: any): HoverInfoState
	local source = if typeof(stateRaw) == "table" then stateRaw else DEFAULT_STATE
	local nextState: HoverInfoState = {
		visible = source.visible == true,
		hoverId = if source.visible == true then sanitizeHoverId(source.hoverId) else nil,
		text = sanitizeText(source.text),
		mousePosition = sanitizeMousePosition(source.mousePosition),
	}

	infoStateAtom(nextState)
	return nextState
end

local function showHover(hoverIdRaw: any, textRaw: any, mousePositionRaw: any): HoverInfoState
	local nextState: HoverInfoState = {
		visible = true,
		hoverId = sanitizeHoverId(hoverIdRaw),
		text = sanitizeText(textRaw),
		mousePosition = sanitizeMousePosition(mousePositionRaw),
	}

	infoStateAtom(nextState)
	return nextState
end

local function hideHover(hoverId: string?): HoverInfoState
	local current = infoStateAtom()
	if hoverId ~= nil and hoverId ~= "" and current.hoverId ~= hoverId then
		return current
	end

	local nextState: HoverInfoState = {
		visible = false,
		hoverId = nil,
		text = "",
		mousePosition = current.mousePosition,
	}

	infoStateAtom(nextState)
	return nextState
end

local function updateMousePosition(mousePositionRaw: any): HoverInfoState
	local current = infoStateAtom()
	local nextMousePosition = sanitizeMousePosition(mousePositionRaw)
	if current.mousePosition == nextMousePosition then
		return current
	end

	local nextState: HoverInfoState = {
		visible = current.visible,
		hoverId = current.hoverId,
		text = current.text,
		mousePosition = nextMousePosition,
	}

	infoStateAtom(nextState)
	return nextState
end

local function resetInfoState(): HoverInfoState
	local current = infoStateAtom()
	local nextState: HoverInfoState = {
		visible = false,
		hoverId = nil,
		text = "",
		mousePosition = current.mousePosition,
	}

	infoStateAtom(nextState)
	return nextState
end

return {
	infoStateAtom = infoStateAtom,
	getInfoState = getInfoState,
	setInfoState = setInfoState,
	showHover = showHover,
	hideHover = hideHover,
	updateMousePosition = updateMousePosition,
	resetInfoState = resetInfoState,
}
