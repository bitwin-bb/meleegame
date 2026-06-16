local require = require(script.Parent.loader).load(script)


local Maid = require("Maid")

local Connection = {}
Connection.__index = Connection

export type DisconnectCallback = () -> ()

export type Connection = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		_disconnectMaid: any,
	},
	Connection
))

function Connection.new(disconnect: DisconnectCallback): Connection
	local maid = Maid.new()
	maid:GiveTask(disconnect)

	return setmetatable({
		Connected = true,
		_disconnectMaid = maid,
	}, Connection)
end

function Connection.Disconnect(self: Connection)
	if not self.Connected then
		return
	end

	self.Connected = false
	self._disconnectMaid:DoCleaning()
end

Connection.disconnect = Connection.Disconnect
Connection.Destroy = Connection.Disconnect
Connection.destroy = Connection.Disconnect

return Connection
