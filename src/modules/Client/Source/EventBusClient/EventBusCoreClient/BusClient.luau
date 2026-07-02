
local require = require(script.Parent.loader).load(script)

local EventRegistryClient = require("EventRegistryClient")
local EventBusShared = require("EventBusShared")

local bus = EventBusShared.Core.EventBus.new("EventBusClient")

local BusClient = {}

function BusClient:On(eventName: string, callback: (...any) -> ())
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:On(eventName, callback)
end

function BusClient:Once(eventName: string, callback: (...any) -> ())
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:Once(eventName, callback)
end

function BusClient:Fire(eventName: string, ...: any)
	if not EventRegistryClient.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function BusClient:Wait(eventName: string): ...any
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:Wait(eventName)
end

function BusClient:Observe(eventName: string)
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:Observe(eventName)
end

function BusClient:GetRxSignal(eventName: string)
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:GetRxSignal(eventName)
end

function BusClient:Off(eventName: string)
	if not EventRegistryClient.Assert(eventName) then
		return
	end

	bus:Off(eventName)
end

function BusClient:Has(eventName: string): boolean
	if not EventRegistryClient.Assert(eventName) then
		return false
	end

	return bus:Has(eventName)
end

function BusClient:GetSignal(eventName: string)
	if not EventRegistryClient.Assert(eventName) then
		return nil
	end

	return bus:GetSignal(eventName)
end

function BusClient:GetEventNames(): { string }
	return bus:GetEventNames()
end

function BusClient:Clear(eventName: string?)
	if eventName ~= nil and not EventRegistryClient.Assert(eventName) then
		return
	end

	bus:Clear(eventName)
end

function BusClient:Destroy()
	bus:Destroy()
end
return BusClient
