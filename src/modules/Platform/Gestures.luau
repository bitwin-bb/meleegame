--!strict
local UserInputService = game:GetService("UserInputService")

local Gestures = {}
Gestures.__index = Gestures

export type GestureType =
	"Tap"
	| "DoubleTap"
	| "LongPress"
	| "DragStart"
	| "Drag"
	| "DragEnd"
	| "Swipe"
	| "PinchStart"
	| "Pinch"
	| "PinchEnd"

export type GesturePayload = {
	gesture: GestureType,
	position: Vector2?,
	startPosition: Vector2?,
	delta: Vector2?,
	duration: number?,
	target: GuiObject?,
	direction: string?,
	scale: number?,
	center: Vector2?,
}

export type GestureCallback = (payload: GesturePayload) -> ()

export type GesturesConfig = {
	eventBus: any?,
	eventChannel: string?,
	tickScheduler: any?,
	tapMaxDuration: number?,
	doubleTapWindow: number?,
	longPressTime: number?,
	dragThreshold: number?,
	swipeMinDistance: number?,
	swipeMaxDuration: number?,
	pinchThreshold: number?,
}

type TouchState = {
	input: InputObject?,
	startPos: Vector2,
	lastPos: Vector2,
	startTime: number,
	lastTime: number,
	movedDistance: number,
	dragging: boolean,
	longPressTriggered: boolean,
	pinchLocked: boolean,
	longPressCancel: (() -> ())?,
	target: GuiObject?,
}

export type Gestures = typeof(setmetatable({} :: any, Gestures))

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

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function vectorDistance(a: Vector2, b: Vector2): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	return math.sqrt(dx * dx + dy * dy)
end

local function getSwipeDirection(delta: Vector2): string
	local absX = math.abs(delta.X)
	local absY = math.abs(delta.Y)
	if absX >= absY then
		return if delta.X >= 0 then "Right" else "Left"
	end
	return if delta.Y >= 0 then "Down" else "Up"
end

local function clearTouchState(state: TouchState)
	state.input = nil
	state.startPos = Vector2.zero
	state.lastPos = Vector2.zero
	state.startTime = 0
	state.lastTime = 0
	state.movedDistance = 0
	state.dragging = false
	state.longPressTriggered = false
	state.pinchLocked = false
	state.longPressCancel = nil
	state.target = nil
end

function Gestures.new(configRaw: GesturesConfig?): Gestures
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "gestures"),
		tickScheduler = config.tickScheduler,
		tapMaxDuration = clampNumber(config.tapMaxDuration, 0.24, 0.05, 2),
		doubleTapWindow = clampNumber(config.doubleTapWindow, 0.28, 0.05, 2),
		longPressTime = clampNumber(config.longPressTime, 0.45, 0.1, 5),
		dragThreshold = clampNumber(config.dragThreshold, 10, 1, 250),
		swipeMinDistance = clampNumber(config.swipeMinDistance, 64, 8, 1000),
		swipeMaxDuration = clampNumber(config.swipeMaxDuration, 0.45, 0.05, 2),
		pinchThreshold = clampNumber(config.pinchThreshold, 0.02, 0.001, 1),
		touches = {} :: { [InputObject]: TouchState },
		activeTouchCount = 0,
		touchPool = {} :: { TouchState },
		listeners = {} :: { [string]: { [number]: GestureCallback } },
		nextListenerId = 0,
		connections = {} :: { RBXScriptConnection? },
		isInitialized = false,
		isEnabled = true,
		lastTapTime = 0,
		lastTapPos = Vector2.zero,
		pendingTapToken = nil :: (() -> ())?,
		pinchTouchA = nil :: InputObject?,
		pinchTouchB = nil :: InputObject?,
		pinchInitialDistance = 0,
		pinchActive = false,
	}, Gestures)
	return self
end

function Gestures._acquireTouchState(self: Gestures): TouchState
	local pooled = table.remove(self.touchPool)
	if pooled ~= nil then
		return pooled
	end
	return {
		input = nil,
		startPos = Vector2.zero,
		lastPos = Vector2.zero,
		startTime = 0,
		lastTime = 0,
		movedDistance = 0,
		dragging = false,
		longPressTriggered = false,
		pinchLocked = false,
		longPressCancel = nil,
		target = nil,
	}
end

function Gestures._releaseTouchState(self: Gestures, state: TouchState)
	clearTouchState(state)
	if #self.touchPool < 32 then
		self.touchPool[#self.touchPool + 1] = state
	end
end

function Gestures._emit(self: Gestures, gesture: GestureType, payload: GesturePayload)
	local bucket = self.listeners[gesture]
	if bucket ~= nil then
		for _, callback in bucket do
			callback(payload)
		end
	end
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, gesture, payload)
	end
end

