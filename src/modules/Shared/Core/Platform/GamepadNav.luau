--!strict
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Packages.Signal)

local GamepadNav = {}
GamepadNav.__index = GamepadNav

local GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE = "CustomCursorGamepadActive"
local THUMBSTICK_ACTIVE_EPSILON = 1e-4
local DEFAULT_MOVE_REPEAT_COOLDOWN = 0.12
local DEFAULT_STICK_DEADZONE = 0.12
local DEFAULT_NAVIGATION_DEADZONE = 0.35

GamepadNav.THUMBSTICK_ACTIVE_EPSILON = THUMBSTICK_ACTIVE_EPSILON
GamepadNav.DEFAULT_MOVE_REPEAT_COOLDOWN = DEFAULT_MOVE_REPEAT_COOLDOWN
GamepadNav.DEFAULT_STICK_DEADZONE = DEFAULT_STICK_DEADZONE
GamepadNav.DEFAULT_NAVIGATION_DEADZONE = DEFAULT_NAVIGATION_DEADZONE

export type NavDirection = "Up" | "Down" | "Left" | "Right"
export type ThumbstickKey = "Left" | "Right"

export type ThumbstickState = {
	key: ThumbstickKey,
	raw: Vector2,
	screen: Vector2,
	magnitude: number,
	active: boolean,
}

export type ThumbstickSnapshot = {
	left: ThumbstickState,
	right: ThumbstickState,
	dominant: ThumbstickKey?,
	lastUpdatedAt: number,
	stickDeadzone: number,
	navigationDeadzone: number,
}

export type LayoutConfig = {
	mode: "Linear" | "Grid"?,
	columns: number?,
	wrap: boolean?,
}

export type FocusCallback = (nextFocused: GuiObject?, prevFocused: GuiObject?) -> ()

export type GamepadNavConfig = {
	eventBus: any?,
	eventChannel: string?,
	focusEvent: string?,
	thumbstickEvent: string?,
	tooltipManager: any?,
	onActivate: ((focused: GuiObject?) -> ())?,
	onBack: (() -> ())?,
	onFocusChanged: FocusCallback?,
	moveRepeatCooldown: number?,
	stickDeadzone: number?,
	navigationDeadzone: number?,
	navigationStickKeyCode: Enum.KeyCode?,
}

type LayoutRecord = {
	key: string,
	elements: { GuiObject },
	mode: "Linear" | "Grid",
	columns: number,
	wrap: boolean,
}

export type GamepadNav = typeof(setmetatable({} :: any, GamepadNav))

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type FocusChangedSignal = {
	Connect: (self: FocusChangedSignal, callback: FocusCallback) -> SignalConnection,
	Fire: (self: FocusChangedSignal, nextFocused: GuiObject?, prevFocused: GuiObject?) -> (),
	DisconnectAll: (self: FocusChangedSignal) -> (),
	Destroy: (self: FocusChangedSignal) -> (),
}

type ThumbstickChangedCallback = (snapshot: ThumbstickSnapshot) -> ()

type ThumbstickChangedSignal = {
	Connect: (self: ThumbstickChangedSignal, callback: ThumbstickChangedCallback) -> SignalConnection,
	Fire: (self: ThumbstickChangedSignal, snapshot: ThumbstickSnapshot) -> (),
	DisconnectAll: (self: ThumbstickChangedSignal) -> (),
	Destroy: (self: ThumbstickChangedSignal) -> (),
}

