--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local UserInputService = game:GetService("UserInputService")

local Input = {}
Input.__index = Input

export type InputPhase = "Began" | "Changed" | "Ended" | "LongPress" | "DoubleTap"

export type InputBinding = {
	keyCode: Enum.KeyCode?,
	inputType: Enum.UserInputType?,
	deadzone: number?,
}

export type InputContext = {
	phase: InputPhase,
	actionName: string,
	input: InputObject,
	inputKey: string,
	timestamp: number,
	duration: number,
	position: any,
	delta: any,
	deadzonePassed: boolean,
	layer: string,
}

export type InputActionCallback = (phase: InputPhase, context: InputContext) -> boolean?

export type ActionOptions = {
	layer: string?,
	priority: number?,
	consume: boolean?,
	enabled: boolean?,
	allowGameProcessed: boolean?,
	allowWhileTyping: boolean?,
	bindings: { InputBinding }?,
	longPressTime: number?,
	doubleTapWindow: number?,
	deadzone: number?,
}

export type LayerConfig = {
	enabled: boolean?,
	priority: number?,
}

export type InputConfig = {
	eventBus: any?,
	eventChannel: string?,
	actionEvent: string?,
	tickScheduler: any?,
	defaultLongPressTime: number?,
	defaultDoubleTapWindow: number?,
	defaultDeadzone: number?,
	layers: { [string]: LayerConfig }?,
}

type CompiledBinding = {
	inputKey: string,
	keyCode: Enum.KeyCode?,
	inputType: Enum.UserInputType?,
	deadzone: number,
}

type ActionRecord = {
	name: string,
	callback: InputActionCallback,
	layer: string,
	priority: number,
	consume: boolean,
	enabled: boolean,
	allowGameProcessed: boolean,
	allowWhileTyping: boolean,
	longPressTime: number,
	doubleTapWindow: number,
	deadzone: number,
	bindings: { CompiledBinding },
}

type BindingEntry = {
	action: ActionRecord,
	binding: CompiledBinding,
}

type ActivePress = {
	actionName: string,
	inputKey: string,
	startTime: number,
	longPressTriggered: boolean,
	longPressCancel: (() -> ())?,
}

export type Input = typeof(setmetatable({} :: any, Input))

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

local function clampPriority(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	local value = math.floor(valueRaw)
	if value < -1000000 then
		return -1000000
	end
	if value > 1000000 then
		return 1000000
	end
	return value
end

local function normalizeLayer(layerRaw: any): string
	if typeof(layerRaw) == "string" and layerRaw ~= "" then
		return layerRaw
	end
	return "Gameplay"
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

local function deriveInputKey(input: InputObject): string
	if input.KeyCode ~= Enum.KeyCode.Unknown then
		return "K:" .. input.KeyCode.Name
	end
	return "U:" .. input.UserInputType.Name
end

local function normalizeBindings(bindingsRaw: any): { InputBinding }
	local out = {}
	if typeof(bindingsRaw) ~= "table" then
		return out
	end
	for _, bindingRaw in bindingsRaw do
		if typeof(bindingRaw) ~= "table" then
			continue
		end
		local keyCode = if typeof(bindingRaw.keyCode) == "EnumItem" then bindingRaw.keyCode else nil
		local inputType = if typeof(bindingRaw.inputType) == "EnumItem" then bindingRaw.inputType else nil
		if keyCode == nil and inputType == nil then
			continue
		end
		out[#out + 1] = {
			keyCode = keyCode,
			inputType = inputType,
			deadzone = bindingRaw.deadzone,
		}
	end
	return out
end

local function sortBindingEntries(self: Input, entries: { BindingEntry })
	table.sort(entries, function(a, b)
		local layerAPriority = self.layerPriorities[a.action.layer] or 0
		local layerBPriority = self.layerPriorities[b.action.layer] or 0
		if layerAPriority ~= layerBPriority then
			return layerAPriority > layerBPriority
		end
		if a.action.priority ~= b.action.priority then
			return a.action.priority > b.action.priority
		end
		return a.action.name < b.action.name
	end)
end

local function hasDeadzonePassed(input: InputObject, deadzone: number): boolean
	if deadzone <= 0 then
		return true
	end
	local position = input.Position
	if typeof(position) ~= "Vector3" then
		return true
	end
	local magnitude = math.sqrt(position.X * position.X + position.Y * position.Y)
	return magnitude >= deadzone
end

function Input.New(configRaw: InputConfig?): Input
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "input"),
		actionEvent = normalizeEventName(config.actionEvent, "action"),
		tickScheduler = config.tickScheduler,
		defaultLongPressTime = clampNumber(config.defaultLongPressTime, 0.45, 0.1, 5),
		defaultDoubleTapWindow = clampNumber(config.defaultDoubleTapWindow, 0.3, 0.05, 2),
		defaultDeadzone = clampNumber(config.defaultDeadzone, 0.15, 0, 1),
		actions = {} :: { [string]: ActionRecord },
		bindingIndex = {} :: { [string]: { BindingEntry } },
		layerEnabled = {
			Gameplay = true,
			UI = true,
		} :: { [string]: boolean },
		layerPriorities = {
			Gameplay = 0,
			UI = 100,
		} :: { [string]: number },
		activePresses = {} :: { [InputObject]: { [string]: ActivePress } },
		lastTapByActionInput = {} :: { [string]: number },
		connections = {} :: { RBXScriptConnection? },
		isInitialized = false,
	}, Input)

	if typeof(config.layers) == "table" then
		for layerName, layerConfig in config.layers do
			if typeof(layerName) == "string" and typeof(layerConfig) == "table" then
				if layerConfig.enabled ~= nil then
					self.layerEnabled[layerName] = layerConfig.enabled == true
				end
				if layerConfig.priority ~= nil then
					self.layerPriorities[layerName] = clampPriority(layerConfig.priority, self.layerPriorities[layerName] or 0)
				end
			end
		end
	end

	return self
