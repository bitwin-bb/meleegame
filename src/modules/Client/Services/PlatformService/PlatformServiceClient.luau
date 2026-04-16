--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformUIScale = require(script:FindFirstAncestor("game").Shared.Services.PlatformService.UIScale)
local PlatformServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlatformService.PlatformServiceUtils)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PlatformKind = PlatformServiceUtils.PlatformKind
type PlatformStateBase = PlatformServiceUtils.PlatformState
type ActionDefinition = PlatformServiceUtils.ActionDefinition
type ActionBinding = PlatformServiceUtils.ActionBinding
type PromptBinding = PlatformServiceUtils.PromptBinding

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type StateChangedSignal = {
	Connect: (self: StateChangedSignal, callback: (state: PlatformClientState) -> ()) -> SignalConnection,
	Fire: (self: StateChangedSignal, state: PlatformClientState) -> (),
	DisconnectAll: (self: StateChangedSignal) -> (),
	Destroy: (self: StateChangedSignal) -> (),
}

type PlatformChangedSignal = {
	Connect: (
		self: PlatformChangedSignal,
		callback: (nextState: PlatformClientState, prevState: PlatformClientState?) -> ()
	) -> SignalConnection,
	Fire: (self: PlatformChangedSignal, nextState: PlatformClientState, prevState: PlatformClientState?) -> (),
	DisconnectAll: (self: PlatformChangedSignal) -> (),
	Destroy: (self: PlatformChangedSignal) -> (),
}

export type ActionPhase = "Began" | "Changed" | "Ended"

export type ActionContext = {
	actionName: string,
	phase: ActionPhase,
	inputState: Enum.UserInputState,
	inputObject: InputObject?,
	platform: PlatformKind,
	definition: ActionDefinition,
	binding: ActionBinding?,
	prompt: PromptBinding?,
	value: number,
	isPressed: boolean,
}

export type ActionListener = (phase: ActionPhase, context: ActionContext) -> boolean?

export type PlatformClientState = PlatformStateBase & {
	updatedAt: number,
}

type ActionRuntime = {
	definition: ActionDefinition,
	listeners: { [number]: ActionListener },
	nextListenerId: number,
	boundBindings: { ActionBinding },
	isBound: boolean,
	isEnabled: boolean,
}

local PlatformServiceClient = {}

PlatformServiceClient.ACTIONS = PlatformServiceUtils.ACTIONS

local TOUCH_MOVEMENT_GUARD_WIDTH = 0.42
local TOUCH_MOVEMENT_GUARD_HEIGHT = 0.44

local function cloneBinding(binding: ActionBinding): ActionBinding
	return {
		keyCode = binding.keyCode,
		inputType = binding.inputType,
		playerAction = binding.playerAction,
		axis = binding.axis,
		axisSign = binding.axisSign,
		deadzone = binding.deadzone,
		label = binding.label,
		icon = binding.icon,
	}
end

