--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local RunService = game:GetService("RunService")

local EventBus = require(script.Parent.EventBus)
local TickScheduler = require(script.Parent.TickScheduler)

local Runtime = {}
Runtime.__index = Runtime

export type RuntimeContext = typeof(setmetatable({} :: any, Runtime))

type RuntimeConfig = {
	eventBus: any?,
	tickScheduler: any?,
	fixedStep: number?,
	platform: any?,
	input: any?,
	gestures: any?,
	haptics: any?,
	cursor: any?,
	perfTier: any?,
	gamepadNav: any?,
	hudScaler: any?,
}

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

local function safeInit(value: any?)
	if value == nil then
		return
	end
	if typeof(value.init) == "function" then
		pcall(function()
			value:init()
		end)
	end
end

local function safeDestroy(value: any?)
	if value == nil then
		return
	end
	if typeof(value.destroy) == "function" then
		pcall(function()
			value:destroy()
		end)
	end
end

local singletonClient: RuntimeContext? = nil
local singletonServer: RuntimeContext? = nil

local function buildClientModules(self: RuntimeContext, config: RuntimeConfig)
	local platformFolder = script.Parent.Parent.Platform
	local Platform = require(platformFolder.Platform)
	local Input = require(platformFolder.Input)
	local Gestures = require(platformFolder.Gestures)
	local Haptics = require(platformFolder.Haptics)
	local Cursor = require(platformFolder.Cursor)
	local PerfTier = require(platformFolder.PerfTier)

	self.platform = if config.platform ~= nil
		then config.platform
		else Platform.new({
			eventBus = self.eventBus,
			eventChannel = "platform",
			changeEvent = "changed",
		})
	self.input = if config.input ~= nil
		then config.input
		else Input.new({
			eventBus = self.eventBus,
			eventChannel = "input",
			actionEvent = "action",
			tickScheduler = self.tickScheduler,
		})
	self.gestures = if config.gestures ~= nil
		then config.gestures
		else Gestures.new({
			eventBus = self.eventBus,
			eventChannel = "gestures",
			tickScheduler = self.tickScheduler,
		})
	self.haptics = if config.haptics ~= nil
		then config.haptics
		else Haptics.new({
			eventBus = self.eventBus,
			eventChannel = "haptics",
			tickScheduler = self.tickScheduler,
			enabled = true,
		})
	self.cursor = if config.cursor ~= nil
		then config.cursor
		else Cursor.new({
			input = self.input,
			eventBus = self.eventBus,
			eventChannel = "cursor",
			changeEvent = "changed",
			tickScheduler = self.tickScheduler,
			useCustomIcon = true,
		})
	self.perfTier = if config.perfTier ~= nil
		then config.perfTier
		else PerfTier.new({
			eventBus = self.eventBus,
			eventChannel = "perf",
			changeEvent = "tierChanged",
			tickScheduler = self.tickScheduler,
		})

	self.gamepadNav = config.gamepadNav
	self.hudScaler = config.hudScaler
end

function Runtime.new(configRaw: RuntimeConfig?): RuntimeContext
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		isClient = RunService:IsClient(),
		eventBus = if config.eventBus ~= nil then config.eventBus else EventBus.new(),
		tickScheduler = if config.tickScheduler ~= nil
			then config.tickScheduler
			else TickScheduler.new({
				fixedStep = clampNumber(config.fixedStep, 1 / 60, 1 / 240, 1),
			}),
		platform = nil,
		input = nil,
		gestures = nil,
		haptics = nil,
		cursor = nil,
		perfTier = nil,
		gamepadNav = config.gamepadNav,
		hudScaler = config.hudScaler,
		heartbeatConnection = nil :: RBXScriptConnection?,
		isInitialized = false,
	}, Runtime)

	if self.isClient then
		buildClientModules(self, config)
	end

	return self
end

function Runtime._ensureHeartbeat(self: RuntimeContext)
	if self.heartbeatConnection ~= nil then
		return
	end
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		local scheduler = self.tickScheduler
		if scheduler ~= nil and typeof((scheduler :: any).update) == "function" then
			local schedulerAny = scheduler :: any
			schedulerAny:update(dt)
		end
	end)
