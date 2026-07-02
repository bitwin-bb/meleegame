local require = require(script.Parent.loader).load(script)

local MaidTaskUtils = require("MaidTaskUtils")

local ConnectionUtils = {}

local function doTask(task: any?)
	if task == nil or not MaidTaskUtils.isValidTask(task) then
		return
	end

	MaidTaskUtils.doTask(task)
end

function ConnectionUtils.Disconnect(connection: RBXScriptConnection?)
	doTask(connection)
end

function ConnectionUtils.DisconnectMany(connections: { RBXScriptConnection? })
	for _, connection in connections do
		doTask(connection)
	end
end

function ConnectionUtils.Call(disconnectRaw: any)
	doTask(disconnectRaw)
end
return ConnectionUtils