local function cloneBindings(bindingsRaw: { ActionBinding }?): { ActionBinding }
	local output: { ActionBinding } = {}
	if typeof(bindingsRaw) ~= "table" then
		return output
	end
	for index = 1, #bindingsRaw do
		local binding = bindingsRaw[index]
		if typeof(binding) == "table" then
			output[#output + 1] = cloneBinding(binding)
		end
	end
	return output
end

local function cloneDefinition(definition: ActionDefinition): ActionDefinition
	local bindingsByPlatform = {}
	if typeof(definition.bindingsByPlatform) == "table" then
		for platform, bindings in definition.bindingsByPlatform do
			bindingsByPlatform[platform] = cloneBindings(bindings)
		end
	end
	local promptBindingsByPlatform = {}
	if typeof(definition.promptBindingsByPlatform) == "table" then
		for platform, bindings in definition.promptBindingsByPlatform do
			promptBindingsByPlatform[platform] = cloneBindings(bindings)
		end
	end
	return {
		actionName = definition.actionName,
		displayName = definition.displayName,
		description = definition.description,
		priority = definition.priority,
		consume = definition.consume,
		allowWhileTyping = definition.allowWhileTyping,
		blockWhenPointerOverGui = definition.blockWhenPointerOverGui,
		blockWhenGuiSelected = definition.blockWhenGuiSelected,
		bindingsByPlatform = bindingsByPlatform,
		promptBindingsByPlatform = promptBindingsByPlatform,
		touchPrompt = definition.touchPrompt,
	}
end

local function sanitizePlatformKind(platformKindRaw: any): PlatformKind
	if platformKindRaw == "Gamepad" then
		return "Gamepad"
	end
	if platformKindRaw == "Touch" then
		return "Touch"
	end
	return "KeyboardMouse"
end

local function sanitizeBinding(bindingRaw: any): ActionBinding?
	if typeof(bindingRaw) ~= "table" then
		return nil
	end
	local binding: ActionBinding = {
		keyCode = if typeof(bindingRaw.keyCode) == "EnumItem" then bindingRaw.keyCode else nil,
		inputType = if typeof(bindingRaw.inputType) == "EnumItem" then bindingRaw.inputType else nil,
		playerAction = if typeof(bindingRaw.playerAction) == "EnumItem" then bindingRaw.playerAction else nil,
		axis = if bindingRaw.axis == "X" or bindingRaw.axis == "Y" then bindingRaw.axis else nil,
		axisSign = if typeof(bindingRaw.axisSign) == "number" then bindingRaw.axisSign else nil,
		deadzone = if typeof(bindingRaw.deadzone) == "number" then bindingRaw.deadzone else nil,
		label = if typeof(bindingRaw.label) == "string" then bindingRaw.label else nil,
		icon = if typeof(bindingRaw.icon) == "string" then bindingRaw.icon else nil,
	}
	if binding.keyCode == nil and binding.inputType == nil and binding.playerAction == nil then
		return nil
	end
	return binding
end

local function sanitizeBindingsTable(bindingsRaw: any): { ActionBinding }
	local output: { ActionBinding } = {}
	if typeof(bindingsRaw) ~= "table" then
		return output
	end
	for index = 1, #bindingsRaw do
		local binding = sanitizeBinding(bindingsRaw[index])
		if binding ~= nil then
			output[#output + 1] = binding
		end
	end
	return output
end

local function sanitizeBindingsByPlatform(bindingsRaw: any): { [string]: { ActionBinding } }
	local output = {}
	if typeof(bindingsRaw) ~= "table" then
		return output
	end
	for platform, bindings in bindingsRaw do
		if typeof(platform) == "string" then
			output[platform] = sanitizeBindingsTable(bindings)
		end
	end
	return output
end

local function sanitizeActionDefinition(actionName: string, definitionRaw: any): ActionDefinition?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end
	return {
		actionName = actionName,
		displayName = if typeof(definitionRaw.displayName) == "string" and definitionRaw.displayName ~= ""
			then definitionRaw.displayName
			else actionName,
		description = if typeof(definitionRaw.description) == "string" then definitionRaw.description else nil,
		priority = if typeof(definitionRaw.priority) == "number" then definitionRaw.priority else 2000,
		consume = definitionRaw.consume == true,
		allowWhileTyping = definitionRaw.allowWhileTyping == true,
		blockWhenPointerOverGui = if definitionRaw.blockWhenPointerOverGui == nil
			then true
			else definitionRaw.blockWhenPointerOverGui == true,
		blockWhenGuiSelected = if definitionRaw.blockWhenGuiSelected == nil
			then true
			else definitionRaw.blockWhenGuiSelected == true,
		bindingsByPlatform = sanitizeBindingsByPlatform(definitionRaw.bindingsByPlatform),
		promptBindingsByPlatform = sanitizeBindingsByPlatform(definitionRaw.promptBindingsByPlatform),
		touchPrompt = if typeof(definitionRaw.touchPrompt) == "string" then definitionRaw.touchPrompt else nil,
	}
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function cloneState(state: PlatformClientState): PlatformClientState
	local cloned = PlatformServiceUtils.clonePlatformState(state)
	return {
		platform = cloned.platform,
		deviceClass = cloned.deviceClass,
		preferredInputName = cloned.preferredInputName,
		lastInputTypeName = cloned.lastInputTypeName,
		viewport = cloned.viewport,
		isTenFootInterface = cloned.isTenFootInterface,
		touchEnabled = cloned.touchEnabled,
		keyboardEnabled = cloned.keyboardEnabled,
		mouseEnabled = cloned.mouseEnabled,
		gamepadEnabled = cloned.gamepadEnabled,
		basePrimaryInputType = cloned.basePrimaryInputType,
		updatedAt = state.updatedAt,
	}
end

local function toActionPhase(inputState: Enum.UserInputState): ActionPhase?
	if inputState == Enum.UserInputState.Begin then
		return "Began"
	end
	if inputState == Enum.UserInputState.Change then
		return "Changed"
	end
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		return "Ended"
	end
	return nil
end

local function getPointerScreenPosition(inputObject: InputObject?): Vector2?
	if inputObject == nil then
		return nil
	end
	if PlatformServiceUtils.isPointerInputType(inputObject.UserInputType) then
		local position = inputObject.Position
		if typeof(position) == "Vector3" then
			return Vector2.new(position.X, position.Y)
		end
		if typeof(position) == "Vector2" then
			return position
		end
	end
	return nil
end

local function getInputVector(inputObject: InputObject?): Vector2?
	if inputObject == nil then
		return nil
	end
	local position = inputObject.Position
	if typeof(position) == "Vector3" then
		return Vector2.new(position.X, position.Y)
	end
	if typeof(position) == "Vector2" then
		return position
	end
	return nil
end

local function shouldUseAxisValue(inputObject: InputObject?): boolean
	if inputObject == nil then
		return false
	end
	if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 or inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		return true
	end
	if PlatformServiceUtils.isGamepadInputType(inputObject.UserInputType) then
		return true
	end
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		local inputVector = getInputVector(inputObject)
		return inputVector ~= nil and inputVector.Magnitude <= 1.2
	end
	return false
end

local function isCustomCursorGui(guiObject: GuiObject): boolean
	local cursor: Instance? = guiObject
	while cursor ~= nil do
		if cursor:GetAttribute("IsCustomMouseCursor") == true then
			return true
		end
		if cursor.Name == "MouseScreenRoot" or cursor.Name == "MouseCursorImage" then
			return true
		end
		cursor = cursor.Parent
	end
	return false
end

local function isInteractiveGuiObject(guiObject: GuiObject): boolean
	if not guiObject.Visible then
		return false
	end
	if isCustomCursorGui(guiObject) then
		return false
	end
	if guiObject:IsA("GuiButton") or guiObject:IsA("TextBox") then
		return true
	end
	if guiObject.Active or guiObject.Selectable then
		return true
	end
	return false
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

local function isScreenPositionOverInteractiveGui(screenPositionRaw: any): boolean
	if typeof(screenPositionRaw) ~= "Vector2" then
		return false
	end
	local playerGui = getPlayerGui()
	if playerGui == nil then
		return false
	end
	local success, guiObjects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(math.floor(screenPositionRaw.X), math.floor(screenPositionRaw.Y))
	end)
	if not success or type(guiObjects) ~= "table" then
		return false
	end
	for _, guiObject in guiObjects do
		if guiObject:IsA("GuiObject") and isInteractiveGuiObject(guiObject) then
			return true
		end
	end
	return false
end

local function isTouchMovementRegion(position: Vector2, viewport: Vector2): boolean
	return position.X <= viewport.X * TOUCH_MOVEMENT_GUARD_WIDTH
		and position.Y >= viewport.Y * TOUCH_MOVEMENT_GUARD_HEIGHT
end

function PlatformServiceClient._resolveCapabilities(
	self: typeof(PlatformServiceClient)
): PlatformServiceUtils.CapabilitySnapshot
	local runtimePlatform = if self.runtimeContext ~= nil then (self.runtimeContext :: any).platform else nil
	if runtimePlatform ~= nil and typeof((runtimePlatform :: any).getSnapshot) == "function" then
		local ok, snapshot = pcall(function()
			return (runtimePlatform :: any):getSnapshot()
		end)
		if ok and typeof(snapshot) == "table" then
			return {
				touchEnabled = snapshot.touchEnabled == true,
				keyboardEnabled = snapshot.keyboardEnabled == true,
				mouseEnabled = snapshot.mouseEnabled == true,
				gamepadEnabled = snapshot.gamepadEnabled == true,
				basePrimaryInputType = if typeof(snapshot.primaryInputType) == "string"
					then snapshot.primaryInputType
					else nil,
			}
		end
	end
	return {
		touchEnabled = UserInputService.TouchEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		mouseEnabled = UserInputService.MouseEnabled,
		gamepadEnabled = UserInputService.GamepadEnabled,
		basePrimaryInputType = nil,
	}
end

function PlatformServiceClient._resolveViewport(self: typeof(PlatformServiceClient)): Vector2
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return Vector2.new(math.max(1, camera.ViewportSize.X), math.max(1, camera.ViewportSize.Y))
	end
	local state = self.state
	if state ~= nil then
		return state.viewport
	end
	return Vector2.new(1920, 1080)
end

function PlatformServiceClient._resolveState(self: typeof(PlatformServiceClient)): PlatformClientState
	local preferredInput = nil
	local preferredInputOk, preferredInputValue = pcall(function()
		return UserInputService.PreferredInput
	end)
	if preferredInputOk then
		preferredInput = preferredInputValue
	end

	local viewport = self:_resolveViewport()
	local capabilities = self:_resolveCapabilities()
	local platformState = PlatformServiceUtils.createPlatformState(
		preferredInput,
		self.lastInputType,
		capabilities,
		viewport,
		GuiService:IsTenFootInterface()
	)
	return {
		platform = platformState.platform,
		deviceClass = platformState.deviceClass,
		preferredInputName = platformState.preferredInputName,
		lastInputTypeName = platformState.lastInputTypeName,
		viewport = platformState.viewport,
		isTenFootInterface = platformState.isTenFootInterface,
		touchEnabled = platformState.touchEnabled,
		keyboardEnabled = platformState.keyboardEnabled,
		mouseEnabled = platformState.mouseEnabled,
		gamepadEnabled = platformState.gamepadEnabled,
		basePrimaryInputType = platformState.basePrimaryInputType,
		updatedAt = os.clock(),
	}
end

function PlatformServiceClient._resolveGamepadFamily(_self: typeof(PlatformServiceClient)): string
	return "xbox"
end

function PlatformServiceClient._updateActionBindingsForPlatform(self: typeof(PlatformServiceClient))
	for _, actionRuntime in self.actions do
		if next(actionRuntime.listeners) ~= nil then
			self:_unbindContextAction(actionRuntime)
			self:_bindContextAction(actionRuntime)
		end
	end
end

function PlatformServiceClient._refreshState(self: typeof(PlatformServiceClient), forceEmit: boolean?)
	local nextState = self:_resolveState()
	local previousState = self.state
	self.state = nextState
	local didPlatformChange = previousState == nil
		or not PlatformServiceUtils.platformStatesEqual(previousState, nextState)
	if didPlatformChange or forceEmit == true then
		local clonedState = cloneState(nextState)
		self.stateChanged:Fire(clonedState)
		if
			previousState == nil
			or previousState.platform ~= nextState.platform
			or previousState.deviceClass ~= nextState.deviceClass
		then
			self.platformChanged:Fire(clonedState, if previousState ~= nil then cloneState(previousState) else nil)
			self:_updateActionBindingsForPlatform()
		end
	end
end

function PlatformServiceClient._getActionRuntime(
	self: typeof(PlatformServiceClient),
	actionName: string
): ActionRuntime?
	return self.actions[actionName]
end

function PlatformServiceClient._ensureActionRuntime(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any,
	overrideDefinitionRaw: any?
): ActionRuntime?
	if typeof(actionNameRaw) ~= "string" or actionNameRaw == "" then
		return nil
	end
	local actionName = actionNameRaw :: string
	local existing = self.actions[actionName]
	if existing ~= nil then
		if overrideDefinitionRaw ~= nil then
			local sanitized = sanitizeActionDefinition(actionName, overrideDefinitionRaw)
			if sanitized ~= nil then
				existing.definition = sanitized
				existing.isEnabled = true
			end
		end
		return existing
	end

	local definition = if overrideDefinitionRaw ~= nil
		then sanitizeActionDefinition(actionName, overrideDefinitionRaw)
		else PlatformServiceUtils.getDefaultActionDefinition(actionName)
	if definition == nil then
		return nil
	end

	local runtime: ActionRuntime = {
		definition = cloneDefinition(definition),
		listeners = {},
		nextListenerId = 0,
		boundBindings = {},
		isBound = false,
		isEnabled = true,
	}
	self.actions[actionName] = runtime
	return runtime
end

function PlatformServiceClient._unbindContextAction(_self: typeof(PlatformServiceClient), actionRuntime: ActionRuntime)
	if not actionRuntime.isBound then
		return
	end
	ContextActionService:UnbindAction(actionRuntime.definition.actionName)
	actionRuntime.boundBindings = {}
	actionRuntime.isBound = false
end

function PlatformServiceClient._contextInputsForBindings(
	_self: typeof(PlatformServiceClient),
	bindings: { ActionBinding }
): { any }
	local output = {}
	local seen = {}
	for index = 1, #bindings do
		local binding = bindings[index]
		local input = binding.playerAction or binding.keyCode or binding.inputType
		if input == nil then
			continue
		end
		local seenKey = tostring(input)
		if seen[seenKey] == true then
			continue
		end
		seen[seenKey] = true
		output[#output + 1] = input
	end
	return output
end

function PlatformServiceClient._findMatchingBinding(
	_self: typeof(PlatformServiceClient),
	bindings: { ActionBinding },
	inputObject: InputObject?
): ActionBinding?
	if inputObject == nil then
		return if #bindings > 0 then bindings[1] else nil
	end
	for index = 1, #bindings do
		local binding = bindings[index]
		if binding.keyCode ~= nil and inputObject.KeyCode == binding.keyCode then
			return binding
		end
		if binding.inputType ~= nil and inputObject.UserInputType == binding.inputType then
			return binding
		end
	end
	return if #bindings > 0 then bindings[1] else nil
end

function PlatformServiceClient._shouldIgnoreAction(
	self: typeof(PlatformServiceClient),
	actionRuntime: ActionRuntime,
	inputObject: InputObject?
): boolean
	local definition = actionRuntime.definition
	if UserInputService:GetFocusedTextBox() ~= nil and definition.allowWhileTyping ~= true then
		return true
	end

	if definition.blockWhenGuiSelected == true and GuiService.SelectedObject ~= nil then
		return true
	end

	if definition.blockWhenPointerOverGui == true then
		local screenPosition = getPointerScreenPosition(inputObject)
		if screenPosition ~= nil then
			if self.state ~= nil and self.state.platform == "Touch" then
				if isTouchMovementRegion(screenPosition, self.state.viewport) then
					return true
				end
			end
			if isScreenPositionOverInteractiveGui(screenPosition) then
				return true
			end
		end
	end

	return false
end

function PlatformServiceClient._dispatchAction(
	self: typeof(PlatformServiceClient),
	actionRuntime: ActionRuntime,
	inputState: Enum.UserInputState,
	inputObject: InputObject?
): Enum.ContextActionResult
	local phase = toActionPhase(inputState)
	if phase == nil then
		return Enum.ContextActionResult.Pass
	end
	if self:_shouldIgnoreAction(actionRuntime, inputObject) then
		if actionRuntime.definition.consume == true then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end

	local prompt = self:getPromptForAction(actionRuntime.definition.actionName)
	local binding = self:_findMatchingBinding(actionRuntime.boundBindings, inputObject)
	local value = 0
	if binding ~= nil then
		local usedAnalogInput = false
		if binding.axis ~= nil and shouldUseAxisValue(inputObject) then
			local inputVector = getInputVector(inputObject)
			if
				inputVector ~= nil
				and inputState ~= Enum.UserInputState.End
				and inputState ~= Enum.UserInputState.Cancel
			then
				usedAnalogInput = true
				local deadzonedVector = PlatformServiceUtils.applyThumbstickDeadzone(inputVector, binding.deadzone)
				local axisValue = if binding.axis == "Y" then deadzonedVector.Y else deadzonedVector.X
				local axisSign = if typeof(binding.axisSign) == "number" and binding.axisSign < 0 then -1 else 1
				value = math.clamp(axisValue * axisSign, 0, 1)
			end
		end
		if value <= 0 and not usedAnalogInput then
			value = if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then 0 else 1
		end
	else
		value = if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then 0 else 1
	end
	local isPressed = value > 0
	local context: ActionContext = {
		actionName = actionRuntime.definition.actionName,
		phase = phase,
		inputState = inputState,
		inputObject = inputObject,
		platform = self:getPlatform(),
		definition = cloneDefinition(actionRuntime.definition),
		binding = if binding ~= nil then cloneBinding(binding) else nil,
		prompt = prompt,
		value = value,
		isPressed = isPressed,
	}

	for _, listener in actionRuntime.listeners do
		pcall(listener, phase, context)
	end

	if actionRuntime.definition.consume == true then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function PlatformServiceClient._bindContextAction(self: typeof(PlatformServiceClient), actionRuntime: ActionRuntime)
	if actionRuntime.isEnabled ~= true then
		return
	end
	local bindings = PlatformServiceUtils.resolveBindingsForPlatform(actionRuntime.definition, self:getPlatform())
	if #bindings <= 0 then
		return
	end
	local inputs = self:_contextInputsForBindings(bindings)
	if #inputs <= 0 then
		return
	end
	actionRuntime.boundBindings = cloneBindings(bindings)
	local priority = if typeof(actionRuntime.definition.priority) == "number"
		then actionRuntime.definition.priority
		else 2000
	ContextActionService:BindActionAtPriority(
		actionRuntime.definition.actionName,
		function(_actionName: string, inputState: Enum.UserInputState, inputObject: InputObject?)
			return self:_dispatchAction(actionRuntime, inputState, inputObject)
		end,
		false,
		priority,
		table.unpack(inputs)
	)
	actionRuntime.isBound = true
end

function PlatformServiceClient.Init(self: typeof(PlatformServiceClient))
	if self.janitor ~= nil then
		return
	end

	self.runtimeContext = CoreRuntime.getClientRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:init()
	end

	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.platformChanged = Signal.new()
	self.actions = {}
	self.lastInputType = nil :: Enum.UserInputType?
	self.gamepadFamily = self:_resolveGamepadFamily()
	self.uiScale = PlatformUIScale.new({
		platformService = self,
	})
	self.uiScale:init()

	self.janitor:GiveChore(function()
		if self.uiScale ~= nil then
			self.uiScale:destroy()
			self.uiScale = nil
		end
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
		self.platformChanged:Destroy()
	end)

	self.janitor:GiveChore(UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		self.lastInputType = inputType
		self:_refreshState(false)
	end))
	self.janitor:GiveChore(UserInputService.GamepadConnected:Connect(function()
		self:_refreshState(false)
	end))
	self.janitor:GiveChore(UserInputService.GamepadDisconnected:Connect(function()
		self:_refreshState(false)
	end))

	local preferredInputConnection = nil :: RBXScriptConnection?
	local preferredInputOk, preferredInputSignalOrError = pcall(function()
		return UserInputService:GetPropertyChangedSignal("PreferredInput")
	end)
	if preferredInputOk and typeof(preferredInputSignalOrError) == "RBXScriptSignal" then
		preferredInputConnection = (preferredInputSignalOrError :: RBXScriptSignal):Connect(function()
			self:_refreshState(false)
		end)
		self.janitor:GiveChore(function()
			safeDisconnect(preferredInputConnection)
		end)
	end

	local function bindViewportChanged()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return nil
		end
		return camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_refreshState(false)
		end)
	end

	local viewportConnection = bindViewportChanged()
	self.janitor:GiveChore(function()
		safeDisconnect(viewportConnection)
	end)
	self.janitor:GiveChore(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		safeDisconnect(viewportConnection)
		viewportConnection = bindViewportChanged()
		self:_refreshState(false)
	end))

	self:_refreshState(true)