function Gestures._scheduleLongPress(self: Gestures, input: InputObject, state: TouchState)
	local function fireLongPress()
		local runtimeState = self.touches[input]
		if runtimeState == nil then
			return
		end
		if runtimeState.longPressTriggered then
			return
		end
		if runtimeState.pinchLocked then
			return
		end
		if runtimeState.movedDistance > self.dragThreshold then
			return
		end
		runtimeState.longPressTriggered = true
		self:_emit("LongPress", {
			gesture = "LongPress",
			position = runtimeState.lastPos,
			startPosition = runtimeState.startPos,
			duration = os.clock() - runtimeState.startTime,
			target = runtimeState.target,
		})
	end

	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).schedule) == "function" then
		local token = (self.tickScheduler :: any):schedule(function()
			fireLongPress()
		end, self.longPressTime, {
			group = "gestures.longpress",
			priority = 200,
		})
		state.longPressCancel = function()
			if typeof(token.cancel) == "function" then
				token:cancel()
			elseif typeof((self.tickScheduler :: any).cancel) == "function" then
				local schedulerAny = self.tickScheduler :: any
				schedulerAny:cancel(token)
			end
		end
		return
	end

	local cancelled = false
	state.longPressCancel = function()
		cancelled = true
	end
	task.delay(self.longPressTime, function()
		if cancelled then
			return
		end
		fireLongPress()
	end)
end

function Gestures._activeTouches(self: Gestures): (InputObject?, InputObject?)
	local first: InputObject? = nil
	local second: InputObject? = nil
	for input in self.touches do
		if first == nil then
			first = input
		elseif second == nil then
			second = input
			break
		end
	end
	return first, second
end

function Gestures._enterPinch(self: Gestures, inputA: InputObject, inputB: InputObject)
	local stateA = self.touches[inputA]
	local stateB = self.touches[inputB]
	if stateA == nil or stateB == nil then
		return
	end
	stateA.pinchLocked = true
	stateB.pinchLocked = true
	self.pinchTouchA = inputA
	self.pinchTouchB = inputB
	self.pinchInitialDistance = vectorDistance(stateA.lastPos, stateB.lastPos)
	self.pinchActive = true
	self:_emit("PinchStart", {
		gesture = "PinchStart",
		center = (stateA.lastPos + stateB.lastPos) * 0.5,
		scale = 1,
	})
end

function Gestures._updatePinch(self: Gestures)
	if not self.pinchActive then
		return
	end
	local inputA = self.pinchTouchA
	local inputB = self.pinchTouchB
	if inputA == nil or inputB == nil then
		return
	end
	local stateA = self.touches[inputA]
	local stateB = self.touches[inputB]
	if stateA == nil or stateB == nil then
		return
	end
	local currentDistance = vectorDistance(stateA.lastPos, stateB.lastPos)
	if self.pinchInitialDistance <= 0 then
		self.pinchInitialDistance = currentDistance
		return
	end
	local scale = currentDistance / self.pinchInitialDistance
	if math.abs(scale - 1) < self.pinchThreshold then
		return
	end
	self:_emit("Pinch", {
		gesture = "Pinch",
		center = (stateA.lastPos + stateB.lastPos) * 0.5,
		scale = scale,
	})
end

function Gestures._exitPinch(self: Gestures)
	if not self.pinchActive then
		return
	end
	self.pinchActive = false
	self.pinchTouchA = nil
	self.pinchTouchB = nil
	self.pinchInitialDistance = 0
	self:_emit("PinchEnd", {
		gesture = "PinchEnd",
	})
end

function Gestures._beginTouch(self: Gestures, input: InputObject)
	local state = self:_acquireTouchState()
	state.input = input
	state.startPos = input.Position
	state.lastPos = input.Position
	state.startTime = os.clock()
	state.lastTime = state.startTime
	state.target = if typeof(input.Target) == "Instance" and input.Target:IsA("GuiObject") then input.Target else nil

	self.touches[input] = state
	self.activeTouchCount += 1
	self:_scheduleLongPress(input, state)

	if self.activeTouchCount == 2 then
		local a, b = self:_activeTouches()
		if a ~= nil and b ~= nil then
			self:_enterPinch(a, b)
		end
	end
end

function Gestures._changeTouch(self: Gestures, input: InputObject)
	local state = self.touches[input]
	if state == nil then
		return
	end
	local current = input.Position
	local delta = current - state.lastPos
	state.movedDistance += delta.Magnitude
	state.lastPos = current
	state.lastTime = os.clock()

	if self.pinchActive then
		self:_updatePinch()
		return
	end
	if state.pinchLocked then
		return
	end

	if not state.dragging and vectorDistance(state.startPos, current) >= self.dragThreshold then
		state.dragging = true
		self:_emit("DragStart", {
			gesture = "DragStart",
			position = current,
			startPosition = state.startPos,
			delta = delta,
			target = state.target,
		})
	end
	if state.dragging then
		self:_emit("Drag", {
			gesture = "Drag",
			position = current,
			startPosition = state.startPos,
			delta = delta,
			duration = state.lastTime - state.startTime,
			target = state.target,
		})
	end
end

