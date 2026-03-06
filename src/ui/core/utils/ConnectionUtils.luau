--!strict
local ConnectionUtils = {}

function ConnectionUtils.disconnect(connection: RBXScriptConnection?)
	if connection ~= nil then
		connection:Disconnect()
	end
end

function ConnectionUtils.disconnectMany(connections: { RBXScriptConnection? })
	for _, connection in connections do
		ConnectionUtils.disconnect(connection)
	end
end

function ConnectionUtils.call(disconnectRaw: any)
	if typeof(disconnectRaw) == "function" then
		(disconnectRaw :: () -> ())()
	end
end

return ConnectionUtils
