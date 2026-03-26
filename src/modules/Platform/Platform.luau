--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Platform = {}
Platform.__index = Platform

export type PlatformSnapshot = {
	isMobile: boolean,
	isConsole: boolean,
	isDesktop: boolean,
	primaryInputType: string,
	supportsHover: boolean,
	supportsRightClick: boolean,
	touchEnabled: boolean,
	keyboardEnabled: boolean,
	mouseEnabled: boolean,
	gamepadEnabled: boolean,
}

export type PlatformConfig = {
	eventBus: any?,
	eventChannel: string?,
	changeEvent: string?,
}

export type PlatformListener = (nextState: PlatformSnapshot, prevState: PlatformSnapshot?) -> ()

export type Platform = typeof(setmetatable({} :: any, Platform))

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type ChangedSignal = {
	Connect: (self: ChangedSignal, callback: PlatformListener) -> SignalConnection,
	Fire: (self: ChangedSignal, nextState: PlatformSnapshot, prevState: PlatformSnapshot?) -> (),
	DisconnectAll: (self: ChangedSignal) -> (),
	Destroy: (self: ChangedSignal) -> (),
}

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function computePrimaryInputType(lastInputType: Enum.UserInputType?, touchEnabled: boolean, keyboardEnabled: boolean, gamepadEnabled: boolean): string
	if lastInputType ~= nil then
		if isGamepadInput(lastInputType) then
			return "Gamepad"
		end
		if lastInputType == Enum.UserInputType.Touch then
			return "Touch"
		end
		if lastInputType == Enum.UserInputType.MouseButton1
			or lastInputType == Enum.UserInputType.MouseButton2
			or lastInputType == Enum.UserInputType.MouseButton3
			or lastInputType == Enum.UserInputType.MouseMovement
			or lastInputType == Enum.UserInputType.MouseWheel
			or lastInputType == Enum.UserInputType.Keyboard
		then
			return "KeyboardMouse"
		end
	end

	if touchEnabled and not keyboardEnabled then
		return "Touch"
	end
	if gamepadEnabled and not keyboardEnabled and not touchEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

local function buildSnapshot(lastInputType: Enum.UserInputType?): PlatformSnapshot
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	local mouseEnabled = UserInputService.MouseEnabled
	local gamepadEnabled = UserInputService.GamepadEnabled
	local primaryInputType = computePrimaryInputType(lastInputType, touchEnabled, keyboardEnabled, gamepadEnabled)

	local isMobile = touchEnabled and not keyboardEnabled and not gamepadEnabled
	local isConsole = gamepadEnabled and not keyboardEnabled and not mouseEnabled
	local isDesktop = keyboardEnabled and mouseEnabled
	
	local supportsHover = mouseEnabled
	local supportsRightClick = mouseEnabled and keyboardEnabled

	return {
		isMobile = isMobile,
		isConsole = isConsole,
		isDesktop = isDesktop,
		primaryInputType = primaryInputType,
		supportsHover = supportsHover,
		supportsRightClick = supportsRightClick,
		touchEnabled = touchEnabled,
		keyboardEnabled = keyboardEnabled,
		mouseEnabled = mouseEnabled,
		gamepadEnabled = gamepadEnabled,
	}
end

