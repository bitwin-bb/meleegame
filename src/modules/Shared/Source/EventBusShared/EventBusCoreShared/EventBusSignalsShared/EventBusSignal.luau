local require = require(script.Parent.loader).load(script)


local Maid = require("Maid")

local Connection = require("Connection")
local Utils = require("EventBusUtilsShared")

type Connection = Connection.Connection

type Listener = {
	connection: Connection,
	callback: (...any) -> (),
	once: boolean,
}

type DispatchItem = {
	listener: Listener,
	once: boolean,
}

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable(
	{} :: {
		_destroyed: boolean,
		_listeners: { Listener },
		_pendingOnceConnections: { Connection },
		_waitingThreads: { thread },
		_maid: any,
	},
	Signal
))

local function reportCallbackError(message: string)
	if Utils.DEBUG_WARN_CALLBACK_ERRORS then
		Utils.Warn("listener error " .. message)
	end
end

function Signal.new(): Signal
	local maid = Maid.new()

	local self = setmetatable({
		_destroyed = false,
		_listeners = {},
		_pendingOnceConnections = {},
		_waitingThreads = {},
		_maid = maid,
	}, Signal)

	maid:GiveTask(function()
		table.clear(self._listeners)
		table.clear(self._pendingOnceConnections)
		table.clear(self._waitingThreads)
	end)

	return self
end

function Signal._disconnectListener(self: Signal, listener: Listener)
	for index = #self._listeners, 1, -1 do
		if self._listeners[index] == listener then
			table.remove(self._listeners, index)
			break
		end
	end
end

function Signal._removePendingOnceConnection(self: Signal, connection: Connection)
	for index = #self._pendingOnceConnections, 1, -1 do
		if self._pendingOnceConnections[index] == connection then
			table.remove(self._pendingOnceConnections, index)
			break
		end
	end
end

function Signal.Connect(self: Signal, callback: (...any) -> ()): Connection
	assert(not self._destroyed, "cannot connect to destroyed signal")
	assert(typeof(callback) == "function", "callback must be a function")

	local listener = nil :: Listener?
	local connection = Connection.new(function()
		local currentListener = listener
		if currentListener ~= nil then
			self:_disconnectListener(currentListener)
		end
	end)

	listener = {
		connection = connection,
		callback = callback,
		once = false,
	}

	table.insert(self._listeners, listener :: Listener)

	return connection
end

function Signal.Once(self: Signal, callback: (...any) -> ()): Connection
	assert(not self._destroyed, "cannot connect to destroyed signal")
	assert(typeof(callback) == "function", "callback must be a function")

	local listener = nil :: Listener?
	local connection = Connection.new(function()
		local currentListener = listener
		if currentListener ~= nil then
			self:_disconnectListener(currentListener)
		end
	end)

	listener = {
		connection = connection,
		callback = callback,
		once = true,
	}

	table.insert(self._listeners, listener :: Listener)

	return connection
end

function Signal.Fire(self: Signal, ...: any)
	if self._destroyed then
		return
	end

	local args = table.pack(...)
	local waitingThreads = self._waitingThreads
	self._waitingThreads = {}

	for _, waitingThread in waitingThreads do
		task.spawn(waitingThread, table.unpack(args, 1, args.n))
	end

	local dispatchItems: { DispatchItem } = {}
	local listeners = table.clone(self._listeners)
	for _, listener in listeners do
		if listener.connection.Connected then
			if listener.once then
				self:_disconnectListener(listener)
				table.insert(self._pendingOnceConnections, listener.connection)
			end

			table.insert(dispatchItems, {
				listener = listener,
				once = listener.once,
			})
		end
	end

	if #dispatchItems == 0 then
		return
	end

	task.spawn(function()
		for _, dispatchItem in dispatchItems do
			local listener = dispatchItem.listener
			if self._destroyed then
				if dispatchItem.once and listener.connection.Connected then
					listener.connection:Disconnect()
				end
				if dispatchItem.once then
					self:_removePendingOnceConnection(listener.connection)
				end
			elseif listener.connection.Connected then
				local ok, result = (pcall :: any)(listener.callback, table.unpack(args, 1, args.n))
				if dispatchItem.once then
					listener.connection:Disconnect()
					self:_removePendingOnceConnection(listener.connection)
				end

				if not ok then
					reportCallbackError(tostring(result))
				end
			elseif dispatchItem.once then
				self:_removePendingOnceConnection(listener.connection)
			end
		end
	end)
end

function Signal.Wait(self: Signal): ...any
	assert(not self._destroyed, "cannot wait on destroyed signal")

	local waitingThread = coroutine.running()
	table.insert(self._waitingThreads, waitingThread)

	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, listener in table.clone(self._listeners) do
		listener.connection:Disconnect()
	end

	for _, connection in table.clone(self._pendingOnceConnections) do
		connection:Disconnect()
	end

	table.clear(self._listeners)
	table.clear(self._pendingOnceConnections)
end

function Signal.Destroy(self: Signal)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:DisconnectAll()

	local waitingThreads = self._waitingThreads
	self._waitingThreads = {}

	for _, waitingThread in waitingThreads do
		task.spawn(waitingThread)
	end

	self._maid:DoCleaning()
end

function Signal.GetConnectionCount(self: Signal): number
	local count = 0
	for _, listener in self._listeners do
		if listener.connection.Connected then
			count += 1
		end
	end

	return count
end
return Signal
