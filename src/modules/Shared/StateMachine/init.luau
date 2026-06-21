
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Nevermore = require(script:WaitForChild("StateMachineNevermore"))
local Table = Nevermore.Get("Table")

local exports = Table.copy({
	Nevermore = Nevermore,
	Utils = require(script:WaitForChild("StateMachineUtils")),

	Core = require(script:WaitForChild("StateMachineCore")),
	Guards = require(script:WaitForChild("Guards")),
	Actions = require(script:WaitForChild("StateMachineActions")),
	Adapters = require(script:WaitForChild("Adapters")),
	Runtime = require(script:WaitForChild("StateMachineRuntime")),
	Machines = require(script:WaitForChild("Machines")),
	Debug = require(script:WaitForChild("StateMachineDebug")),
})

if RunService:IsClient() then
	exports.Client = require("StateMachineClient")
end

if RunService:IsServer() then
	exports.Server = require("StateMachineServer")
end

return exports
