--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Cursor = {}
Cursor.__index = Cursor

local GAMEPAD_CURSOR_SPEED = 900
local GAMEPAD_CURSOR_DEADZONE = 0.18
local GAMEPAD_CURSOR_THUMBSTICK = Enum.KeyCode.Thumbstick2
local GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE = "CustomCursorGamepadActive"

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

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type CursorChangedSignal = {
	Connect: (self: CursorChangedSignal, callback: (state: CursorState) -> ()) -> SignalConnection,
	Fire: (self: CursorChangedSignal, state: CursorState) -> (),
	DisconnectAll: (self: CursorChangedSignal) -> (),
	Destroy: (self: CursorChangedSignal) -> (),
}

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

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function isPointerMoveInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

local function getViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return Vector2.new(math.max(1, camera.ViewportSize.X), math.max(1, camera.ViewportSize.Y))
	end
	return Vector2.new(1920, 1080)
end

local function clampScreenPosition(screenPosition: Vector2): Vector2
	local viewport = getViewportSize()
	return Vector2.new(
		math.clamp(screenPosition.X, 0, math.max(0, viewport.X - 1)),
		math.clamp(screenPosition.Y, 0, math.max(0, viewport.Y - 1))
	)
end

local function getCenteredScreenPosition(): Vector2
	local viewport = getViewportSize()
	return Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
end

local function normalizeGamepadCursorVector(vector: Vector2): Vector2
	local magnitude = vector.Magnitude
	if magnitude <= GAMEPAD_CURSOR_DEADZONE or magnitude <= 1e-4 then
		return Vector2.zero
	end
	local scaledMagnitude = math.clamp((magnitude - GAMEPAD_CURSOR_DEADZONE) / math.max(1e-4, 1 - GAMEPAD_CURSOR_DEADZONE), 0, 1)
	return vector.Unit * scaledMagnitude
end

local function resolveLastInputType(inputTypeRaw: any): Enum.UserInputType?
	if typeof(inputTypeRaw) == "EnumItem" and inputTypeRaw.EnumType == Enum.UserInputType then
		return inputTypeRaw :: Enum.UserInputType
	end

	local ok, inputType = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(inputType) == "EnumItem" and inputType.EnumType == Enum.UserInputType then
		return inputType :: Enum.UserInputType
	end

	return nil
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
		if CollectionService:HasTag(current, "IsCustomMouseCursor") then
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

function Cursor.New(configRaw: CursorConfig?): Cursor
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local defaultScreenPosition = Vector2.zero
	local ok, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(mouseLocation) == "Vector2" then
		defaultScreenPosition = mouseLocation
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		defaultScreenPosition = getCenteredScreenPosition()
	end
	local state = {
		enabled = true,
		visible = UserInputService.MouseEnabled or (UserInputService.GamepadEnabled and not UserInputService.MouseEnabled),
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
		changedSignal = Signal.new() :: CursorChangedSignal,
		inputChangedConnection = nil :: RBXScriptConnection?,
		inputBeganConnection = nil :: RBXScriptConnection?,
		inputEndedConnection = nil :: RBXScriptConnection?,
		lastInputTypeChangedConnection = nil :: RBXScriptConnection?,
		stepConnection = nil :: RBXScriptConnection?,
		pollToken = nil,
		boundWithInputModule = false,
		gamepadThumbstickConnection = nil :: RBXScriptConnection?,
		gamepadInputBeganConnection = nil :: RBXScriptConnection?,
		gamepadInputEndedConnection = nil :: RBXScriptConnection?,
		gamepadMoveVector = Vector2.zero,
		lastInputWasGamepad = UserInputService.GamepadEnabled and not UserInputService.MouseEnabled,
		isInitialized = false,
	}, Cursor)
	return self
end

function Cursor._emitChanged(self: Cursor, state: CursorState)
	self.changedSignal:Fire(state)
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

function Cursor._updateVisibility(self: Cursor)
	self:_setState({
		visible = self.state.enabled and (self.lastInputWasGamepad or UserInputService.MouseEnabled),
	})
	GuiService:SetAttribute(GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE, self.state.enabled and self.lastInputWasGamepad)
end

function Cursor._syncSelectedObject(self: Cursor, hoveredGui: GuiObject?)
	if not self.lastInputWasGamepad then
		return
	end

	local nextSelected = nil :: GuiObject?
	if hoveredGui ~= nil and (hoveredGui.Selectable or hoveredGui:IsA("GuiButton") or hoveredGui:IsA("TextBox")) then
		nextSelected = hoveredGui
	end

	if GuiService.SelectedObject ~= nextSelected then
		GuiService.SelectedObject = nextSelected
	end
end

function Cursor._applyFromScreenPosition(self: Cursor, screenPosition: Vector2)
	local clampedScreenPosition = clampScreenPosition(screenPosition)
	local guiPosition = toGuiPosition(clampedScreenPosition)
	local hoveredGui = resolveHoveredGuiObject(guiPosition)
	self:_syncSelectedObject(hoveredGui)
	self:_setState({
		screenPosition = clampedScreenPosition,
		guiPosition = guiPosition,
		isHoveringGui = hoveredGui ~= nil,
		hoveredGuiPath = if hoveredGui ~= nil then hoveredGui:GetFullName() else false,
	})