local function clampInteger(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then math.floor(valueRaw) else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function isSelectable(gui: GuiObject): boolean
	return gui.Visible and gui.Active and gui.Selectable
end

local function createThumbstickState(key: ThumbstickKey): ThumbstickState
	return {
		key = key,
		raw = Vector2.zero,
		screen = Vector2.zero,
		magnitude = 0,
		active = false,
	}
end

local function cloneThumbstickState(state: ThumbstickState): ThumbstickState
	return {
		key = state.key,
		raw = state.raw,
		screen = state.screen,
		magnitude = state.magnitude,
		active = state.active,
	}
end

local function cloneThumbstickSnapshot(snapshot: ThumbstickSnapshot): ThumbstickSnapshot
	return {
		left = cloneThumbstickState(snapshot.left),
		right = cloneThumbstickState(snapshot.right),
		dominant = snapshot.dominant,
		lastUpdatedAt = snapshot.lastUpdatedAt,
		stickDeadzone = snapshot.stickDeadzone,
		navigationDeadzone = snapshot.navigationDeadzone,
	}
end

local function normalizeThumbstickVector(vector: Vector2, deadzone: number): Vector2
	local magnitude = vector.Magnitude
	if magnitude <= deadzone or magnitude <= THUMBSTICK_ACTIVE_EPSILON then
		return Vector2.zero
	end
	local remappedMagnitude =
		math.clamp((magnitude - deadzone) / math.max(THUMBSTICK_ACTIVE_EPSILON, 1 - deadzone), 0, 1)
	return vector.Unit * remappedMagnitude
end

function GamepadNav.ResolveRemappedDeadzoneMagnitude(sourceDeadzoneRaw: any, targetDeadzoneRaw: any): number
	local sourceDeadzone = clampNumber(sourceDeadzoneRaw, DEFAULT_STICK_DEADZONE, 0, 1)
	local targetDeadzone = clampNumber(targetDeadzoneRaw, DEFAULT_NAVIGATION_DEADZONE, 0, 1)
	return math.clamp((targetDeadzone - sourceDeadzone) / math.max(THUMBSTICK_ACTIVE_EPSILON, 1 - sourceDeadzone), 0, 1)
end

local function resolveInputThumbstickVector(input: InputObject, deadzone: number): Vector2?
	local position = input.Position
	if typeof(position) ~= "Vector3" then
		return nil
	end
	return normalizeThumbstickVector(Vector2.new(position.X, position.Y), deadzone)
end

local function createThumbstickStateFromInput(
	key: ThumbstickKey,
	input: InputObject,
	deadzone: number
): ThumbstickState?
	local nextRaw = resolveInputThumbstickVector(input, deadzone)
	if nextRaw == nil then
		return nil
	end

	return {
		key = key,
		raw = nextRaw,
		screen = Vector2.new(nextRaw.X, -nextRaw.Y),
		magnitude = nextRaw.Magnitude,
		active = nextRaw.Magnitude > THUMBSTICK_ACTIVE_EPSILON,
	}
end

local function resolveDominantThumbstick(left: ThumbstickState, right: ThumbstickState): ThumbstickKey?
	if right.active then
		return "Right"
	end
	if left.active then
		return "Left"
	end
	return nil
end

local function thumbstickStatesEqual(a: ThumbstickState, b: ThumbstickState): boolean
	return a.key == b.key
		and a.active == b.active
		and math.abs(a.raw.X - b.raw.X) <= THUMBSTICK_ACTIVE_EPSILON
		and math.abs(a.raw.Y - b.raw.Y) <= THUMBSTICK_ACTIVE_EPSILON
		and math.abs(a.screen.X - b.screen.X) <= THUMBSTICK_ACTIVE_EPSILON
		and math.abs(a.screen.Y - b.screen.Y) <= THUMBSTICK_ACTIVE_EPSILON
		and math.abs(a.magnitude - b.magnitude) <= THUMBSTICK_ACTIVE_EPSILON
end

function GamepadNav.New(configRaw: GamepadNavConfig?): GamepadNav
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local stickDeadzone = clampNumber(config.stickDeadzone, DEFAULT_STICK_DEADZONE, 0, 1)
	local navigationDeadzone = clampNumber(config.navigationDeadzone, DEFAULT_NAVIGATION_DEADZONE, 0, 1)
	local thumbstickSnapshot: ThumbstickSnapshot = {
		left = createThumbstickState("Left"),
		right = createThumbstickState("Right"),
		dominant = nil,
		lastUpdatedAt = 0,
		stickDeadzone = stickDeadzone,
		navigationDeadzone = navigationDeadzone,
	}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "gamepad.nav"),
		focusEvent = normalizeEventName(config.focusEvent, "focusChanged"),
		thumbstickEvent = normalizeEventName(config.thumbstickEvent, "thumbsticksChanged"),
		tooltipManager = config.tooltipManager,
		onActivate = if typeof(config.onActivate) == "function" then config.onActivate else nil,
		onBack = if typeof(config.onBack) == "function" then config.onBack else nil,
		externalFocusChanged = if typeof(config.onFocusChanged) == "function" then config.onFocusChanged else nil,
		moveRepeatCooldown = clampNumber(config.moveRepeatCooldown, DEFAULT_MOVE_REPEAT_COOLDOWN, 0.02, 1),
		stickDeadzone = stickDeadzone,
		navigationDeadzone = navigationDeadzone,
		navigationStickKeyCode = if typeof(config.navigationStickKeyCode) == "EnumItem"
				and config.navigationStickKeyCode.EnumType == Enum.KeyCode
			then config.navigationStickKeyCode
			else Enum.KeyCode.Thumbstick1,
		layouts = {} :: { [string]: LayoutRecord },
		layoutOrder = {} :: { string },
		activeLayoutKey = nil :: string?,
		activeIndex = 0,
		lastFocusedByLayout = {} :: { [string]: number },
		focusChangedSignal = Signal.new() :: FocusChangedSignal,
		thumbstickChangedSignal = Signal.new() :: ThumbstickChangedSignal,
		thumbstickSnapshot = thumbstickSnapshot,
		connections = {} :: { RBXScriptConnection? },
		isInitialized = false,
		isEnabled = true,
		lastMoveAt = 0,
		lastStickDirX = 0,
		lastStickDirY = 0,
	}, GamepadNav)
	return self