end

function Input._compileBindings(self: Input, action: ActionRecord, bindingsRaw: any): { CompiledBinding }
	local normalized = normalizeBindings(bindingsRaw)
	local compiled = Sift.Array.create(#normalized)
	for index = 1, #normalized do
		local binding = normalized[index]
		local keyCode = binding.keyCode
		local inputType = binding.inputType
		local inputKey = if keyCode ~= nil then "K:" .. keyCode.Name else "U:" .. (inputType :: Enum.UserInputType).Name
		compiled[index] = {
			inputKey = inputKey,
			keyCode = keyCode,
			inputType = inputType,
			deadzone = clampNumber(binding.deadzone, action.deadzone, 0, 1),
		}
	end
	return compiled
end

function Input._rebuildBindingIndex(self: Input)
	table.clear(self.bindingIndex)
	for _, action in self.actions do
		if not action.enabled then
			continue
		end
		for index = 1, #action.bindings do
			local binding = action.bindings[index]
			local entries = self.bindingIndex[binding.inputKey]
			if entries == nil then
				entries = {}
				self.bindingIndex[binding.inputKey] = entries
			end
			entries[#entries + 1] = {
				action = action,
				binding = binding,
			}
		end
	end
	for _, entries in self.bindingIndex do
		sortBindingEntries(self, entries)
	end
end

function Input._scheduleLongPress(self: Input, inputObject: InputObject, action: ActionRecord, press: ActivePress)
	if action.longPressTime <= 0 then
		return
	end
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).schedule) == "function" then
		local token = (self.tickScheduler :: any):schedule(function()
			local inputPresses = self.activePresses[inputObject]
			if inputPresses == nil then
				return
			end
			local runtimePress = inputPresses[action.name]
			if runtimePress == nil or runtimePress.longPressTriggered then
				return
			end
			runtimePress.longPressTriggered = true
			self:_dispatchAction(action, press.inputKey, inputObject, "LongPress", false, runtimePress.startTime)
		end, action.longPressTime, {
			group = "input.longpress",
			priority = 200,
		})
		press.longPressCancel = function()
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
	press.longPressCancel = function()
		cancelled = true
	end
	task.delay(action.longPressTime, function()
		if cancelled then
			return
		end
		local inputPresses = self.activePresses[inputObject]
		if inputPresses == nil then
			return
		end
		local runtimePress = inputPresses[action.name]
		if runtimePress == nil or runtimePress.longPressTriggered then
			return
		end
		runtimePress.longPressTriggered = true
		self:_dispatchAction(action, press.inputKey, inputObject, "LongPress", false, runtimePress.startTime)
	end)
