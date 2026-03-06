--!strict
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Platform = require(script.Parent.Parent.Platform.Platform)

local UIController = {}
UIController.__index = UIController

export type ScreenHooks = {
	OnOpen: ((payload: any, controller: any) -> ())?,
	OnClose: ((payload: any, controller: any) -> ())?,
	OnPause: ((payload: any, controller: any) -> ())?,
	OnResume: ((payload: any, controller: any) -> ())?,
}

export type TransitionConfig = {
	enabled: boolean?,
	property: string?,
	openedValue: any?,
	closedValue: any?,
	spring: { [string]: any }?,
}

export type ScreenDefinition = {
	key: string,
	frame: GuiObject?,
	isModal: boolean?,
	zIndex: number?,
	closable: boolean?,
	initialFocus: GuiObject?,
	hooks: ScreenHooks?,
	transition: TransitionConfig?,
}

export type UIControllerConfig = {
	springAnimator: any?,
	platform: any?,
	escEnabled: boolean?,
	screenBaseZ: number?,
	modalBaseZ: number?,
	modalStepZ: number?,
}

export type UIController = typeof(setmetatable({} :: any, UIController))

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

local function safeDisconnect(connection: any?)
	if connection == nil then
		return
	end
	pcall(function()
		connection:Disconnect()
	end)
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function setVisible(frame: GuiObject?, visible: boolean)
	if frame == nil then
		return
	end
	pcall(function()
		(frame :: any).Visible = visible
	end)
end

local function applyZShift(root: GuiObject?, targetBase: number)
	if root == nil then
		return
	end
	local currentBase = root.ZIndex
	local delta = targetBase - currentBase
	if delta == 0 then
		return
	end
	root.ZIndex = targetBase
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(1, descendant.ZIndex + delta)
		end
	end
end

local function navigationModeFromPrimaryInput(primaryInputTypeRaw: any): string
	if primaryInputTypeRaw == "Gamepad" then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

function UIController.new(configRaw: UIControllerConfig?): UIController
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		registry = {} :: { [string]: any },
		activeScreenKey = nil :: string?,
		modalStack = {} :: { string },
		modalFocusStack = {} :: { GuiObject? },
		inputLocked = false,
		navigationMode = "KeyboardMouse",
		escEnabled = if config.escEnabled == nil then true else config.escEnabled == true,
		springAnimator = config.springAnimator,
		platform = if config.platform ~= nil then config.platform else Platform.new(),
		ownsPlatform = config.platform == nil,
		platformDisconnect = nil :: (() -> ())?,
		screenBaseZ = clampInteger(config.screenBaseZ, 10, 1, 10000),
		modalBaseZ = clampInteger(config.modalBaseZ, 300, 1, 10000),
		modalStepZ = clampInteger(config.modalStepZ, 40, 1, 10000),
		isInitialized = false,
		connections = {} :: { any },
	}, UIController)
	return self
end

function UIController._setNavigationModeFromPlatformSnapshot(self: UIController, snapshotRaw: any)
	if typeof(snapshotRaw) ~= "table" then
		return
	end
	self.navigationMode = navigationModeFromPrimaryInput(snapshotRaw.primaryInputType)
end

function UIController._syncNavigationModeFromPlatform(self: UIController): boolean
	local platform = self.platform
	if platform == nil then
		return false
	end

	if typeof((platform :: any).getSnapshot) == "function" then
		local ok, snapshot = pcall(function()
			return (platform :: any):getSnapshot()
		end)
		if ok then
			self:_setNavigationModeFromPlatformSnapshot(snapshot)
			return true
		end
	end

	if typeof((platform :: any).getPrimaryInputType) == "function" then
		local ok, primaryInputType = pcall(function()
			return (platform :: any):getPrimaryInputType()
		end)
		if ok then
			self.navigationMode = navigationModeFromPrimaryInput(primaryInputType)
			return true
		end
	end

	return false
end

function UIController.init(self: UIController)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.connections[#self.connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if self.inputLocked then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and self.escEnabled then
			if #self.modalStack > 0 then
				self:popModal()
				return
			end
			if self.activeScreenKey ~= nil then
				local screen = self.registry[self.activeScreenKey]
				if screen ~= nil and screen.closable ~= false then
					self:closeScreen(self.activeScreenKey)
				end
			end
		end
	end)

	if self.platform ~= nil then
		if typeof((self.platform :: any).init) == "function" then
			pcall(function()
				local platformAny = self.platform :: any
				platformAny:init()
			end)
		end

		self:_syncNavigationModeFromPlatform()
		if typeof((self.platform :: any).onChanged) == "function" then
			self.platformDisconnect = (self.platform :: any):onChanged(function(nextState: any)
				self:_setNavigationModeFromPlatformSnapshot(nextState)
			end)
		end
	end

	if self.platformDisconnect == nil then
		self.connections[#self.connections + 1] = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			if isGamepadInput(inputType) then
				self.navigationMode = "Gamepad"
			else
				self.navigationMode = "KeyboardMouse"
			end
		end)
	end