end

function GamepadNav._getActiveLayout(self: GamepadNav): LayoutRecord?
	local key = self.activeLayoutKey
	if key == nil then
		return nil
	end
	return self.layouts[key]
end

function GamepadNav._emitFocusChanged(self: GamepadNav, nextFocused: GuiObject?, prevFocused: GuiObject?)
	if self.externalFocusChanged ~= nil then
		self.externalFocusChanged(nextFocused, prevFocused)
	end
	self.focusChangedSignal:Fire(nextFocused, prevFocused)
	if
		self.tooltipManager ~= nil
		and typeof((self.tooltipManager :: any).hide) == "function"
		and nextFocused == nil
	then
		local tooltipManagerAny = self.tooltipManager :: any
		tooltipManagerAny:hide()
	end
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.focusEvent, {
			layout = self.activeLayoutKey,
			index = self.activeIndex,
			focused = nextFocused,
			previous = prevFocused,
		})
	end
end

function GamepadNav._emitThumbstickChanged(self: GamepadNav)
	local snapshot = cloneThumbstickSnapshot(self.thumbstickSnapshot)
	self.thumbstickChangedSignal:Fire(snapshot)
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.thumbstickEvent, snapshot)
	end
end

function GamepadNav._ensureVisibleInScroll(_self: GamepadNav, focused: GuiObject?)
	if focused == nil then
		return
	end
	local ancestor = focused.Parent
	while ancestor ~= nil do
		if ancestor:IsA("ScrollingFrame") then
			local scrollingFrame = ancestor
			local frameTop = scrollingFrame.AbsolutePosition.Y
			local frameBottom = frameTop + scrollingFrame.AbsoluteWindowSize.Y
			local focusedTop = focused.AbsolutePosition.Y
			local focusedBottom = focusedTop + focused.AbsoluteSize.Y
			local canvasY = scrollingFrame.CanvasPosition.Y

			if focusedTop < frameTop then
				canvasY -= (frameTop - focusedTop) + 4
			elseif focusedBottom > frameBottom then
				canvasY += (focusedBottom - frameBottom) + 4
			end

			scrollingFrame.CanvasPosition = Vector2.new(scrollingFrame.CanvasPosition.X, math.max(0, canvasY))
			return
		end
		ancestor = ancestor.Parent
	end
end

