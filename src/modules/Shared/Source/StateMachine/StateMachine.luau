
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local exports = Table.copy({
	Nevermore = Nevermore,
	Utils = require("StateMachineUtils"),

	Core = require("StateMachineCore"),
	Guards = require("Guards"),
	Actions = require("StateMachineActions"),
	Adapters = require("Adapters"),
	Runtime = require("StateMachineRuntime"),
	Machines = require("Machines"),
	Debug = require("StateMachineDebug"),
})

if RunService:IsClient() then
	exports.Client = require("StateMachineClient")
end

if RunService:IsServer() then
	exports.Server = require("StateMachineServer")
end

return exports
