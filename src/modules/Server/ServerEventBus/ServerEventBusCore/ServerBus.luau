
local require = require(script.Parent.loader).load(script)

local ServerEventRegistry = require("ServerEventRegistry")
local SharedEventBus = require("SharedEventBus")

local bus = SharedEventBus.Core.EventBus.new("ServerEventBus")

local ServerBus = {}

function ServerBus:On(eventName: string, callback: (...any) -> ())
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:On(eventName, callback)
end

function ServerBus:Once(eventName: string, callback: (...any) -> ())
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Once(eventName, callback)
end

function ServerBus:Fire(eventName: string, ...: any)
	if not ServerEventRegistry.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function ServerBus:Wait(eventName: string): ...any
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Wait(eventName)
end

function ServerBus:Observe(eventName: string)
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Observe(eventName)
end

function ServerBus:GetRxSignal(eventName: string)
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:GetRxSignal(eventName)
end

function ServerBus:Off(eventName: string)
	if not ServerEventRegistry.Assert(eventName) then
		return
	end

	bus:Off(eventName)
end

function ServerBus:Has(eventName: string): boolean
	if not ServerEventRegistry.Assert(eventName) then
		return false
	end

	return bus:Has(eventName)
end

function ServerBus:GetSignal(eventName: string)
	if not ServerEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:GetSignal(eventName)
end

function ServerBus:GetEventNames(): { string }
	return bus:GetEventNames()
end

function ServerBus:Clear(eventName: string?)
	if eventName ~= nil and not ServerEventRegistry.Assert(eventName) then
		return
	end

	bus:Clear(eventName)
end

function ServerBus:Destroy()
	bus:Destroy()
end

ServerBus.on = ServerBus.On
ServerBus.once = ServerBus.Once
ServerBus.fire = ServerBus.Fire
ServerBus.wait = ServerBus.Wait
ServerBus.observe = ServerBus.Observe
ServerBus.getRxSignal = ServerBus.GetRxSignal
ServerBus.off = ServerBus.Off
ServerBus.has = ServerBus.Has
ServerBus.getSignal = ServerBus.GetSignal
ServerBus.getEventNames = ServerBus.GetEventNames
ServerBus.clear = ServerBus.Clear
ServerBus.destroy = ServerBus.Destroy

return ServerBus
