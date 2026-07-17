local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Charm: any = require(ReplicatedStorage.Packages.Charm)
local ImageIds = require("ImageIds")

export type MouseCursorState = "default" | "hover" | "click"
export type MouseState = {
	visible: boolean,
	position: Vector2,
	isHoveringGui: boolean,
	hoveredGuiPath: string?,
	isMouseDown: boolean,
	cursorState: MouseCursorState,
	imageId: string,
}

type MouseStateSource = {
	visible: boolean,
	position: Vector2,
	isHoveringGui: boolean,
	hoveredGuiPath: string?,
	isMouseDown: boolean,
}

local DEFAULT_MOUSE_IMAGE_ID = if typeof(ImageIds.mouse) == "string" then ImageIds.mouse else ""
local HOVER_MOUSE_IMAGE_ID = if typeof(ImageIds.mouseHover) == "string"
	then ImageIds.mouseHover
	else DEFAULT_MOUSE_IMAGE_ID
local CLICK_MOUSE_IMAGE_ID = if typeof(ImageIds.mouseClick) == "string"
	then ImageIds.mouseClick
	else HOVER_MOUSE_IMAGE_ID
local DEFAULT_MOUSE_POSITION = Vector2.new(0, 0)

local function getCursorState(source: MouseStateSource): MouseCursorState
	if source.isMouseDown then
		return "click"
	end
	if source.isHoveringGui then
		return "hover"
	end
	return "default"
end

local function getCursorImageId(cursorState: MouseCursorState): string
	if cursorState == "click" then
		return CLICK_MOUSE_IMAGE_ID
	end
	if cursorState == "hover" then
		return HOVER_MOUSE_IMAGE_ID
	end
	return DEFAULT_MOUSE_IMAGE_ID
end

local function createMouseState(source: MouseStateSource): MouseState
	local cursorState = getCursorState(source)
	return {
		visible = source.visible,
		position = source.position,
		isHoveringGui = source.isHoveringGui,
		hoveredGuiPath = if source.isHoveringGui then source.hoveredGuiPath else nil,
		isMouseDown = source.isMouseDown,
		cursorState = cursorState,
		imageId = getCursorImageId(cursorState :: any),
	} :: MouseState
end

local DEFAULT_STATE: MouseState = createMouseState({
	visible = true,
	position = DEFAULT_MOUSE_POSITION,
	isHoveringGui = false,
	hoveredGuiPath = nil,
	isMouseDown = false,
})

local mouseStateAtom: Charm.Atom<MouseState> = Charm.atom(DEFAULT_STATE)

local mousePositionAtom: Charm.Selector<Vector2> = Charm.computed(function(): Vector2
	return mouseStateAtom().position
end)

local mouseVisibleAtom: Charm.Selector<boolean> = Charm.computed(function(): boolean
	return mouseStateAtom().visible
end)

local mouseCursorStateAtom: Charm.Selector<MouseCursorState> = Charm.computed(function(): MouseCursorState
	return mouseStateAtom().cursorState
end)

local mouseImageIdAtom: Charm.Selector<string> = Charm.computed(function(): string
	return mouseStateAtom().imageId
end)

local function coercePosition(value: any): Vector2
	if typeof(value) == "Vector2" then
		return value
	end

	return mouseStateAtom().position
end

local function coerceBool(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function coerceHoveredGuiPath(value: any): string?
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function getMouseState(): MouseState
	return mouseStateAtom()
end

local function setMouseState(stateRaw: any): MouseState
	local current = mouseStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {} :: any
	local nextState = createMouseState({
		visible = coerceBool((source :: any).visible, current.visible),
		position = coercePosition((source :: any).position),
		isHoveringGui = coerceBool((source :: any).isHoveringGui, current.isHoveringGui),
		hoveredGuiPath = coerceHoveredGuiPath((source :: any).hoveredGuiPath),
		isMouseDown = coerceBool((source :: any).isMouseDown, current.isMouseDown),
	})

	mouseStateAtom(nextState)
	return nextState
end

local function updatePointer(positionRaw: any, isHoveringRaw: any, hoveredGuiPathRaw: any): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = current.visible,
		position = coercePosition(positionRaw),
		isHoveringGui = coerceBool(isHoveringRaw, current.isHoveringGui),
		hoveredGuiPath = coerceHoveredGuiPath(hoveredGuiPathRaw),
		isMouseDown = current.isMouseDown,
	})
	mouseStateAtom(nextState)
	return nextState
end

local function setMousePosition(positionRaw: any): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = current.visible,
		position = coercePosition(positionRaw),
		isHoveringGui = current.isHoveringGui,
		hoveredGuiPath = current.hoveredGuiPath,
		isMouseDown = current.isMouseDown,
	})
	mouseStateAtom(nextState)
	return nextState
end

local function setHovering(isHoveringRaw: any, hoveredGuiPathRaw: any): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = current.visible,
		position = current.position,
		isHoveringGui = coerceBool(isHoveringRaw, current.isHoveringGui),
		hoveredGuiPath = coerceHoveredGuiPath(hoveredGuiPathRaw),
		isMouseDown = current.isMouseDown,
	})
	mouseStateAtom(nextState)
	return nextState
end

local function setMouseDown(isMouseDownRaw: any): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = current.visible,
		position = current.position,
		isHoveringGui = current.isHoveringGui,
		hoveredGuiPath = current.hoveredGuiPath,
		isMouseDown = coerceBool(isMouseDownRaw, current.isMouseDown),
	})
	mouseStateAtom(nextState)
	return nextState
end

local function setMouseVisible(visibleRaw: any): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = coerceBool(visibleRaw, current.visible),
		position = current.position,
		isHoveringGui = current.isHoveringGui,
		hoveredGuiPath = current.hoveredGuiPath,
		isMouseDown = current.isMouseDown,
	})
	mouseStateAtom(nextState)
	return nextState
end

local function resetMouseState(): MouseState
	local current = mouseStateAtom()
	local nextState = createMouseState({
		visible = current.visible,
		position = current.position,
		isHoveringGui = false,
		hoveredGuiPath = nil,
		isMouseDown = false,
	})
	mouseStateAtom(nextState)
	return nextState
end

return {
	mouseStateAtom = mouseStateAtom,
	mousePositionAtom = mousePositionAtom,
	mouseVisibleAtom = mouseVisibleAtom,
	mouseCursorStateAtom = mouseCursorStateAtom,
	mouseImageIdAtom = mouseImageIdAtom,
	getMouseState = getMouseState,
	setMouseState = setMouseState,
	updatePointer = updatePointer,
	setMousePosition = setMousePosition,
	setHovering = setHovering,
	setMouseDown = setMouseDown,
	setMouseVisible = setMouseVisible,
	resetMouseState = resetMouseState,
}