end

function Cursor._syncFromMouseLocation(self: Cursor)
	if not UserInputService.MouseEnabled then
		return
	end
	local ok, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(mouseLocation) == "Vector2" then
		self:_applyFromScreenPosition(mouseLocation)
	end
end

function Cursor._activateHoveredGui(self: Cursor)
	local hoveredGui = resolveHoveredGuiObject(self.state.guiPosition)
	if hoveredGui ~= nil then
		self:_syncSelectedObject(hoveredGui)
		if hoveredGui:IsA("GuiButton") then
			hoveredGui:Activate()
			return
		end
	end

	local selectedObject = GuiService.SelectedObject
	if selectedObject ~= nil and selectedObject:IsA("GuiButton") then
		selectedObject:Activate()
	end
end

function Cursor._updateGamepadVector(self: Cursor, inputObject: InputObject)
	if inputObject.KeyCode ~= GAMEPAD_CURSOR_THUMBSTICK then
		return
	end
	local position = inputObject.Position
	if typeof(position) ~= "Vector3" then
		return
	end

	self.lastInputWasGamepad = true
	self.gamepadMoveVector = normalizeGamepadCursorVector(Vector2.new(position.X, -position.Y))
	self:_updateVisibility()
end

function Cursor._stepGamepadCursor(self: Cursor, dt: number)
	if not self.state.enabled or not self.lastInputWasGamepad then
		return
	end
	if self.gamepadMoveVector.Magnitude <= 1e-4 then
		return
	end

	local basePosition = self.state.screenPosition
	if basePosition.Magnitude <= 1e-4 and not UserInputService.MouseEnabled then
		basePosition = getCenteredScreenPosition()
	end
	self:_applyFromScreenPosition(basePosition + self.gamepadMoveVector * GAMEPAD_CURSOR_SPEED * math.max(dt, 1 / 240))
end

function Cursor._bindGamepadConnections(self: Cursor)
	self.gamepadThumbstickConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
		if not self.state.enabled or not isGamepadInput(inputObject.UserInputType) then
			return
		end
		self:_updateGamepadVector(inputObject)
	end)

	self.gamepadInputBeganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessed: boolean)
		if gameProcessed or not self.state.enabled or not isGamepadInput(inputObject.UserInputType) then
			return
		end

		self.lastInputWasGamepad = true
		self:_updateVisibility()

		if inputObject.KeyCode == Enum.KeyCode.ButtonA then
			self:_setState({
				mouseDown = true,
			})
			self:_activateHoveredGui()
		end
	end)

	self.gamepadInputEndedConnection = UserInputService.InputEnded:Connect(function(inputObject: InputObject)
		if not self.state.enabled or not isGamepadInput(inputObject.UserInputType) then
			return
		end

		if inputObject.KeyCode == GAMEPAD_CURSOR_THUMBSTICK then
			self.gamepadMoveVector = Vector2.zero
		elseif inputObject.KeyCode == Enum.KeyCode.ButtonA then
			self:_setState({
				mouseDown = false,
			})
		end
	end)
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
			self.lastInputWasGamepad = false
			self:_updateVisibility()
			self:_applyFromScreenPosition(inputObject.Position)
		end
	end)

	self.inputBeganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject)
		if not self.state.enabled then
			return
		end
		if isMouseButtonInput(inputObject.UserInputType) then
			self.lastInputWasGamepad = false
			self:_updateVisibility()
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
			if self.state.enabled then
				if UserInputService.MouseEnabled and not self.lastInputWasGamepad then
					self:_syncFromMouseLocation()
				end
				self:_stepGamepadCursor(1 / 60)
			end
		end, 1 / 60, {
			group = "cursor.poll",
			priority = 250,
			catchUp = false,
		})
		return
	end
	self.stepConnection = RunService.RenderStepped:Connect(function(dt: number)
		if not self.state.enabled then
			return
		end
		if UserInputService.MouseEnabled and not self.lastInputWasGamepad then
			self:_syncFromMouseLocation()
		end
		self:_stepGamepadCursor(dt)
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

function Cursor.Init(self: Cursor)
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
	self:_bindGamepadConnections()

	self.lastInputTypeChangedConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local lastInputType = resolveLastInputType(inputType)
		self.lastInputWasGamepad = if lastInputType ~= nil then isGamepadInput(lastInputType) else self.lastInputWasGamepad
		if not self.lastInputWasGamepad then
			self.gamepadMoveVector = Vector2.zero
		end
		self:_setState({
			mouseDown = false,
		})
		self:_updateVisibility()
		if self.lastInputWasGamepad then
			if self.state.screenPosition.Magnitude <= 1e-4 then
				self:_applyFromScreenPosition(getCenteredScreenPosition())
			end
		else
			self:_syncFromMouseLocation()
		end
	end)

	self:_startPolling()
end