end

function PlatformServiceClient.RequestSync(self: typeof(PlatformServiceClient))
	self:_refreshState(true)
end

function PlatformServiceClient.GetState(self: typeof(PlatformServiceClient)): PlatformClientState
	if self.state == nil then
		self:_refreshState(true)
	end
	return cloneState(self.state :: PlatformClientState)
end

function PlatformServiceClient.IsReady(self: typeof(PlatformServiceClient)): boolean
	return self.janitor ~= nil
end

function PlatformServiceClient.GetPlatform(self: typeof(PlatformServiceClient)): PlatformKind
	return self:getState().platform
end

function PlatformServiceClient.IsTouch(self: typeof(PlatformServiceClient)): boolean
	return self:getPlatform() == "Touch"
end

function PlatformServiceClient.IsGamepad(self: typeof(PlatformServiceClient)): boolean
	return self:getPlatform() == "Gamepad"
end

function PlatformServiceClient.IsKeyboardMouse(self: typeof(PlatformServiceClient)): boolean
	return self:getPlatform() == "KeyboardMouse"
end

function PlatformServiceClient.OnPlatformChanged(self: typeof(PlatformServiceClient), callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.platformChanged:Connect(callbackRaw)
	return function()
		connection:Disconnect()
	end
end

function PlatformServiceClient.RegisterAction(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any,
	definitionRaw: any
): boolean
	local runtime = self:_ensureActionRuntime(actionNameRaw, definitionRaw)
	if runtime == nil then
		return false
	end
	self:_unbindContextAction(runtime)
	if next(runtime.listeners) ~= nil then
		self:_bindContextAction(runtime)
	end
	return true
end

function PlatformServiceClient.RebindAction(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any,
	platformKindRaw: any,
	bindingsRaw: any,
	promptBindingsRaw: any?
): boolean
	local runtime = self:_ensureActionRuntime(actionNameRaw)
	if runtime == nil then
		return false
	end
	local platformKind = sanitizePlatformKind(platformKindRaw)
	runtime.definition.bindingsByPlatform = runtime.definition.bindingsByPlatform or {}
	runtime.definition.bindingsByPlatform[platformKind] = sanitizeBindingsTable(bindingsRaw)
	if promptBindingsRaw ~= nil then
		runtime.definition.promptBindingsByPlatform = runtime.definition.promptBindingsByPlatform or {}
		runtime.definition.promptBindingsByPlatform[platformKind] = sanitizeBindingsTable(promptBindingsRaw)
	end
	self:_unbindContextAction(runtime)
	if next(runtime.listeners) ~= nil then
		self:_bindContextAction(runtime)
	end
	return true
end

function PlatformServiceClient.SetActionEnabled(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any,
	enabledRaw: any
): boolean
	if typeof(actionNameRaw) ~= "string" then
		return false
	end
	local runtime = self.actions[actionNameRaw]
	if runtime == nil then
		return false
	end
	runtime.isEnabled = enabledRaw == true
	self:_unbindContextAction(runtime)
	if runtime.isEnabled and next(runtime.listeners) ~= nil then
		self:_bindContextAction(runtime)
	end
	return true
end

function PlatformServiceClient.BindAction(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any,
	callbackRaw: any,
	overrideDefinitionRaw: any?
): (() -> ())?
	if typeof(callbackRaw) ~= "function" then
		return nil
	end
	local runtime = self:_ensureActionRuntime(actionNameRaw, overrideDefinitionRaw)
	if runtime == nil then
		return nil
	end
	runtime.nextListenerId += 1
	local listenerId = runtime.nextListenerId
	runtime.listeners[listenerId] = callbackRaw
	if not runtime.isBound then
		self:_bindContextAction(runtime)
	end
	return function()
		local actionRuntime = self.actions[runtime.definition.actionName]
		if actionRuntime == nil then
			return
		end
		actionRuntime.listeners[listenerId] = nil
		if next(actionRuntime.listeners) == nil then
			self:_unbindContextAction(actionRuntime)
		end
	end
end

function PlatformServiceClient.GetPromptForAction(
	self: typeof(PlatformServiceClient),
	actionNameRaw: any
): PromptBinding?
	if typeof(actionNameRaw) ~= "string" then
		return nil
	end
	local runtime = self.actions[actionNameRaw]
	local definition = if runtime ~= nil
		then runtime.definition
		else PlatformServiceUtils.getDefaultActionDefinition(actionNameRaw)
	if definition == nil then
		return nil
	end

	local prompt = PlatformServiceUtils.resolvePromptForAction(
		definition,
		self:getPlatform(),
		self:getState().deviceClass,
		self.gamepadFamily
	)
	if prompt == nil then
		return nil
	end
	local output = {
		actionName = prompt.actionName,
		displayName = prompt.displayName,
		platform = prompt.platform,
		deviceClass = prompt.deviceClass,
		text = prompt.text,
		icon = prompt.icon,
		keyCode = prompt.keyCode,
		inputType = prompt.inputType,
		playerAction = prompt.playerAction,
	} :: PromptBinding

	if output.keyCode ~= nil then
		if output.text == nil or output.text == "" then
			local okText, officialText = pcall(function()
				return UserInputService:GetStringForKeyCode(output.keyCode :: Enum.KeyCode)
			end)
			if okText and typeof(officialText) == "string" and officialText ~= "" then
				output.text = officialText
			end
		end

		if output.icon == nil or output.icon == "" then
			local okImage, officialImage = pcall(function()
				return UserInputService:GetImageForKeyCode(output.keyCode :: Enum.KeyCode)
			end)
			if okImage and typeof(officialImage) == "string" and officialImage ~= "" then
				output.icon = officialImage
			end
		end
	end

	return output
end

function PlatformServiceClient.GetUIScale(self: typeof(PlatformServiceClient)): any?
	return self.uiScale
end

function PlatformServiceClient.SetScreenGui(self: typeof(PlatformServiceClient), screenGuiRaw: any): boolean
	if self.uiScale == nil then
		return false
	end
	return self.uiScale:setScreenGui(screenGuiRaw)
end

function PlatformServiceClient.SetScaleTarget(self: typeof(PlatformServiceClient), targetRaw: any): boolean
	if self.uiScale == nil then
		return false
	end
	return self.uiScale:setScaleTarget(targetRaw)
end

function PlatformServiceClient.Destroy(self: typeof(PlatformServiceClient))
	for _, actionRuntime in self.actions do
		self:_unbindContextAction(actionRuntime)
	end
	table.clear(self.actions)
	if self.janitor ~= nil then
		self.janitor:Destroy()
		self.janitor = nil
	end
	self.runtimeContext = nil
	self.state = nil
	self.lastInputType = nil
end

PlatformServiceClient.init = PlatformServiceClient.Init
PlatformServiceClient.requestSync = PlatformServiceClient.RequestSync
PlatformServiceClient.isReady = PlatformServiceClient.IsReady
PlatformServiceClient.getState = PlatformServiceClient.GetState
PlatformServiceClient.getPlatform = PlatformServiceClient.GetPlatform
PlatformServiceClient.isTouch = PlatformServiceClient.IsTouch
PlatformServiceClient.isGamepad = PlatformServiceClient.IsGamepad
PlatformServiceClient.isKeyboardMouse = PlatformServiceClient.IsKeyboardMouse
PlatformServiceClient.onPlatformChanged = PlatformServiceClient.OnPlatformChanged
PlatformServiceClient.registerAction = PlatformServiceClient.RegisterAction
PlatformServiceClient.rebindAction = PlatformServiceClient.RebindAction
PlatformServiceClient.setActionEnabled = PlatformServiceClient.SetActionEnabled
PlatformServiceClient.bindAction = PlatformServiceClient.BindAction
PlatformServiceClient.getPromptForAction = PlatformServiceClient.GetPromptForAction
PlatformServiceClient.getUIScale = PlatformServiceClient.GetUIScale
PlatformServiceClient.setScreenGui = PlatformServiceClient.SetScreenGui
PlatformServiceClient.setScaleTarget = PlatformServiceClient.SetScaleTarget
PlatformServiceClient.destroy = PlatformServiceClient.Destroy

return PlatformServiceClient