end

function Runtime.init(self: RuntimeContext): RuntimeContext
	if self.isInitialized then
		return self
	end
	self.isInitialized = true
	self:_ensureHeartbeat()
	safeInit(self.platform)
	safeInit(self.input)
	safeInit(self.gestures)
	safeInit(self.haptics)
	safeInit(self.cursor)
	safeInit(self.perfTier)
	safeInit(self.gamepadNav)
	safeInit(self.hudScaler)
	return self
end

function Runtime.getGamepadNav(self: RuntimeContext, configRaw: any?): any
	if self.gamepadNav ~= nil then
		return self.gamepadNav
	end
	if not self.isClient then
		return nil
	end
	local GamepadNav = require(script.Parent.Parent.Platform.GamepadNav)
	self.gamepadNav = GamepadNav.new(if typeof(configRaw) == "table"
		then configRaw
		else {
			eventBus = self.eventBus,
			eventChannel = "gamepad.nav",
			focusEvent = "focusChanged",
		})
	if self.isInitialized then
		safeInit(self.gamepadNav)
	end
	return self.gamepadNav
end

function Runtime.getHUDScaler(self: RuntimeContext, configRaw: any?): any
	if self.hudScaler ~= nil then
		return self.hudScaler
	end
	if not self.isClient then
		return nil
	end
	local HUDScaler = require(script.Parent.Parent.Platform.HUDScaler)
	local config = if typeof(configRaw) == "table" then Sift.Dictionary.copy(configRaw) else {}
	if config.platform == nil then
		config.platform = self.platform
	end
	if config.eventBus == nil then
		config.eventBus = self.eventBus
	end
	self.hudScaler = HUDScaler.new(config)
	if self.isInitialized then
		safeInit(self.hudScaler)
	end
	return self.hudScaler
end

function Runtime.getEventBus(self: RuntimeContext): any
	return self.eventBus
end

function Runtime.getTickScheduler(self: RuntimeContext): any
	return self.tickScheduler
end

function Runtime.destroy(self: RuntimeContext)
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end
	safeDestroy(self.hudScaler)
	safeDestroy(self.gamepadNav)
	safeDestroy(self.perfTier)
	safeDestroy(self.cursor)
	safeDestroy(self.haptics)
	safeDestroy(self.gestures)
	safeDestroy(self.input)
	safeDestroy(self.platform)
	safeDestroy(self.tickScheduler)
	safeDestroy(self.eventBus)
	self.hudScaler = nil
	self.gamepadNav = nil
	self.perfTier = nil
	self.cursor = nil
	self.haptics = nil
	self.gestures = nil
	self.input = nil
	self.platform = nil
	self.isInitialized = false
end

function Runtime.getClientRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if singletonClient == nil then
		singletonClient = Runtime.new(configRaw)
	end
	return singletonClient :: RuntimeContext
end

function Runtime.getServerRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if singletonServer == nil then
		singletonServer = Runtime.new(configRaw)
	end
	return singletonServer :: RuntimeContext
end

function Runtime.getSharedRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if RunService:IsClient() then
		return Runtime.getClientRuntime(configRaw)
	end
	return Runtime.getServerRuntime(configRaw)
end

function Runtime.destroyClientRuntime()
	if singletonClient == nil then
		return
	end
	singletonClient:destroy()
	singletonClient = nil
end

function Runtime.destroyServerRuntime()
	if singletonServer == nil then
		return
	end
	singletonServer:destroy()
	singletonServer = nil
end

Runtime.Init = Runtime.init
Runtime.Destroy = Runtime.destroy
Runtime.GetGamepadNav = Runtime.getGamepadNav
Runtime.GetHUDScaler = Runtime.getHUDScaler
Runtime.GetEventBus = Runtime.getEventBus
Runtime.GetTickScheduler = Runtime.getTickScheduler

return Runtime