function Gestures._scheduleTapEmit(self: Gestures, payload: GesturePayload)
	if self.pendingTapToken ~= nil then
		self.pendingTapToken()
		self.pendingTapToken = nil
	end
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).schedule) == "function" then
		local cancelled = false
		local token = (self.tickScheduler :: any):schedule(function()
			if cancelled then
				return
			end
			self:_emit("Tap", payload)
		end, self.doubleTapWindow, {
			group = "gestures.tap",
			priority = 150,
		})
		self.pendingTapToken = function()
			cancelled = true
			if typeof(token.cancel) == "function" then
				token:cancel()
			elseif typeof((self.tickScheduler :: any).cancel) == "function" then
				local schedulerAny = self.tickScheduler :: any
				schedulerAny:cancel(token)
			end
		end
		return
	end
	local cancelled = false
	self.pendingTapToken = function()
		cancelled = true
	end
	task.delay(self.doubleTapWindow, function()
		if cancelled then
			return
		end
		self:_emit("Tap", payload)
	end)
end

function Gestures._endTouch(self: Gestures, input: InputObject)
	local state = self.touches[input]
	if state == nil then
		return
	end
	local now = os.clock()
	local duration = now - state.startTime
	local delta = state.lastPos - state.startPos
	local distance = delta.Magnitude

	if state.longPressCancel ~= nil then
		state.longPressCancel()
	end

	if self.pinchActive and (input == self.pinchTouchA or input == self.pinchTouchB) then
		self:_exitPinch()
	end

	if state.dragging then
		self:_emit("DragEnd", {
			gesture = "DragEnd",
			position = state.lastPos,
			startPosition = state.startPos,
			delta = delta,
			duration = duration,
			target = state.target,
		})
	end

	if (not state.pinchLocked) and (not state.longPressTriggered) then
		if duration <= self.swipeMaxDuration and distance >= self.swipeMinDistance then
			self:_emit("Swipe", {
				gesture = "Swipe",
				position = state.lastPos,
				startPosition = state.startPos,
				delta = delta,
				duration = duration,
				direction = getSwipeDirection(delta),
				target = state.target,
			})
		elseif duration <= self.tapMaxDuration and distance <= self.dragThreshold then
			local isDoubleTap = (now - self.lastTapTime) <= self.doubleTapWindow and vectorDistance(self.lastTapPos, state.lastPos) <= (self.dragThreshold * 1.5)
			if isDoubleTap then
				if self.pendingTapToken ~= nil then
					self.pendingTapToken()
					self.pendingTapToken = nil
				end
				self:_emit("DoubleTap", {
					gesture = "DoubleTap",
					position = state.lastPos,
					startPosition = state.startPos,
					duration = duration,
					target = state.target,
				})
				self.lastTapTime = 0
			else
				self.lastTapTime = now
				self.lastTapPos = state.lastPos
				self:_scheduleTapEmit({
					gesture = "Tap",
					position = state.lastPos,
					startPosition = state.startPos,
					duration = duration,
					target = state.target,
				})
			end
		end
	end

	self.touches[input] = nil
	self.activeTouchCount -= 1
	self:_releaseTouchState(state)
end

function Gestures._onInputBegan(self: Gestures, input: InputObject)
	if not self.isEnabled then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	self:_beginTouch(input)
end

function Gestures._onInputChanged(self: Gestures, input: InputObject)
	if not self.isEnabled then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	self:_changeTouch(input)
end

function Gestures._onInputEnded(self: Gestures, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	self:_endTouch(input)
end

function Gestures.init(self: Gestures)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.connections[#self.connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject)
		self:_onInputBegan(input)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputChanged:Connect(function(input: InputObject)
		self:_onInputChanged(input)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputEnded:Connect(function(input: InputObject)
		self:_onInputEnded(input)
	end)
end

function Gestures.bind(self: Gestures, gestureRaw: any, callbackRaw: any): () -> ()
	if typeof(gestureRaw) ~= "string" or gestureRaw == "" then
		return function() end
	end
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local gesture = gestureRaw :: string
	local bucket = self.listeners[gesture]
	if bucket == nil then
		bucket = {}
		self.listeners[gesture] = bucket
	end
	self.nextListenerId += 1
	local id = self.nextListenerId
	bucket[id] = callbackRaw
	return function()
		local runtime = self.listeners[gesture]
		if runtime == nil then
			return
		end
		runtime[id] = nil
		if next(runtime) == nil then
			self.listeners[gesture] = nil
		end
	end
end

function Gestures.setEnabled(self: Gestures, enabledRaw: any)
	self.isEnabled = enabledRaw == true
end

function Gestures.destroy(self: Gestures)
	if self.pendingTapToken ~= nil then
		self.pendingTapToken()
		self.pendingTapToken = nil
	end
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	for input, state in self.touches do
		if state.longPressCancel ~= nil then
			state.longPressCancel()
		end
		self.touches[input] = nil
		self:_releaseTouchState(state)
	end
	table.clear(self.listeners)
	self:_exitPinch()
	self.isInitialized = false
end

Gestures.Bind = Gestures.bind
Gestures.SetEnabled = Gestures.setEnabled
Gestures.Init = Gestures.init
Gestures.Destroy = Gestures.destroy

return Gestures
