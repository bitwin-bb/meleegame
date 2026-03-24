--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Cursor = {}
Cursor.__index = Cursor

export type CursorState = {
	enabled: boolean,
	visible: boolean,
	mouseDown: boolean,
	screenPosition: Vector2,
	guiPosition: Vector2,
	isHoveringGui: boolean,
	hoveredGuiPath: string?,
}

export type CursorConfig = {
	input: any?,
	eventBus: any?,
	eventChannel: string?,
	changeEvent: string?,
	tickScheduler: any?,
	useCustomIcon: boolean?,
}

export type Cursor = typeof(setmetatable({} :: any, Cursor))

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

local function isMouseButtonInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
end

local function isPointerMoveInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

local function toGuiPosition(screenPosition: Vector2): Vector2
	local topLeftInset, _ = GuiService:GetGuiInset()
	if topLeftInset.X == 0 and topLeftInset.Y == 0 then
		return screenPosition
	end
	return screenPosition
end

local function getPlayerGui(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui ~= nil and playerGui:IsA("PlayerGui") then
		return playerGui
	end
	return nil
end

local function isCustomCursorGui(guiObject: GuiObject): boolean
	local current: Instance? = guiObject
	while current do
		if current:GetAttribute("IsCustomMouseCursor") == true then
			return true
		end
		if current.Name == "MouseScreenRoot" or current.Name == "MouseCursorImage" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isHoverTarget(guiObject: GuiObject): boolean
	if not guiObject.Visible then
		return false
	end
	if isCustomCursorGui(guiObject) then
		return false
	end
	if guiObject:IsA("GuiButton") then
		return true
	end
	if guiObject:IsA("TextBox") then
		return true
	end
	if guiObject.Active then
		return true
	end
	if guiObject.Selectable then
		return true
	end
	return false
end

local function resolveHoveredGuiObject(guiPosition: Vector2): GuiObject?
	local playerGui = getPlayerGui()
	if playerGui == nil then
		return nil
	end
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(math.floor(guiPosition.X), math.floor(guiPosition.Y))
	end)
	if not ok or type(objects) ~= "table" then
		return nil
	end
	for _, guiObject in objects do
		if guiObject:IsA("GuiObject") and isHoverTarget(guiObject) then
			return guiObject
		end
	end
	return nil
end

local function cloneState(state: CursorState): CursorState
	return {
		enabled = state.enabled,
		visible = state.visible,
		mouseDown = state.mouseDown,
		screenPosition = state.screenPosition,
		guiPosition = state.guiPosition,
		isHoveringGui = state.isHoveringGui,
		hoveredGuiPath = state.hoveredGuiPath,
	}
end

local function statesEqual(a: CursorState, b: CursorState): boolean
	return a.enabled == b.enabled
		and a.visible == b.visible
		and a.mouseDown == b.mouseDown
		and a.screenPosition == b.screenPosition
		and a.guiPosition == b.guiPosition
		and a.isHoveringGui == b.isHoveringGui
		and a.hoveredGuiPath == b.hoveredGuiPath
end

function Cursor.new(configRaw: CursorConfig?): Cursor
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local defaultScreenPosition = Vector2.zero
	local ok, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(mouseLocation) == "Vector2" then
		defaultScreenPosition = mouseLocation
	end
	local state = {
		enabled = true,
		visible = UserInputService.MouseEnabled,
		mouseDown = false,
		screenPosition = defaultScreenPosition,
		guiPosition = toGuiPosition(defaultScreenPosition),
		isHoveringGui = false,
		hoveredGuiPath = nil,
	} :: CursorState
	local self = setmetatable({
		input = config.input,
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "cursor"),
		changeEvent = normalizeEventName(config.changeEvent, "changed"),
		tickScheduler = config.tickScheduler,
		useCustomIcon = if config.useCustomIcon == nil then true else config.useCustomIcon == true,
		defaultMouseIconEnabled = nil :: boolean?,
		state = state,
		nextListenerId = 0,
		listeners = {} :: { [number]: (state: CursorState) -> () },
		inputChangedConnection = nil :: RBXScriptConnection?,
		inputBeganConnection = nil :: RBXScriptConnection?,
		inputEndedConnection = nil :: RBXScriptConnection?,
		lastInputTypeChangedConnection = nil :: RBXScriptConnection?,
		stepConnection = nil :: RBXScriptConnection?,
		pollToken = nil,
		boundWithInputModule = false,
		isInitialized = false,
	}, Cursor)
	return self
end

function Cursor._emitChanged(self: Cursor, state: CursorState)
	for _, callback in self.listeners do
		callback(state)
	end
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.changeEvent, state)
	end
end