function GamepadNav._focusIndex(self: GamepadNav, indexRaw: any): boolean
	local layout = self:_getActiveLayout()
	if layout == nil then
		return false
	end
	local count = #layout.elements
	if count <= 0 then
		return false
	end
	local index = clampInteger(indexRaw, 1, 1, count)

	local candidate = layout.elements[index]
	if candidate == nil or not isSelectable(candidate) then
		local found = nil
		for step = 0, count - 1 do
			local probe = ((index + step - 1) % count) + 1
			local probeGui = layout.elements[probe]
			if probeGui ~= nil and isSelectable(probeGui) then
				found = probe
				break
			end
		end
		if found == nil then
			return false
		end
		index = found
		candidate = layout.elements[index]
	end

	local previous = GuiService.SelectedObject
	GuiService.SelectedObject = candidate
	self.activeIndex = index
	self.lastFocusedByLayout[layout.key] = index
	self:_ensureVisibleInScroll(candidate)
	self:_emitFocusChanged(candidate, previous)
	return true
end

function GamepadNav._moveLinear(self: GamepadNav, direction: NavDirection): boolean
	local layout = self:_getActiveLayout()
	if layout == nil then
		return false
	end
	local count = #layout.elements
	if count <= 0 then
		return false
	end
	local step = if direction == "Left" or direction == "Up" then -1 else 1
	local nextIndex = self.activeIndex + step
	if nextIndex < 1 then
		nextIndex = if layout.wrap then count else 1
	elseif nextIndex > count then
		nextIndex = if layout.wrap then 1 else count
	end
	return self:_focusIndex(nextIndex)
end

function GamepadNav._moveGrid(self: GamepadNav, direction: NavDirection): boolean
	local layout = self:_getActiveLayout()
	if layout == nil then
		return false
	end
	local count = #layout.elements
	if count <= 0 then
		return false
	end
	local columns = math.max(1, layout.columns)
	local index = if self.activeIndex > 0 then self.activeIndex else 1
	local row = math.floor((index - 1) / columns)
	local col = (index - 1) % columns

	if direction == "Left" then
		col -= 1
	elseif direction == "Right" then
		col += 1
	elseif direction == "Up" then
		row -= 1
	else
		row += 1
	end

	local maxRow = math.floor((count - 1) / columns)
	if layout.wrap then
		if col < 0 then
			col = columns - 1
		elseif col >= columns then
			col = 0
		end
		if row < 0 then
			row = maxRow
		elseif row > maxRow then
			row = 0
		end
	else
		col = math.clamp(col, 0, columns - 1)
		row = math.clamp(row, 0, maxRow)
	end

	local nextIndex = row * columns + col + 1
	if nextIndex > count then
		nextIndex = count
	end
	return self:_focusIndex(nextIndex)
end

function GamepadNav._move(self: GamepadNav, direction: NavDirection): boolean
	local now = os.clock()
	if now - self.lastMoveAt < self.moveRepeatCooldown then
		return false
	end
	self.lastMoveAt = now
	local layout = self:_getActiveLayout()
	if layout == nil then
		return false
	end
	if layout.mode == "Grid" then
		return self:_moveGrid(direction)
	end
	return self:_moveLinear(direction)
end

function GamepadNav._handleThumbstick(self: GamepadNav, vector: Vector2)
	local x = vector.X
	local y = vector.Y
	local absX = math.abs(x)
	local absY = math.abs(y)
	if absX <= 1e-4 and absY <= 1e-4 then
		self.lastStickDirX = 0
		self.lastStickDirY = 0
		return
	end

	if absX >= absY then
		local dir = if x > 0 then 1 else -1
		if self.lastStickDirX ~= dir then
			self.lastStickDirX = dir
			self.lastStickDirY = 0
			self:_move(if dir > 0 then "Right" else "Left")
		end
	else
		local dir = if y > 0 then 1 else -1
		if self.lastStickDirY ~= dir then
			self.lastStickDirY = dir
			self.lastStickDirX = 0
			self:_move(if dir > 0 then "Down" else "Up")
		end
	end
end