local function snapshotsEqual(a: PlatformSnapshot?, b: PlatformSnapshot?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.isMobile == b.isMobile
		and a.isConsole == b.isConsole
		and a.isDesktop == b.isDesktop
		and a.primaryInputType == b.primaryInputType
		and a.supportsHover == b.supportsHover
		and a.supportsRightClick == b.supportsRightClick
		and a.touchEnabled == b.touchEnabled
		and a.keyboardEnabled == b.keyboardEnabled
		and a.mouseEnabled == b.mouseEnabled
		and a.gamepadEnabled == b.gamepadEnabled
end

local function cloneSnapshot(snapshot: PlatformSnapshot): PlatformSnapshot
	return {
		isMobile = snapshot.isMobile,
		isConsole = snapshot.isConsole,
		isDesktop = snapshot.isDesktop,
		primaryInputType = snapshot.primaryInputType,
		supportsHover = snapshot.supportsHover,
		supportsRightClick = snapshot.supportsRightClick,
		touchEnabled = snapshot.touchEnabled,
		keyboardEnabled = snapshot.keyboardEnabled,
		mouseEnabled = snapshot.mouseEnabled,
		gamepadEnabled = snapshot.gamepadEnabled,
	}
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

function Platform.new(configRaw: PlatformConfig?): Platform
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "platform"),
		changeEvent = normalizeEventName(config.changeEvent, "changed"),
		snapshot = nil :: PlatformSnapshot?,
		lastInputType = nil :: Enum.UserInputType?,
		connections = {} :: { RBXScriptConnection? },
		changedSignal = Signal.new() :: ChangedSignal,
		isInitialized = false,
	}, Platform)
	return self
end

function Platform._emitChange(self: Platform, nextState: PlatformSnapshot, prevState: PlatformSnapshot?)
	self.changedSignal:Fire(nextState, prevState)
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.changeEvent, {
			nextState = nextState,
			prevState = prevState,
		})
	end
end

function Platform._refresh(self: Platform)
	local nextSnapshot = buildSnapshot(self.lastInputType)
	local prevSnapshot = self.snapshot
	if snapshotsEqual(nextSnapshot, prevSnapshot) then
		return
	end
	self.snapshot = nextSnapshot
	self:_emitChange(cloneSnapshot(nextSnapshot), if prevSnapshot ~= nil then cloneSnapshot(prevSnapshot) else nil)
end

function Platform.init(self: Platform)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self.snapshot = buildSnapshot(self.lastInputType)
	self.connections[#self.connections + 1] = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		self.lastInputType = inputType
		self:_refresh()
	end)
	self.connections[#self.connections + 1] = UserInputService.GamepadConnected:Connect(function()
		self:_refresh()
	end)
	self.connections[#self.connections + 1] = UserInputService.GamepadDisconnected:Connect(function()
		self:_refresh()
	end)
end

function Platform.onChanged(self: Platform, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.changedSignal:Connect(callbackRaw :: PlatformListener)
	return function()
		connection:Disconnect()
	end
end

function Platform.getSnapshot(self: Platform): PlatformSnapshot
	if self.snapshot == nil then
		self.snapshot = buildSnapshot(self.lastInputType)
	end
	return cloneSnapshot(self.snapshot :: PlatformSnapshot)
end

function Platform.isMobile(self: Platform): boolean
	return self:getSnapshot().isMobile
end

function Platform.isConsole(self: Platform): boolean
	return self:getSnapshot().isConsole
end

function Platform.isDesktop(self: Platform): boolean
	return self:getSnapshot().isDesktop
end

function Platform.getPrimaryInputType(self: Platform): string
	return self:getSnapshot().primaryInputType
end

function Platform.supportsHover(self: Platform): boolean
	return self:getSnapshot().supportsHover
end

function Platform.supportsRightClick(self: Platform): boolean
	return self:getSnapshot().supportsRightClick
end

function Platform.destroy(self: Platform)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	self.changedSignal:DisconnectAll()
	self.changedSignal:Destroy()
	self.isInitialized = false
end

Platform.IsMobile = Platform.isMobile
Platform.IsConsole = Platform.isConsole
Platform.IsDesktop = Platform.isDesktop
Platform.GetPrimaryInputType = Platform.getPrimaryInputType
Platform.SupportsHover = Platform.supportsHover
Platform.SupportsRightClick = Platform.supportsRightClick
Platform.GetSnapshot = Platform.getSnapshot
Platform.OnChanged = Platform.onChanged
Platform.Init = Platform.init
Platform.Destroy = Platform.destroy

return Platform
