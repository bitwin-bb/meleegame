local require = require(script.Parent.loader).load(script)

local ConnectionUtils = {}

function ConnectionUtils.Disconnect(connection: RBXScriptConnection?)
	if connection ~= nil then
		connection:Disconnect()
	end
end

function ConnectionUtils.DisconnectMany(connections: { RBXScriptConnection? })
	for _, connection in connections do
		ConnectionUtils.Disconnect(connection)
	end
end

function ConnectionUtils.Call(disconnectRaw: any)
	if typeof(disconnectRaw) == "function" then
		(disconnectRaw :: () -> ())()
	end
end
return ConnectionUtils