function GamepadNav._setThumbstickSnapshot(
	self: GamepadNav,
	nextLeft: ThumbstickState,
	nextRight: ThumbstickState
): boolean
	local nextDominant = resolveDominantThumbstick(nextLeft, nextRight)
	if
		thumbstickStatesEqual(self.thumbstickSnapshot.left, nextLeft)
		and thumbstickStatesEqual(self.thumbstickSnapshot.right, nextRight)
		and self.thumbstickSnapshot.dominant == nextDominant
	then
		return false
	end

	self.thumbstickSnapshot.left = nextLeft
	self.thumbstickSnapshot.right = nextRight
	self.thumbstickSnapshot.dominant = nextDominant
	self.thumbstickSnapshot.lastUpdatedAt = os.clock()
	self.thumbstickSnapshot.stickDeadzone = self.stickDeadzone
	self.thumbstickSnapshot.navigationDeadzone = self.navigationDeadzone
	self:_emitThumbstickChanged()
	return true
end

function GamepadNav._setThumbstickState(self: GamepadNav, key: ThumbstickKey, nextState: ThumbstickState): boolean
	local currentLeft = self.thumbstickSnapshot.left
	local currentRight = self.thumbstickSnapshot.right
	local nextLeft = if key == "Left" then nextState else currentLeft
	local nextRight = if key == "Right" then nextState else currentRight
	return self:_setThumbstickSnapshot(nextLeft, nextRight)
end

function GamepadNav._updateThumbstick(self: GamepadNav, key: ThumbstickKey, input: InputObject)
	local nextState = createThumbstickStateFromInput(key, input, self.stickDeadzone)
	if nextState == nil then
		return
	end

	self:_setThumbstickState(key, nextState)
end

function GamepadNav._refreshThumbsticks(self: GamepadNav, gamepadType: Enum.UserInputType): boolean
	local ok, gamepadState = pcall(function()
		return UserInputService:GetGamepadState(gamepadType)
	end)
	if not ok or typeof(gamepadState) ~= "table" then
		return false
	end

	local nextLeft = createThumbstickState("Left")
	local nextRight = createThumbstickState("Right")
	local foundThumbstick = false
	for _, inputRaw in gamepadState do
		local input = if typeof(inputRaw) == "InputObject" then inputRaw :: InputObject else nil
		if input == nil then
			continue
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local nextState = createThumbstickStateFromInput("Left", input, self.stickDeadzone)
			if nextState ~= nil then
				nextLeft = nextState
				foundThumbstick = true
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local nextState = createThumbstickStateFromInput("Right", input, self.stickDeadzone)
			if nextState ~= nil then
				nextRight = nextState
				foundThumbstick = true
			end
		end
	end

	if not foundThumbstick then
		return false
	end
	self:_setThumbstickSnapshot(nextLeft, nextRight)
	return true
end

function GamepadNav._getNavigationVector(self: GamepadNav, input: InputObject): Vector2
	return resolveInputThumbstickVector(input, self.navigationDeadzone) or Vector2.zero
end

function GamepadNav._resetThumbstick(self: GamepadNav, key: ThumbstickKey)
	self:_setThumbstickState(key, createThumbstickState(key))
end

function GamepadNav._onInputBegan(self: GamepadNav, input: InputObject, gameProcessed: boolean)
	if gameProcessed or not self.isEnabled then
		return
	end
	if not isGamepadInput(input.UserInputType) then
		return
	end

	if input.KeyCode == Enum.KeyCode.DPadUp then
		self:_move("Up")
	elseif input.KeyCode == Enum.KeyCode.DPadDown then
		self:_move("Down")
	elseif input.KeyCode == Enum.KeyCode.DPadLeft then
		self:_move("Left")
	elseif input.KeyCode == Enum.KeyCode.DPadRight then
		self:_move("Right")
	elseif input.KeyCode == Enum.KeyCode.ButtonA then
		if GuiService:GetAttribute(GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE) == true then
			return
		end
		local focused = GuiService.SelectedObject
		if focused ~= nil and focused:IsA("GuiButton") then
			focused:Activate()
		elseif self.onActivate ~= nil then
			self.onActivate(focused)
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonB then
		if self.onBack ~= nil then
			self.onBack()
		end
	end
end

