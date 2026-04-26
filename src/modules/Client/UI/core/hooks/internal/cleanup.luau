--!strict
local Cleanup = {}

function Cleanup.Disconnect(connectionRaw: any)
	if connectionRaw == nil then
		return
	end

	if typeof(connectionRaw) == "RBXScriptConnection" then
		connectionRaw:Disconnect()
		return
	end

	if typeof(connectionRaw) ~= "table" then
		return
	end

	local disconnect = (connectionRaw :: any).Disconnect
	if typeof(disconnect) ~= "function" then
		disconnect = (connectionRaw :: any).disconnect
	end
	if typeof(disconnect) == "function" then
		disconnect(connectionRaw)
	end
end

function Cleanup.CancelTask(threadRaw: any)
	if threadRaw == nil or typeof(threadRaw) ~= "thread" then
		return
	end

	pcall(task.cancel, threadRaw :: thread)
end

function Cleanup.Call(cleanupRaw: any)
	if cleanupRaw == nil then
		return
	end

	if typeof(cleanupRaw) == "function" then
		cleanupRaw()
		return
	end

	Cleanup.Disconnect(cleanupRaw)
end

Cleanup.disconnect = Cleanup.Disconnect
Cleanup.cancelTask = Cleanup.CancelTask
Cleanup.call = Cleanup.Call

return Cleanup
