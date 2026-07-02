local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local RunService = game:GetService("RunService")

local EventBus = require("CoreEventBus")
local MaidTaskUtils = require("MaidTaskUtils")
local TickScheduler = require("TickScheduler")

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
	if typeof(value.Init) == "function" then
		pcall(function()
			value:Init()
		end)
	end
end

local function safeDestroy(value: any?)
	if value == nil or not MaidTaskUtils.isValidTask(value) then
		return
	end
	pcall(function()
		MaidTaskUtils.doTask(value)
	end)
end

local singletonClient: RuntimeContext? = nil
local singletonServer: RuntimeContext? = nil

local function buildClientModules(self: RuntimeContext, config: RuntimeConfig)
	local platformFolder = script:FindFirstAncestor("game").Shared.Source.Platform.Modules
	local Platform = require(platformFolder.PlatformUtils)
	local Input = require(platformFolder.Input)
	local Gestures = require(platformFolder.Gestures)
	local Haptics = require(platformFolder.Haptics)
	local Cursor = require(platformFolder.Cursor)
	local PerfTier = require(platformFolder.PerfTier)

	self.platform = if config.platform ~= nil
		then config.platform
		else Platform.New({
			eventBus = self.eventBus,
			eventChannel = "platform",
			changeEvent = "changed",
		})
	self.input = if config.input ~= nil
		then config.input
		else Input.New({
			eventBus = self.eventBus,
			eventChannel = "input",
			actionEvent = "action",
			tickScheduler = self.tickScheduler,
		})
	self.gestures = if config.gestures ~= nil
		then config.gestures
		else Gestures.New({
			eventBus = self.eventBus,
			eventChannel = "gestures",
			tickScheduler = self.tickScheduler,
		})
	self.haptics = if config.haptics ~= nil
		then config.haptics
		else Haptics.New({
			eventBus = self.eventBus,
			eventChannel = "haptics",
			tickScheduler = self.tickScheduler,
			enabled = true,
		})
	self.cursor = if config.cursor ~= nil
		then config.cursor
		else Cursor.New({
			input = self.input,
			eventBus = self.eventBus,
			eventChannel = "cursor",
			changeEvent = "changed",
			tickScheduler = self.tickScheduler,
			useCustomIcon = true,
		})
	self.perfTier = if config.perfTier ~= nil
		then config.perfTier
		else PerfTier.New({
			eventBus = self.eventBus,
			eventChannel = "perf",
			changeEvent = "tierChanged",
			tickScheduler = self.tickScheduler,
		})

	self.gamepadNav = config.gamepadNav
	self.hudScaler = config.hudScaler
end

function Runtime.New(configRaw: RuntimeConfig?): RuntimeContext
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local self = setmetatable({
		isClient = RunService:IsClient(),
		eventBus = if config.eventBus ~= nil then config.eventBus else EventBus.New(),
		tickScheduler = if config.tickScheduler ~= nil
			then config.tickScheduler
			else TickScheduler.New({
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
		if scheduler ~= nil and typeof((scheduler :: any).Update) == "function" then
			local schedulerAny = scheduler :: any
			schedulerAny:Update(dt)
		end
	end)
end

function Runtime.Init(self: RuntimeContext): RuntimeContext
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

function Runtime.GetGamepadNav(self: RuntimeContext, configRaw: any?): any
	if self.gamepadNav ~= nil then
		return self.gamepadNav
	end
	if not self.isClient then
		return nil
	end
	local GamepadNav = require("GamepadNav")
	self.gamepadNav = GamepadNav.New(if typeof(configRaw) == "table"
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

function Runtime.GetHUDScaler(self: RuntimeContext, configRaw: any?): any
	if self.hudScaler ~= nil then
		return self.hudScaler
	end
	if not self.isClient then
		return nil
	end
	local HUDScaler = require("HudScaler")
	local config = if typeof(configRaw) == "table" then Sift.Dictionary.copy(configRaw) else {} :: any
	if config.platform == nil then
		config.platform = self.platform
	end
	if config.eventBus == nil then
		config.eventBus = self.eventBus
	end
	self.hudScaler = HUDScaler.New(config)
	if self.isInitialized then
		safeInit(self.hudScaler)
	end
	return self.hudScaler
end

function Runtime.GetEventBus(self: RuntimeContext): any
	return self.eventBus
end

function Runtime.GetTickScheduler(self: RuntimeContext): any
	return self.tickScheduler
end

function Runtime.Destroy(self: RuntimeContext)
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

function Runtime.GetClientRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if singletonClient == nil then
		singletonClient = Runtime.New(configRaw)
	end
	return singletonClient :: RuntimeContext
end

function Runtime.GetServerRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if singletonServer == nil then
		singletonServer = Runtime.New(configRaw)
	end
	return singletonServer :: RuntimeContext
end

function Runtime.GetSharedRuntime(configRaw: RuntimeConfig?): RuntimeContext
	if RunService:IsClient() then
		return Runtime.GetClientRuntime(configRaw)
	end
	return Runtime.GetServerRuntime(configRaw)
end

function Runtime.DestroyClientRuntime()
	if singletonClient == nil then
		return
	end
	singletonClient:Destroy()
	singletonClient = nil
end

function Runtime.DestroyServerRuntime()
	if singletonServer == nil then
		return
	end
	singletonServer:Destroy()
	singletonServer = nil
end

return Runtime
