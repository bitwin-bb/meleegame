--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing game root")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Maid = loader("Maid")

local Connection = {}
Connection.__index = Connection

export type DisconnectCallback = () -> ()

export type Connection = typeof(setmetatable({} :: {
	Connected: boolean,
	_disconnectMaid: any,
}, Connection))

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
