--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing game root")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Rx = loader("Rx") :: any
local RxSignal = loader("RxSignal") :: any

local EventName = require(script.Parent.EventName)
local Signal = require(script.Parent.signals.Signal)

type Signal = Signal.Signal

type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

local EventBus = {}
EventBus.__index = EventBus

export type EventBus = typeof(setmetatable({} :: {
	Name: string,
	_destroyed: boolean,
	_signals: { [string]: Signal },
	_rxSignals: { [string]: RxSignalObject },
}, EventBus))

local function getSortedKeys(source: { [string]: any }): { string }
	local keys: { string } = {}
	for key in source do
		keys[#keys + 1] = key
	end

	table.sort(keys)
	return keys
end

function EventBus.new(name: string?): EventBus
	return setmetatable({
		Name = if typeof(name) == "string" and name ~= "" then name else "EventBus",
		_destroyed = false,
		_signals = {},
		_rxSignals = {},
	}, EventBus)
end

function EventBus._assertAlive(self: EventBus)
	assert(not self._destroyed, "cannot reuse destroyed event bus")
end

function EventBus.GetSignal(self: EventBus, eventNameRaw: any): Signal
	self:_assertAlive()

	local eventName = EventName.Assert(eventNameRaw)
	local signal = self._signals[eventName]
	if signal ~= nil then
		return signal
	end

	signal = Signal.new()
	self._signals[eventName] = signal

	return signal
end

function EventBus.On(self: EventBus, eventNameRaw: any, callback: (...any) -> ())
	return self:GetSignal(eventNameRaw):Connect(callback)
end

function EventBus.Once(self: EventBus, eventNameRaw: any, callback: (...any) -> ())
	return self:GetSignal(eventNameRaw):Once(callback)
end

function EventBus.Fire(self: EventBus, eventNameRaw: any, ...: any)
	if self._destroyed then
		return
	end

	local eventName = EventName.Sanitize(eventNameRaw)
	if eventName == nil then
		return
	end

	local signal = self._signals[eventName]
	if signal == nil then
		return
	end

	signal:Fire(...)
end

function EventBus.Wait(self: EventBus, eventNameRaw: any): ...any
	return self:GetSignal(eventNameRaw):Wait()
end

function EventBus.Off(self: EventBus, eventNameRaw: any)
	if self._destroyed then
		return
	end

	local eventName = EventName.Sanitize(eventNameRaw)
	if eventName == nil then
		return
	end

	local signal = self._signals[eventName]
	if signal == nil then
		return
	end

	signal:Destroy()
	self._signals[eventName] = nil
	self._rxSignals[eventName] = nil
end

function EventBus.Has(self: EventBus, eventNameRaw: any): boolean
	local eventName = EventName.Sanitize(eventNameRaw)
	return eventName ~= nil and self._signals[eventName] ~= nil
end

function EventBus.GetEventNames(self: EventBus): { string }
	return getSortedKeys(self._signals)
end

function EventBus.Clear(self: EventBus, eventNameRaw: any?)
	if eventNameRaw ~= nil then
		self:Off(eventNameRaw)
		return
	end

	for eventName in table.clone(self._signals) do
		self:Off(eventName)
	end
end

function EventBus.Destroy(self: EventBus)
	if self._destroyed then
		return
	end

	self:Clear()
	self._destroyed = true
	table.clear(self._signals)
	table.clear(self._rxSignals)
end

function EventBus.Observe(self: EventBus, eventNameRaw: any)
	return Rx.fromSignal(self:GetSignal(eventNameRaw))
end

function EventBus.GetRxSignal(self: EventBus, eventNameRaw: any): RxSignalObject
	self:_assertAlive()

	local eventName = EventName.Assert(eventNameRaw)
	local rxSignal = self._rxSignals[eventName]
	if rxSignal ~= nil then
		return rxSignal
	end

	rxSignal = RxSignal.new(function()
		return self:Observe(eventName)
	end) :: RxSignalObject

	self._rxSignals[eventName] = rxSignal

	return rxSignal
end

EventBus.on = EventBus.On
EventBus.once = EventBus.Once
EventBus.fire = EventBus.Fire
EventBus.wait = EventBus.Wait
EventBus.off = EventBus.Off
EventBus.has = EventBus.Has
EventBus.getSignal = EventBus.GetSignal
EventBus.getEventNames = EventBus.GetEventNames
EventBus.clear = EventBus.Clear
EventBus.destroy = EventBus.Destroy
EventBus.observe = EventBus.Observe
EventBus.getRxSignal = EventBus.GetRxSignal

return EventBus
