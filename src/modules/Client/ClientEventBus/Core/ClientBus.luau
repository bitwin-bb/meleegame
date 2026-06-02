--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing game root")

local ClientEventRegistry = require(gameRoot.Client.ClientEventBus.Core.ClientEventRegistry)
local SharedEventBus = require(gameRoot.Shared.SharedEventBus)

local bus = SharedEventBus.Core.EventBus.new("ClientEventBus")

local ClientBus = {}

function ClientBus:On(eventName: string, callback: (...any) -> ())
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:On(eventName, callback)
end

function ClientBus:Once(eventName: string, callback: (...any) -> ())
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Once(eventName, callback)
end

function ClientBus:Fire(eventName: string, ...: any)
	if not ClientEventRegistry.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function ClientBus:Wait(eventName: string): ...any
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Wait(eventName)
end

function ClientBus:Observe(eventName: string)
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:Observe(eventName)
end

function ClientBus:GetRxSignal(eventName: string)
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:GetRxSignal(eventName)
end

function ClientBus:Off(eventName: string)
	if not ClientEventRegistry.Assert(eventName) then
		return
	end

	bus:Off(eventName)
end

function ClientBus:Has(eventName: string): boolean
	if not ClientEventRegistry.Assert(eventName) then
		return false
	end

	return bus:Has(eventName)
end

function ClientBus:GetSignal(eventName: string)
	if not ClientEventRegistry.Assert(eventName) then
		return nil
	end

	return bus:GetSignal(eventName)
end

function ClientBus:GetEventNames(): { string }
	return bus:GetEventNames()
end

function ClientBus:Clear(eventName: string?)
	if eventName ~= nil and not ClientEventRegistry.Assert(eventName) then
		return
	end

	bus:Clear(eventName)
end

function ClientBus:Destroy()
	bus:Destroy()
end

ClientBus.on = ClientBus.On
ClientBus.once = ClientBus.Once
ClientBus.fire = ClientBus.Fire
ClientBus.wait = ClientBus.Wait
ClientBus.observe = ClientBus.Observe
ClientBus.getRxSignal = ClientBus.GetRxSignal
ClientBus.off = ClientBus.Off
ClientBus.has = ClientBus.Has
ClientBus.getSignal = ClientBus.GetSignal
ClientBus.getEventNames = ClientBus.GetEventNames
ClientBus.clear = ClientBus.Clear
ClientBus.destroy = ClientBus.Destroy

return ClientBus
