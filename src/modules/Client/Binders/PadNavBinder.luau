--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Maid = require("Maid")
local Observable = require("Observable")
local Rx = require("Rx")

local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local padSlice = require(script:FindFirstAncestor("game").Client.UI.features.pad.state.padSlice)

type ObservableObject = {
	Subscribe: (
		self: ObservableObject,
		fireCallback: ((...any) -> ())?,
		failCallback: ((...any) -> ())?,
		completeCallback: ((...any) -> ())?
	) -> any,
	Pipe: (self: ObservableObject, transformers: { any }) -> ObservableObject,
}

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

type ThumbstickState = {
	key: "Left" | "Right",
	raw: Vector2,
	screen: Vector2,
	magnitude: number,
	active: boolean,
}

type ThumbstickSnapshot = {
	left: ThumbstickState,
	right: ThumbstickState,
	dominant: "Left" | "Right"?,
	lastUpdatedAt: number,
}

local PadNavBinder = {}
PadNavBinder.ServiceName = "PadNavBinder"

local EMPTY_THUMBSTICK_SNAPSHOT: ThumbstickSnapshot = {
	left = {
		key = "Left",
		raw = Vector2.zero,
		screen = Vector2.zero,
		magnitude = 0,
		active = false,
	},
	right = {
		key = "Right",
		raw = Vector2.zero,
		screen = Vector2.zero,
		magnitude = 0,
		active = false,
	},
	dominant = nil,
	lastUpdatedAt = 0,
}

local function cleanupTask(taskRaw: any)
	if type(taskRaw) == "function" then
		taskRaw()
		return
	end

	if typeof(taskRaw) == "RBXScriptConnection" then
		taskRaw:Disconnect()
		return
	end

	if type(taskRaw) == "table" and typeof((taskRaw :: any).Disconnect) == "function" then
		(taskRaw :: any):Disconnect()
	end
end

local function resolveGamepadNav(runtimeContextRaw: any): any?
	if runtimeContextRaw == nil then
		return nil
	end

	if typeof((runtimeContextRaw :: any).getGamepadNav) == "function" then
		local ok, gamepadNavOrError = pcall(function()
			return (runtimeContextRaw :: any):getGamepadNav()
		end)
		if ok then
			return gamepadNavOrError
		end
	end

	return (runtimeContextRaw :: any).gamepadNav
end

local function resolveThumbstickSnapshot(gamepadNavRaw: any): ThumbstickSnapshot
	if gamepadNavRaw ~= nil and typeof((gamepadNavRaw :: any).getThumbstickState) == "function" then
		local ok, snapshotOrError = pcall(function()
			return (gamepadNavRaw :: any):getThumbstickState()
		end)
		if ok and typeof(snapshotOrError) == "table" then
			return snapshotOrError :: ThumbstickSnapshot
		end
	end

	return EMPTY_THUMBSTICK_SNAPSHOT
end

function PadNavBinder._observeThumbsticks(self): ObservableObject
	local gamepadNav = self._gamepadNav
	if gamepadNav == nil then
		return Rx.of(EMPTY_THUMBSTICK_SNAPSHOT) :: ObservableObject
	end

	return Observable.new(function(sub)
		local disconnect = nil

		if typeof((gamepadNav :: any).onThumbstickChanged) == "function" then
			disconnect = (gamepadNav :: any):onThumbstickChanged(function(snapshot: any)
				sub:Fire(snapshot)
			end)
		end

		sub:Fire(resolveThumbstickSnapshot(gamepadNav))

		return function()
			cleanupTask(disconnect)
		end
	end) :: ObservableObject
end

function PadNavBinder._bindStreams(self)
	self._maid:DoCleaning()
	self._gamepadNav = resolveGamepadNav(self._runtimeContext)

	padSlice.setPlatform(PlatformServiceClient:getPlatform())
	padSlice.updateThumbsticks(resolveThumbstickSnapshot(self._gamepadNav))

	self._maid:GiveTask(Rx.combineLatestDefer({
		platform = PlatformServiceClient:ObservePlatform(),
		thumbsticks = self:_observeThumbsticks(),
	}):Subscribe(function(snapshot: { platform: string, thumbsticks: ThumbstickSnapshot })
		local platform = snapshot.platform
		padSlice.setPlatform(platform)

		if platform == "Gamepad" then
			padSlice.updateThumbsticks(snapshot.thumbsticks)
		else
			padSlice.updateThumbsticks(EMPTY_THUMBSTICK_SNAPSHOT)
		end
	end))
end

function PadNavBinder.Init(self, serviceBag: any)
	assert(self._serviceBag == nil, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new() :: MaidClass

	self._runtimeContext = CoreRuntime.getClientRuntime()
	if self._runtimeContext ~= nil and typeof((self._runtimeContext :: any).init) == "function" then
		(self._runtimeContext :: any):init()
	end

	if not PlatformServiceClient:isReady() then
		PlatformServiceClient:init()
	end

	self:_bindStreams()
end

function PadNavBinder.Start(_self)
	-- this bridge binds during Init so pad state is ready before the UI mounts
end

function PadNavBinder.Destroy(self)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid:Destroy()
		self._maid = nil
	end

	self._gamepadNav = nil
	self._runtimeContext = nil
	self._serviceBag = nil
	padSlice.resetPadState()
end

return PadNavBinder