function GamepadNav._onInputChanged(self: GamepadNav, input: InputObject)
	if not self.isEnabled then
		return
	end
	if not isGamepadInput(input.UserInputType) then
		return
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		if not self:_refreshThumbsticks(input.UserInputType) then
			self:_updateThumbstick("Left", input)
		end
		if self.navigationStickKeyCode == Enum.KeyCode.Thumbstick1 then
			self:_handleThumbstick(self:_getNavigationVector(input))
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		if not self:_refreshThumbsticks(input.UserInputType) then
			self:_updateThumbstick("Right", input)
		end
		if self.navigationStickKeyCode == Enum.KeyCode.Thumbstick2 then
			self:_handleThumbstick(self:_getNavigationVector(input))
		end
	end
end

function GamepadNav._onInputEnded(self: GamepadNav, input: InputObject)
	if not self.isEnabled then
		return
	end
	if not isGamepadInput(input.UserInputType) then
		return
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		if not self:_refreshThumbsticks(input.UserInputType) then
			self:_resetThumbstick("Left")
		end
		if self.navigationStickKeyCode == Enum.KeyCode.Thumbstick1 then
			self:_handleThumbstick(Vector2.zero)
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		if not self:_refreshThumbsticks(input.UserInputType) then
			self:_resetThumbstick("Right")
		end
		if self.navigationStickKeyCode == Enum.KeyCode.Thumbstick2 then
			self:_handleThumbstick(Vector2.zero)
		end
	end
end