end

function Input._dispatchAction(
	self: Input,
	action: ActionRecord,
	inputKey: string,
	inputObject: InputObject,
	phase: InputPhase,
	gameProcessed: boolean,
	startTime: number?
): boolean
	if not action.enabled then
		return false
	end
	if not (self.layerEnabled[action.layer] == true) then
		return false
	end
	if gameProcessed and not action.allowGameProcessed then
		return false
	end
	if UserInputService:GetFocusedTextBox() ~= nil and not action.allowWhileTyping then
		return false
	end

	local timestamp = os.clock()
	local beginTimestamp = if startTime ~= nil then startTime else timestamp
	local duration = math.max(0, timestamp - beginTimestamp)
	local context: InputContext = {
		phase = phase,
		actionName = action.name,
		input = inputObject,
		inputKey = inputKey,
		timestamp = timestamp,
		duration = duration,
		position = inputObject.Position,
		delta = inputObject.Delta,
		deadzonePassed = true,
		layer = action.layer,
	}

	local ok, consumedOrErr = pcall(action.callback, phase, context)
	if not ok then
		return false
	end

	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.actionEvent, {
			actionName = action.name,
			phase = phase,
			layer = action.layer,
			inputKey = inputKey,
			duration = duration,
		})
	end

	if action.consume then
		return consumedOrErr ~= false
	end
	return false
end

function Input._getEntriesForInput(self: Input, input: InputObject): { BindingEntry }?
	return self.bindingIndex[deriveInputKey(input)]
end

function Input._handleInput(self: Input, input: InputObject, phase: InputPhase, gameProcessed: boolean)
	local entries = self:_getEntriesForInput(input)
	if entries == nil then
		return
	end

	local inputKey = deriveInputKey(input)
	local consumed = false
	local now = os.clock()

	for index = 1, #entries do
		if consumed then
			break
		end
		local entry = entries[index]
		local action = entry.action
		local binding = entry.binding
		if not hasDeadzonePassed(input, binding.deadzone) then
			continue
		end

		if phase == "Began" then
			local perInput = self.activePresses[input]
			if perInput == nil then
				perInput = {}
				self.activePresses[input] = perInput
			end
			local press: ActivePress = {
				actionName = action.name,
				inputKey = inputKey,
				startTime = now,
				longPressTriggered = false,
				longPressCancel = nil,
			}
			perInput[action.name] = press
			self:_scheduleLongPress(input, action, press)
		end

		local activePress = if self.activePresses[input] ~= nil then self.activePresses[input][action.name] else nil
		local startTime = if activePress ~= nil then activePress.startTime else nil
		local didConsume = self:_dispatchAction(action, inputKey, input, phase, gameProcessed, startTime)
		if didConsume then
			consumed = true
		end

		if phase == "Ended" then
			local perInput = self.activePresses[input]
			local press = if perInput ~= nil then perInput[action.name] else nil
			if press ~= nil then
				if press.longPressCancel ~= nil then
					press.longPressCancel()
				end
				local shouldCheckDoubleTap = (not press.longPressTriggered) and action.doubleTapWindow > 0
				if shouldCheckDoubleTap then
					local tapKey = action.name .. "|" .. inputKey
					local previousTap = self.lastTapByActionInput[tapKey]
					if previousTap ~= nil and (now - previousTap) <= action.doubleTapWindow then
						self.lastTapByActionInput[tapKey] = nil
						self:_dispatchAction(action, inputKey, input, "DoubleTap", gameProcessed, press.startTime)
					else
						self.lastTapByActionInput[tapKey] = now
					end
				end
				perInput[action.name] = nil
				if next(perInput) == nil then
					self.activePresses[input] = nil
				end
			end
		end
	end
end

function Input.Init(self: Input)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.connections[#self.connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_handleInput(input, "Began", gameProcessed)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_handleInput(input, "Changed", gameProcessed)
	end)
	self.connections[#self.connections + 1] = UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_handleInput(input, "Ended", gameProcessed)
	end)
end