function Cursor._setState(self: Cursor, partial: { [string]: any })
	local current = self.state
	local nextState: CursorState = {
		enabled = if partial.enabled ~= nil then partial.enabled == true else current.enabled,
		visible = if partial.visible ~= nil then partial.visible == true else current.visible,
		mouseDown = if partial.mouseDown ~= nil then partial.mouseDown == true else current.mouseDown,
		screenPosition = if typeof(partial.screenPosition) == "Vector2" then partial.screenPosition else current.screenPosition,
		guiPosition = if typeof(partial.guiPosition) == "Vector2" then partial.guiPosition else current.guiPosition,
		isHoveringGui = if partial.isHoveringGui ~= nil then partial.isHoveringGui == true else current.isHoveringGui,
		hoveredGuiPath = if typeof(partial.hoveredGuiPath) == "string" and partial.hoveredGuiPath ~= ""
			then partial.hoveredGuiPath
			else if partial.hoveredGuiPath == false
				then nil
				else current.hoveredGuiPath,
	}
	if statesEqual(current, nextState) then
		return
	end
	self.state = nextState
	self:_emitChanged(cloneState(nextState))
end

function Cursor._applyMouseIcon(self: Cursor)
	if self.defaultMouseIconEnabled == nil then
		self.defaultMouseIconEnabled = UserInputService.MouseIconEnabled
	end
	if self.useCustomIcon and self.state.enabled then
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseIconEnabled = if self.defaultMouseIconEnabled ~= nil then self.defaultMouseIconEnabled else true
	end
end

function Cursor._applyFromScreenPosition(self: Cursor, screenPosition: Vector2)
	local guiPosition = toGuiPosition(screenPosition)
	local hoveredGui = resolveHoveredGuiObject(guiPosition)
	self:_setState({
		screenPosition = screenPosition,
		guiPosition = guiPosition,
		isHoveringGui = hoveredGui ~= nil,
		hoveredGuiPath = if hoveredGui ~= nil then hoveredGui:GetFullName() else false,
	})
end

function Cursor._syncFromMouseLocation(self: Cursor)
	local ok, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(mouseLocation) == "Vector2" then
		self:_applyFromScreenPosition(mouseLocation)
	end
end

function Cursor._bindWithInputModule(self: Cursor): boolean
	local input = self.input
	if input == nil or typeof((input :: any).bindAction) ~= "function" then
		return false
	end

	local moveBound = (input :: any):bindAction("Cursor.PointerMove", function(phase: string, context: any)
		if not self.state.enabled then
			return false
		end
		if phase ~= "Changed" and phase ~= "Began" then
			return false
		end
		local inputObject = if typeof(context) == "table" then context.input else nil
		if typeof(inputObject) == "InputObject" and isPointerMoveInput((inputObject :: InputObject).UserInputType) then
			self:_applyFromScreenPosition((inputObject :: InputObject).Position)
		end
		return false
	end, {
		layer = "UI",
		consume = false,
		allowGameProcessed = true,
		allowWhileTyping = true,
		bindings = {
			{ inputType = Enum.UserInputType.MouseMovement },
			{ inputType = Enum.UserInputType.Touch },
		},
	})

	local downBound = (input :: any):bindAction("Cursor.PointerDown", function(phase: string)
		if not self.state.enabled then
			return false
		end
		if phase == "Began" then
			self:_setState({
				mouseDown = true,
			})
		elseif phase == "Ended" then
			self:_setState({
				mouseDown = false,
			})
		end
		return false
	end, {
		layer = "UI",
		consume = false,
		allowGameProcessed = true,
		allowWhileTyping = true,
		bindings = {
			{ inputType = Enum.UserInputType.MouseButton1 },
			{ inputType = Enum.UserInputType.MouseButton2 },
			{ inputType = Enum.UserInputType.MouseButton3 },
		},
	})

	return moveBound == true and downBound == true
end

function Cursor._unbindInputModule(self: Cursor)
	if not self.boundWithInputModule then
		return
	end
	local input = self.input
	if input ~= nil and typeof((input :: any).unbindAction) == "function" then
		local inputAny = input :: any
		inputAny:unbindAction("Cursor.PointerMove")
		inputAny:unbindAction("Cursor.PointerDown")
	end
	self.boundWithInputModule = false
end

function Cursor._bindFallbackConnections(self: Cursor)
	self.inputChangedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
		if not self.state.enabled then
			return
		end
		if isPointerMoveInput(inputObject.UserInputType) then
			self:_applyFromScreenPosition(inputObject.Position)
		end
	end)

	self.inputBeganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject)
		if not self.state.enabled then
			return
		end
		if isMouseButtonInput(inputObject.UserInputType) then
			self:_setState({
				mouseDown = true,
			})
			self:_syncFromMouseLocation()
		end
	end)

	self.inputEndedConnection = UserInputService.InputEnded:Connect(function(inputObject: InputObject)
		if not self.state.enabled then
			return
		end
		if isMouseButtonInput(inputObject.UserInputType) then
			self:_setState({
				mouseDown = false,
			})
			self:_syncFromMouseLocation()
		end
	end)