function GamepadNav.Init(self: GamepadNav)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.connections[#self.connections + 1] = UserInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			self:_onInputBegan(input, gameProcessed)
		end
	)
	self.connections[#self.connections + 1] = UserInputService.InputChanged:Connect(function(input: InputObject)
		self:_onInputChanged(input)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputEnded:Connect(function(input: InputObject)
		self:_onInputEnded(input)
	end)
end

function GamepadNav.RegisterLayout(self: GamepadNav, keyRaw: any, elementsRaw: any, configRaw: LayoutConfig?): boolean
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return false
	end
	if typeof(elementsRaw) ~= "table" then
		return false
	end
	local elements = {}
	for index = 1, #elementsRaw do
		local item = elementsRaw[index]
		if typeof(item) == "Instance" and item:IsA("GuiObject") then
			elements[#elements + 1] = item
		end
	end
	if #elements == 0 then
		return false
	end
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local record: LayoutRecord = {
		key = keyRaw,
		elements = elements,
		mode = if config.mode == "Grid" then "Grid" else "Linear",
		columns = clampInteger(config.columns, 1, 1, 32),
		wrap = if config.wrap == nil then true else config.wrap == true,
	}
	if self.layouts[keyRaw] == nil then
		self.layoutOrder[#self.layoutOrder + 1] = keyRaw
	end
	self.layouts[keyRaw] = record
	return true
end

function GamepadNav.UnregisterLayout(self: GamepadNav, keyRaw: any): boolean
	if typeof(keyRaw) ~= "string" then
		return false
	end
	if self.layouts[keyRaw] == nil then
		return false
	end
	self.layouts[keyRaw] = nil
	for index = #self.layoutOrder, 1, -1 do
		if self.layoutOrder[index] == keyRaw then
			table.remove(self.layoutOrder, index)
			break
		end
	end
	if self.activeLayoutKey == keyRaw then
		self.activeLayoutKey = nil
		self.activeIndex = 0
		GuiService.SelectedObject = nil
	end
	return true
end

function GamepadNav.SetLayout(self: GamepadNav, keyRaw: any, restoreRaw: any?): boolean
	if typeof(keyRaw) ~= "string" then
		return false
	end
	local layout = self.layouts[keyRaw]
	if layout == nil then
		return false
	end
	self.activeLayoutKey = keyRaw
	local restore = if restoreRaw == nil then true else restoreRaw == true
	local startIndex = if restore then (self.lastFocusedByLayout[keyRaw] or 1) else 1
	return self:_focusIndex(startIndex)
end

function GamepadNav.GetActiveElements(self: GamepadNav): { GuiObject }
	local layout = self:_getActiveLayout()
	if layout == nil then
		return {}
	end
	return Sift.Dictionary.copy(layout.elements)
end

function GamepadNav.GetFocused(_self: GamepadNav): GuiObject?
	return GuiService.SelectedObject
end

function GamepadNav.Move(self: GamepadNav, directionRaw: any): boolean
	if typeof(directionRaw) ~= "string" then
		return false
	end
	local direction = directionRaw :: NavDirection
	if direction ~= "Up" and direction ~= "Down" and direction ~= "Left" and direction ~= "Right" then
		return false
	end
	return self:_move(direction)
end

function GamepadNav.FocusIndex(self: GamepadNav, indexRaw: any): boolean
	return self:_focusIndex(indexRaw)
end

function GamepadNav.OnFocusChanged(self: GamepadNav, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.focusChangedSignal:Connect(callbackRaw :: FocusCallback)
	return function()
		connection:Disconnect()
	end
end

function GamepadNav.GetThumbstickState(self: GamepadNav): ThumbstickSnapshot
	return cloneThumbstickSnapshot(self.thumbstickSnapshot)
end

function GamepadNav.OnThumbstickChanged(self: GamepadNav, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.thumbstickChangedSignal:Connect(callbackRaw :: ThumbstickChangedCallback)
	return function()
		connection:Disconnect()
	end
end

function GamepadNav.SetEnabled(self: GamepadNav, enabledRaw: any)
	self.isEnabled = enabledRaw == true
	if not self.isEnabled then
		GuiService.SelectedObject = nil
	end
end

function GamepadNav.Destroy(self: GamepadNav)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	table.clear(self.layouts)
	table.clear(self.layoutOrder)
	table.clear(self.lastFocusedByLayout)
	self.focusChangedSignal:DisconnectAll()
	self.focusChangedSignal:Destroy()
	self.thumbstickChangedSignal:DisconnectAll()
	self.thumbstickChangedSignal:Destroy()
	self.activeLayoutKey = nil
	self.activeIndex = 0
	self.isInitialized = false
end

GamepadNav.RegisterLayout = GamepadNav.RegisterLayout
GamepadNav.UnregisterLayout = GamepadNav.UnregisterLayout
GamepadNav.SetLayout = GamepadNav.SetLayout
GamepadNav.GetActiveElements = GamepadNav.GetActiveElements
GamepadNav.GetFocused = GamepadNav.GetFocused
GamepadNav.Move = GamepadNav.Move
GamepadNav.FocusIndex = GamepadNav.FocusIndex
GamepadNav.OnFocusChanged = GamepadNav.OnFocusChanged
GamepadNav.GetThumbstickState = GamepadNav.GetThumbstickState
GamepadNav.OnThumbstickChanged = GamepadNav.OnThumbstickChanged
GamepadNav.ResolveRemappedDeadzoneMagnitude = GamepadNav.ResolveRemappedDeadzoneMagnitude
GamepadNav.SetEnabled = GamepadNav.SetEnabled
GamepadNav.Init = GamepadNav.Init
GamepadNav.Destroy = GamepadNav.Destroy

GamepadNav.new = GamepadNav.New
GamepadNav.init = GamepadNav.Init
GamepadNav.registerLayout = GamepadNav.RegisterLayout
GamepadNav.unregisterLayout = GamepadNav.UnregisterLayout
GamepadNav.setLayout = GamepadNav.SetLayout
GamepadNav.getActiveElements = GamepadNav.GetActiveElements
GamepadNav.getFocused = GamepadNav.GetFocused
GamepadNav.move = GamepadNav.Move
GamepadNav.focusIndex = GamepadNav.FocusIndex
GamepadNav.onFocusChanged = GamepadNav.OnFocusChanged
GamepadNav.getThumbstickState = GamepadNav.GetThumbstickState
GamepadNav.onThumbstickChanged = GamepadNav.OnThumbstickChanged
GamepadNav.resolveRemappedDeadzoneMagnitude = GamepadNav.ResolveRemappedDeadzoneMagnitude
GamepadNav.setEnabled = GamepadNav.SetEnabled
GamepadNav.destroy = GamepadNav.Destroy

return GamepadNav