function Input.BindAction(self: Input, actionNameRaw: any, callbackRaw: any, optionsRaw: ActionOptions?): boolean
	if typeof(actionNameRaw) ~= "string" or actionNameRaw == "" then
		return false
	end
	if typeof(callbackRaw) ~= "function" then
		return false
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local actionName = actionNameRaw :: string
	local layer = normalizeLayer(options.layer)
	local action: ActionRecord = {
		name = actionName,
		callback = callbackRaw,
		layer = layer,
		priority = clampPriority(options.priority, 0),
		consume = options.consume == true,
		enabled = if options.enabled == nil then true else options.enabled == true,
		allowGameProcessed = options.allowGameProcessed == true,
		allowWhileTyping = options.allowWhileTyping == true,
		longPressTime = clampNumber(options.longPressTime, self.defaultLongPressTime, 0, 5),
		doubleTapWindow = clampNumber(options.doubleTapWindow, self.defaultDoubleTapWindow, 0, 2),
		deadzone = clampNumber(options.deadzone, self.defaultDeadzone, 0, 1),
		bindings = {},
	}

	action.bindings = self:_compileBindings(action, options.bindings)
	if #action.bindings == 0 then
		return false
	end

	self.actions[actionName] = action
	if self.layerEnabled[layer] == nil then
		self.layerEnabled[layer] = true
	end
	if self.layerPriorities[layer] == nil then
		self.layerPriorities[layer] = 0
	end
	self:_rebuildBindingIndex()
	return true
end

function Input.RebindAction(self: Input, actionNameRaw: any, bindingsRaw: any): boolean
	if typeof(actionNameRaw) ~= "string" then
		return false
	end
	local action = self.actions[actionNameRaw]
	if action == nil then
		return false
	end
	local compiled = self:_compileBindings(action, bindingsRaw)
	if #compiled == 0 then
		return false
	end
	action.bindings = compiled
	self:_rebuildBindingIndex()
	return true
end

function Input.SetActionEnabled(self: Input, actionNameRaw: any, enabledRaw: any): boolean
	if typeof(actionNameRaw) ~= "string" then
		return false
	end
	local action = self.actions[actionNameRaw]
	if action == nil then
		return false
	end
	action.enabled = enabledRaw == true
	self:_rebuildBindingIndex()
	return true
end

function Input.UnbindAction(self: Input, actionNameRaw: any): boolean
	if typeof(actionNameRaw) ~= "string" then
		return false
	end
	if self.actions[actionNameRaw] == nil then
		return false
	end
	self.actions[actionNameRaw] = nil
	self:_rebuildBindingIndex()
	return true
end

function Input.SetLayerEnabled(self: Input, layerRaw: any, enabledRaw: any)
	local layer = normalizeLayer(layerRaw)
	self.layerEnabled[layer] = enabledRaw == true
end

function Input.SetLayerPriority(self: Input, layerRaw: any, priorityRaw: any)
	local layer = normalizeLayer(layerRaw)
	self.layerPriorities[layer] = clampPriority(priorityRaw, self.layerPriorities[layer] or 0)
	self:_rebuildBindingIndex()
end

function Input.GetLayerEnabled(self: Input, layerRaw: any): boolean
	local layer = normalizeLayer(layerRaw)
	return self.layerEnabled[layer] == true
end

function Input.Clear(self: Input)
	table.clear(self.actions)
	table.clear(self.bindingIndex)
	table.clear(self.activePresses)
	table.clear(self.lastTapByActionInput)
end

function Input.Destroy(self: Input)
	self:clear()
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	self.isInitialized = false
end

Input.BindAction = Input.BindAction
Input.RebindAction = Input.RebindAction
Input.UnbindAction = Input.UnbindAction
Input.SetActionEnabled = Input.SetActionEnabled
Input.SetLayerEnabled = Input.SetLayerEnabled
Input.SetLayerPriority = Input.SetLayerPriority
Input.GetLayerEnabled = Input.GetLayerEnabled
Input.Init = Input.Init
Input.Destroy = Input.Destroy

Input.new = Input.New
Input.init = Input.Init
Input.bindAction = Input.BindAction
Input.rebindAction = Input.RebindAction
Input.setActionEnabled = Input.SetActionEnabled
Input.unbindAction = Input.UnbindAction
Input.setLayerEnabled = Input.SetLayerEnabled
Input.setLayerPriority = Input.SetLayerPriority
Input.getLayerEnabled = Input.GetLayerEnabled
Input.clear = Input.Clear
Input.destroy = Input.Destroy

return Input