end

function UIController.registerScreen(self: UIController, definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end
	if typeof(definitionRaw.key) ~= "string" or definitionRaw.key == "" then
		return false
	end
	local key = definitionRaw.key
	if self.registry[key] ~= nil then
		return false
	end

	self.registry[key] = {
		key = key,
		frame = if typeof(definitionRaw.frame) == "Instance" then definitionRaw.frame else nil,
		isModal = definitionRaw.isModal == true,
		zIndex = clampInteger(definitionRaw.zIndex, self.screenBaseZ, 1, 10000),
		closable = if definitionRaw.closable == nil then true else definitionRaw.closable == true,
		initialFocus = if typeof(definitionRaw.initialFocus) == "Instance" then definitionRaw.initialFocus else nil,
		hooks = if typeof(definitionRaw.hooks) == "table" then definitionRaw.hooks else {},
		transition = if typeof(definitionRaw.transition) == "table" then definitionRaw.transition else {},
	}
	setVisible(self.registry[key].frame, false)
	return true
end

function UIController.unregisterScreen(self: UIController, keyRaw: any)
	if typeof(keyRaw) ~= "string" then
		return
	end
	if self.activeScreenKey == keyRaw then
		self:closeScreen(keyRaw)
	end
	for index = #self.modalStack, 1, -1 do
		if self.modalStack[index] == keyRaw then
			table.remove(self.modalStack, index)
			table.remove(self.modalFocusStack, index)
		end
	end
	self.registry[keyRaw] = nil
end

function UIController._playTransition(self: UIController, screen: any, opening: boolean)
	local frame = screen.frame
	if frame == nil then
		return
	end
	local transition = screen.transition
	if transition == nil or transition.enabled == false then
		return
	end
	local property = if typeof(transition.property) == "string" then transition.property else "BackgroundTransparency"
	local target = if opening then transition.openedValue else transition.closedValue
	if target == nil then
		if property == "BackgroundTransparency" then
			target = if opening then 0 else 1
		elseif property == "GroupTransparency" then
			target = if opening then 0 else 1
		end
	end
	if target == nil then
		return
	end

	if self.springAnimator ~= nil and typeof((self.springAnimator :: any).animate) == "function" then
		local springAnimatorAny = self.springAnimator :: any
		springAnimatorAny:animate(frame, property, target, transition.spring)
		return
	end
	pcall(function()
		(frame :: any)[property] = target
	end)
end

function UIController._fireHook(self: UIController, screen: any, hookName: string, payload: any)
	local hooks = screen.hooks
	if hooks == nil then
		return
	end
	local callback = hooks[hookName]
	if typeof(callback) ~= "function" then
		return
	end
	callback(payload, self)
end

function UIController._setScreenVisible(self: UIController, screen: any, visible: boolean, zIndex: number)
	if screen.frame ~= nil then
		applyZShift(screen.frame, zIndex)
	end
	setVisible(screen.frame, visible)
	if visible then
		self:_playTransition(screen, true)
	else
		self:_playTransition(screen, false)
	end
end

function UIController.openScreen(self: UIController, keyRaw: any, payload: any?): boolean
	if typeof(keyRaw) ~= "string" then
		return false
	end
	local screen = self.registry[keyRaw]
	if screen == nil or screen.isModal then
		return false
	end
	if self.activeScreenKey == keyRaw then
		return true
	end
	if self.activeScreenKey ~= nil then
		self:closeScreen(self.activeScreenKey)
	end

	self.activeScreenKey = keyRaw
	self:_setScreenVisible(screen, true, screen.zIndex)
	self:_fireHook(screen, "OnOpen", payload)
	return true
end

function UIController.closeScreen(self: UIController, keyRaw: any?, payload: any?): boolean
	local key = if typeof(keyRaw) == "string" then keyRaw else self.activeScreenKey
	if key == nil then
		return false
	end
	local screen = self.registry[key]
	if screen == nil then
		return false
	end
	if self.activeScreenKey ~= key then
		return false
	end

	self:_fireHook(screen, "OnClose", payload)
	self:_setScreenVisible(screen, false, screen.zIndex)
	self.activeScreenKey = nil
	return true
end

function UIController.pushModal(self: UIController, keyRaw: any, payload: any?): boolean
	if typeof(keyRaw) ~= "string" then
		return false
	end
	local screen = self.registry[keyRaw]
	if screen == nil or not screen.isModal then
		return false
	end

	local currentTopKey = self.modalStack[#self.modalStack]
	if currentTopKey ~= nil then
		local currentTop = self.registry[currentTopKey]
		if currentTop ~= nil then
			self:_fireHook(currentTop, "OnPause", payload)
		end
	end

	self.modalStack[#self.modalStack + 1] = keyRaw
	self.modalFocusStack[#self.modalFocusStack + 1] = GuiService.SelectedObject

	for index = 1, #self.modalStack do
		local modalKey = self.modalStack[index]
		local modal = self.registry[modalKey]
		if modal ~= nil then
			self:_setScreenVisible(modal, true, self.modalBaseZ + (index - 1) * self.modalStepZ)
		end
	end

	self:_fireHook(screen, "OnOpen", payload)
	if self.navigationMode == "Gamepad" and screen.initialFocus ~= nil then
		GuiService.SelectedObject = screen.initialFocus
	end
	return true
end

function UIController.popModal(self: UIController, payload: any?): boolean
	local topIndex = #self.modalStack
	if topIndex <= 0 then
		return false
	end
	local key = self.modalStack[topIndex]
	local screen = self.registry[key]
	table.remove(self.modalStack, topIndex)
	local previousFocus = table.remove(self.modalFocusStack, topIndex)

	if screen ~= nil then
		self:_fireHook(screen, "OnClose", payload)
		self:_setScreenVisible(screen, false, self.modalBaseZ)
	end

	local newTopKey = self.modalStack[#self.modalStack]
	if newTopKey ~= nil then
		local newTop = self.registry[newTopKey]
		if newTop ~= nil then
			self:_fireHook(newTop, "OnResume", payload)
		end
	end

	for index = 1, #self.modalStack do
		local modal = self.registry[self.modalStack[index]]
		if modal ~= nil then
			applyZShift(modal.frame, self.modalBaseZ + (index - 1) * self.modalStepZ)
		end
	end

	if self.navigationMode == "Gamepad" then
		GuiService.SelectedObject = previousFocus
	end
	return true
end

function UIController.closeTopModal(self: UIController, payload: any?): boolean
	return self:popModal(payload)
end

function UIController.setInputLocked(self: UIController, lockedRaw: any)
	self.inputLocked = lockedRaw == true
end

function UIController.isInputLocked(self: UIController): boolean
	return self.inputLocked
end

function UIController.setNavigationMode(self: UIController, modeRaw: any)
	if modeRaw == "Gamepad" or modeRaw == "KeyboardMouse" then
		self.navigationMode = modeRaw
	end
end

function UIController.getNavigationMode(self: UIController): string
	return self.navigationMode
end

function UIController.getActiveScreen(self: UIController): string?
	return self.activeScreenKey
end

function UIController.getTopModal(self: UIController): string?
	return self.modalStack[#self.modalStack]
end

function UIController.getModalStack(self: UIController): { string }
	return table.clone(self.modalStack)
end

function UIController.destroy(self: UIController)
	for key, screen in self.registry do
		if screen.isModal then
			setVisible(screen.frame, false)
		else
			if self.activeScreenKey == key then
				setVisible(screen.frame, false)
			end
		end
	end
	table.clear(self.registry)
	self.activeScreenKey = nil
	clearArray(self.modalStack)
	clearArray(self.modalFocusStack)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	if self.platformDisconnect ~= nil then
		self.platformDisconnect()
		self.platformDisconnect = nil
	end
	if self.ownsPlatform and self.platform ~= nil and typeof((self.platform :: any).destroy) == "function" then
		pcall(function()
			local platformAny = self.platform :: any
			platformAny:destroy()
		end)
	end
	self.platform = nil
	self.ownsPlatform = false
	self.isInitialized = false
end

UIController.RegisterScreen = UIController.registerScreen
UIController.UnregisterScreen = UIController.unregisterScreen
UIController.OpenScreen = UIController.openScreen
UIController.CloseScreen = UIController.closeScreen
UIController.PushModal = UIController.pushModal
UIController.PopModal = UIController.popModal
UIController.CloseTopModal = UIController.closeTopModal
UIController.SetInputLocked = UIController.setInputLocked
UIController.GetActiveScreen = UIController.getActiveScreen
UIController.Init = UIController.init
UIController.Destroy = UIController.destroy

return UIController