end

function Cursor._startPolling(self: Cursor)
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).scheduleEvery) == "function" then
		self.pollToken = (self.tickScheduler :: any):scheduleEvery(function()
			if not self.state.enabled or not UserInputService.MouseEnabled then
				return
			end
			self:_syncFromMouseLocation()
		end, 1 / 60, {
			group = "cursor.poll",
			priority = 250,
			catchUp = false,
		})
		return
	end
	self.stepConnection = RunService.RenderStepped:Connect(function()
		if not self.state.enabled or not UserInputService.MouseEnabled then
			return
		end
		self:_syncFromMouseLocation()
	end)
end

function Cursor._stopPolling(self: Cursor)
	if self.pollToken ~= nil then
		if typeof(self.pollToken.cancel) == "function" then
			self.pollToken:cancel()
		elseif self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).cancel) == "function" then
			local schedulerAny = self.tickScheduler :: any
			schedulerAny:cancel(self.pollToken)
		end
		self.pollToken = nil
	end
	safeDisconnect(self.stepConnection)
	self.stepConnection = nil
end

function Cursor.init(self: Cursor)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self:_applyMouseIcon()
	self:_syncFromMouseLocation()

	if self.input ~= nil and typeof((self.input :: any).init) == "function" then
		local inputAny = self.input :: any
		pcall(function()
			inputAny:init()
		end)
	end

	self.boundWithInputModule = self:_bindWithInputModule()
	if not self.boundWithInputModule then
		self:_bindFallbackConnections()
	end

	self.lastInputTypeChangedConnection = UserInputService.LastInputTypeChanged:Connect(function()
		self:_setState({
			visible = UserInputService.MouseEnabled,
			mouseDown = false,
		})
		self:_syncFromMouseLocation()
	end)

	self:_startPolling()
end

function Cursor.onChanged(self: Cursor, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	self.nextListenerId += 1
	local id = self.nextListenerId
	self.listeners[id] = callbackRaw
	return function()
		self.listeners[id] = nil
	end
end

function Cursor.getState(self: Cursor): CursorState
	return cloneState(self.state)
end

function Cursor.getScreenPosition(self: Cursor): Vector2
	return self.state.screenPosition
end

function Cursor.getGuiPosition(self: Cursor): Vector2
	return self.state.guiPosition
end

function Cursor.isHoveringGui(self: Cursor): boolean
	return self.state.isHoveringGui
end

function Cursor.getHoveredGuiPath(self: Cursor): string?
	return self.state.hoveredGuiPath
end

function Cursor.setMouseDown(self: Cursor, isDownRaw: any)
	self:_setState({
		mouseDown = isDownRaw == true,
	})
end

function Cursor.setEnabled(self: Cursor, enabledRaw: any)
	self:_setState({
		enabled = enabledRaw == true,
	})
	self:_applyMouseIcon()
end

function Cursor.setUseCustomIcon(self: Cursor, useCustomIconRaw: any)
	self.useCustomIcon = useCustomIconRaw == true
	self:_applyMouseIcon()
end

function Cursor.sync(self: Cursor)
	self:_syncFromMouseLocation()
end

function Cursor.updateFromScreenPosition(self: Cursor, screenPositionRaw: any)
	if typeof(screenPositionRaw) ~= "Vector2" then
		return
	end
	self:_applyFromScreenPosition(screenPositionRaw)
end

function Cursor.destroy(self: Cursor)
	self:_stopPolling()
	self:_unbindInputModule()
	safeDisconnect(self.inputChangedConnection)
	safeDisconnect(self.inputBeganConnection)
	safeDisconnect(self.inputEndedConnection)
	safeDisconnect(self.lastInputTypeChangedConnection)
	self.inputChangedConnection = nil
	self.inputBeganConnection = nil
	self.inputEndedConnection = nil
	self.lastInputTypeChangedConnection = nil
	if self.defaultMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = self.defaultMouseIconEnabled
	else
		UserInputService.MouseIconEnabled = true
	end
	self.defaultMouseIconEnabled = nil
	table.clear(self.listeners)
	self.isInitialized = false
end

Cursor.OnChanged = Cursor.onChanged
Cursor.GetState = Cursor.getState
Cursor.GetScreenPosition = Cursor.getScreenPosition
Cursor.GetGuiPosition = Cursor.getGuiPosition
Cursor.SetMouseDown = Cursor.setMouseDown
Cursor.SetEnabled = Cursor.setEnabled
Cursor.SetUseCustomIcon = Cursor.setUseCustomIcon
Cursor.Sync = Cursor.sync
Cursor.UpdateFromScreenPosition = Cursor.updateFromScreenPosition
Cursor.Init = Cursor.init
Cursor.Destroy = Cursor.destroy

return Cursor
