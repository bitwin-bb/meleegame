--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local GamepadNav = {}
GamepadNav.__index = GamepadNav

export type NavDirection = "Up" | "Down" | "Left" | "Right"

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
	tooltipManager: any?,
	onActivate: ((focused: GuiObject?) -> ())?,
	onBack: (() -> ())?,
	onFocusChanged: FocusCallback?,
	moveRepeatCooldown: number?,
	stickDeadzone: number?,
}

type LayoutRecord = {
	key: string,
	elements: { GuiObject },
	mode: "Linear" | "Grid",
	columns: number,
	wrap: boolean,
}

export type GamepadNav = typeof(setmetatable({} :: any, GamepadNav))

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

function GamepadNav.new(configRaw: GamepadNavConfig?): GamepadNav
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "gamepad.nav"),
		focusEvent = normalizeEventName(config.focusEvent, "focusChanged"),
		tooltipManager = config.tooltipManager,
		onActivate = if typeof(config.onActivate) == "function" then config.onActivate else nil,
		onBack = if typeof(config.onBack) == "function" then config.onBack else nil,
		externalFocusChanged = if typeof(config.onFocusChanged) == "function" then config.onFocusChanged else nil,
		moveRepeatCooldown = clampNumber(config.moveRepeatCooldown, 0.12, 0.02, 1),
		stickDeadzone = clampNumber(config.stickDeadzone, 0.35, 0, 1),
		layouts = {} :: { [string]: LayoutRecord },
		layoutOrder = {} :: { string },
		activeLayoutKey = nil :: string?,
		activeIndex = 0,
		lastFocusedByLayout = {} :: { [string]: number },
		focusListeners = {} :: { [number]: FocusCallback },
		nextListenerId = 0,
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
	for _, callback in self.focusListeners do
		callback(nextFocused, prevFocused)
	end
	if self.tooltipManager ~= nil and typeof((self.tooltipManager :: any).hide) == "function" and nextFocused == nil then
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

function GamepadNav._ensureVisibleInScroll(self: GamepadNav, focused: GuiObject?)
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

function GamepadNav._handleThumbstick(self: GamepadNav, input: InputObject)
	local pos = input.Position
	if typeof(pos) ~= "Vector3" then
		return
	end
	local x = pos.X
	local y = pos.Y
	local absX = math.abs(x)
	local absY = math.abs(y)
	if absX < self.stickDeadzone and absY < self.stickDeadzone then
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
		self:_handleThumbstick(input)
	end
end

function GamepadNav.init(self: GamepadNav)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.connections[#self.connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_onInputBegan(input, gameProcessed)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputChanged:Connect(function(input: InputObject)
		self:_onInputChanged(input)
	end)
end

function GamepadNav.registerLayout(self: GamepadNav, keyRaw: any, elementsRaw: any, configRaw: LayoutConfig?): boolean
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

function GamepadNav.unregisterLayout(self: GamepadNav, keyRaw: any): boolean
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

function GamepadNav.setLayout(self: GamepadNav, keyRaw: any, restoreRaw: any?): boolean
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

function GamepadNav.getActiveElements(self: GamepadNav): { GuiObject }
	local layout = self:_getActiveLayout()
	if layout == nil then
		return {}
	end
	return table.clone(layout.elements)
end

function GamepadNav.getFocused(self: GamepadNav): GuiObject?
	return GuiService.SelectedObject
end

function GamepadNav.move(self: GamepadNav, directionRaw: any): boolean
	if typeof(directionRaw) ~= "string" then
		return false
	end
	local direction = directionRaw :: NavDirection
	if direction ~= "Up" and direction ~= "Down" and direction ~= "Left" and direction ~= "Right" then
		return false
	end
	return self:_move(direction)
end

function GamepadNav.focusIndex(self: GamepadNav, indexRaw: any): boolean
	return self:_focusIndex(indexRaw)
end

function GamepadNav.onFocusChanged(self: GamepadNav, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	self.nextListenerId += 1
	local id = self.nextListenerId
	self.focusListeners[id] = callbackRaw
	return function()
		self.focusListeners[id] = nil
	end
end

function GamepadNav.setEnabled(self: GamepadNav, enabledRaw: any)
	self.isEnabled = enabledRaw == true
	if not self.isEnabled then
		GuiService.SelectedObject = nil
	end
end

function GamepadNav.destroy(self: GamepadNav)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	table.clear(self.layouts)
	table.clear(self.layoutOrder)
	table.clear(self.lastFocusedByLayout)
	table.clear(self.focusListeners)
	self.activeLayoutKey = nil
	self.activeIndex = 0
	self.isInitialized = false
end

GamepadNav.RegisterLayout = GamepadNav.registerLayout
GamepadNav.UnregisterLayout = GamepadNav.unregisterLayout
GamepadNav.SetLayout = GamepadNav.setLayout
GamepadNav.GetActiveElements = GamepadNav.getActiveElements
GamepadNav.GetFocused = GamepadNav.getFocused
GamepadNav.Move = GamepadNav.move
GamepadNav.FocusIndex = GamepadNav.focusIndex
GamepadNav.OnFocusChanged = GamepadNav.onFocusChanged
GamepadNav.SetEnabled = GamepadNav.setEnabled
GamepadNav.Init = GamepadNav.init
GamepadNav.Destroy = GamepadNav.destroy

return GamepadNav
