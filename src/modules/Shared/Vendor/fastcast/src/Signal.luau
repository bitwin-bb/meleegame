--!strict

-- A new implementation of RBXScriptSignal that uses proper Lua OOP.
-- This was explicitly made to transport other OOP objects.
-- I would be using BindableEvents, but they don't like cyclic tables (part of OOP objects with __index)

--// Services
local TestService = game:GetService("TestService")

--// Modules
local table = require(script.Parent.Parent.Table)

--// Types
type ConnectionStaticData = {
	Signal: SignalStatic?,
	Delegate: (...any) -> (),
	Index: number,
}
type SignalStaticData = {
	Name: string,
	Connections: { ConnectionStatic },
	YieldingThreads: { thread },
}

--// Connection Static Setup
local ConnectionStatic = {}
ConnectionStatic.__index = ConnectionStatic
ConnectionStatic.__type = "SignalConnection" -- For compatibility with TypeMarshaller
export type ConnectionStatic = typeof(setmetatable({} :: ConnectionStaticData, ConnectionStatic))

function ConnectionStatic.new(sig: SignalStatic, func: (...any) -> ())
	local self = setmetatable({}, ConnectionStatic) :: ConnectionStatic

	self.Signal = sig
	self.Delegate = func
	self.Index = -1

	return self
end

function ConnectionStatic.Disconnect(self: ConnectionStatic)
	if self.Signal then
		table.remove(self.Signal.Connections, self.Index)
		self.Signal = nil
	end

	self.Index = -1
end

--// Signal Static Setup
local SignalStatic = {}
SignalStatic.__index = SignalStatic
SignalStatic.__type = "Signal" -- For compatibility with TypeMarshaller
export type SignalStatic = typeof(setmetatable({} :: SignalStaticData, SignalStatic))

function SignalStatic.new(signalName: string)
	local self = setmetatable({}, SignalStatic) :: SignalStatic

	self.Name = signalName
	self.Connections = {}
	self.YieldingThreads = {}

	return self
end

function SignalStatic.Connect(self: SignalStatic, func: (...any) -> ()): ConnectionStatic
	local Connection = ConnectionStatic.new(self, func)
	table.insert(self.Connections, Connection)
	Connection.Index = #self.Connections

	return Connection
end

local function ThreadAndReportError(delegate: any, args: { [any]: any }, handlerName: string)
	local thread = coroutine.create(function()
		delegate(unpack(args))
	end)
	local success, msg = coroutine.resume(thread)
	if not success then
		-- For the love of god roblox PLEASE add the ability to customize message type in output statements.
		-- This "testservice" garbage at the start of my message is annoying as all hell.
		TestService:Error(string.format("Exception thrown in your %s event handler: %s", handlerName, msg))
		TestService:Checkpoint(debug.traceback(thread))
	end
end

function SignalStatic.Fire(self: SignalStatic, ...)
	local args = table.pack(...)

	-- Loop through each connection
	for _, connection in self.Connections do
		if connection.Delegate then
			local name = connection.Signal and connection.Signal.Name or "NO HANDLER"

			-- Catch case for disposed signals.
			ThreadAndReportError(connection.Delegate, args, name)
		end
	end

	-- Loop through each thread
	for _, thread in self.YieldingThreads do
		coroutine.resume(thread, ...)
	end
end

function SignalStatic.FireSync(self: SignalStatic, ...)
	local args = table.pack(...)

	for _, connection in self.Connections do
		if connection.Delegate then
			-- Catch case for disposed signals.
			connection.Delegate(unpack(args))
		end
	end

	for _, thread in self.YieldingThreads do
		coroutine.resume(thread, ...)
	end
end

function SignalStatic.Wait(self: SignalStatic): ...any
	local args: { any }
	local thread = coroutine.running()

	table.insert(self.YieldingThreads, thread)
	args = { coroutine.yield() }
	table.removeObject(self.YieldingThreads, thread)

	return unpack(args)
end

function SignalStatic.Dispose(self: SignalStatic): ...any
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

function SignalStatic.Disconnect(self: SignalStatic): ...any
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return SignalStatic.new
