
local require = require(script.Parent.loader).load(script)

local EventRegistryServer = require("EventRegistryServer")
local EventBusShared = require("EventBusShared")

local bus = EventBusShared.Core.EventBus.new("EventBusServer")

local BusServer = {}

function BusServer:On(eventName: string, callback: (...any) -> ())
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:On(eventName, callback)
end

function BusServer:Once(eventName: string, callback: (...any) -> ())
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:Once(eventName, callback)
end

function BusServer:Fire(eventName: string, ...: any)
	if not EventRegistryServer.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function BusServer:Wait(eventName: string): ...any
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:Wait(eventName)
end

function BusServer:Observe(eventName: string)
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:Observe(eventName)
end

function BusServer:GetRxSignal(eventName: string)
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:GetRxSignal(eventName)
end

function BusServer:Off(eventName: string)
	if not EventRegistryServer.Assert(eventName) then
		return
	end

	bus:Off(eventName)
end

function BusServer:Has(eventName: string): boolean
	if not EventRegistryServer.Assert(eventName) then
		return false
	end

	return bus:Has(eventName)
end

function BusServer:GetSignal(eventName: string)
	if not EventRegistryServer.Assert(eventName) then
		return nil
	end

	return bus:GetSignal(eventName)
end

function BusServer:GetEventNames(): { string }
	return bus:GetEventNames()
end

function BusServer:Clear(eventName: string?)
	if eventName ~= nil and not EventRegistryServer.Assert(eventName) then
		return
	end

	bus:Clear(eventName)
end

function BusServer:Destroy()
	bus:Destroy()
end
return BusServer