function Cursor.OnChanged(self: Cursor, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.changedSignal:Connect(callbackRaw :: (state: CursorState) -> ())
	return function()
		connection:Disconnect()
	end
end

function Cursor.GetState(self: Cursor): CursorState
	return cloneState(self.state)
end

function Cursor.GetScreenPosition(self: Cursor): Vector2
	return self.state.screenPosition
end

function Cursor.GetGuiPosition(self: Cursor): Vector2
	return self.state.guiPosition
end

function Cursor.IsHoveringGui(self: Cursor): boolean
	return self.state.isHoveringGui
end

function Cursor.GetHoveredGuiPath(self: Cursor): string?
	return self.state.hoveredGuiPath
end

function Cursor.SetMouseDown(self: Cursor, isDownRaw: any)
	self:_setState({
		mouseDown = isDownRaw == true,
	})
end

function Cursor.SetEnabled(self: Cursor, enabledRaw: any)
	local isEnabled = enabledRaw == true
	self:_setState({
		enabled = isEnabled,
		mouseDown = if isEnabled then self.state.mouseDown else false,
		visible = if isEnabled then self.state.visible else false,
	})
	if isEnabled then
		self:_updateVisibility()
		if self.lastInputWasGamepad then
			if self.state.screenPosition.Magnitude <= 1e-4 then
				self:_applyFromScreenPosition(getCenteredScreenPosition())
			end
		else
			self:_syncFromMouseLocation()
		end
	else
		GuiService:SetAttribute(GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE, false)
	end
	self:_applyMouseIcon()
end

function Cursor.SetUseCustomIcon(self: Cursor, useCustomIconRaw: any)
	self.useCustomIcon = useCustomIconRaw == true
	self:_applyMouseIcon()
end

function Cursor.Sync(self: Cursor)
	if self.lastInputWasGamepad then
		self:_updateVisibility()
		if self.state.screenPosition.Magnitude <= 1e-4 then
			self:_applyFromScreenPosition(getCenteredScreenPosition())
		end
		return
	end
	self:_syncFromMouseLocation()
end

function Cursor.UpdateFromScreenPosition(self: Cursor, screenPositionRaw: any)
	if typeof(screenPositionRaw) ~= "Vector2" then
		return
	end
	self:_applyFromScreenPosition(screenPositionRaw)
end

function Cursor.Destroy(self: Cursor)
	self:_stopPolling()
	self:_unbindInputModule()
	safeDisconnect(self.inputChangedConnection)
	safeDisconnect(self.inputBeganConnection)
	safeDisconnect(self.inputEndedConnection)
	safeDisconnect(self.gamepadThumbstickConnection)
	safeDisconnect(self.gamepadInputBeganConnection)
	safeDisconnect(self.gamepadInputEndedConnection)
	safeDisconnect(self.lastInputTypeChangedConnection)
	self.inputChangedConnection = nil
	self.inputBeganConnection = nil
	self.inputEndedConnection = nil
	self.gamepadThumbstickConnection = nil
	self.gamepadInputBeganConnection = nil
	self.gamepadInputEndedConnection = nil
	self.lastInputTypeChangedConnection = nil
	if self.defaultMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = self.defaultMouseIconEnabled
	else
		UserInputService.MouseIconEnabled = true
	end
	GuiService:SetAttribute(GAMEPAD_CURSOR_ACTIVE_ATTRIBUTE, false)
	self.defaultMouseIconEnabled = nil
	self.changedSignal:DisconnectAll()
	self.changedSignal:Destroy()
	self.isInitialized = false
end

Cursor.OnChanged = Cursor.OnChanged
Cursor.GetState = Cursor.GetState
Cursor.GetScreenPosition = Cursor.GetScreenPosition
Cursor.GetGuiPosition = Cursor.GetGuiPosition
Cursor.SetMouseDown = Cursor.SetMouseDown
Cursor.SetEnabled = Cursor.SetEnabled
Cursor.SetUseCustomIcon = Cursor.SetUseCustomIcon
Cursor.Sync = Cursor.Sync
Cursor.UpdateFromScreenPosition = Cursor.UpdateFromScreenPosition
Cursor.Init = Cursor.Init
Cursor.Destroy = Cursor.Destroy

Cursor.new = Cursor.New
Cursor.init = Cursor.Init
Cursor.onChanged = Cursor.OnChanged
Cursor.getState = Cursor.GetState
Cursor.getScreenPosition = Cursor.GetScreenPosition
Cursor.getGuiPosition = Cursor.GetGuiPosition
Cursor.isHoveringGui = Cursor.IsHoveringGui
Cursor.getHoveredGuiPath = Cursor.GetHoveredGuiPath
Cursor.setMouseDown = Cursor.SetMouseDown
Cursor.setEnabled = Cursor.SetEnabled
Cursor.setUseCustomIcon = Cursor.SetUseCustomIcon
Cursor.sync = Cursor.Sync
Cursor.updateFromScreenPosition = Cursor.UpdateFromScreenPosition
Cursor.destroy = Cursor.Destroy

return Cursor
