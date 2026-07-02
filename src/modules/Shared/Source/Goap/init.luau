
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Nevermore = require(script:WaitForChild("GoapNevermore"))
local Table = Nevermore.GetRolePackages("Exports").Table

local exports = Table.copy({
	Nevermore = Nevermore,
	Utils = require(script:WaitForChild("GoapUtils")),

	Core = require(script:WaitForChild("GoapCore")),
	Actions = require(script:WaitForChild("GoapActions")),
	Goals = require(script:WaitForChild("Goals")),
	Sensors = require(script:WaitForChild("Sensors")),
	Scorers = require(script:WaitForChild("Scorers")),
	Executors = require(script:WaitForChild("Executors")),
	Agents = require(script:WaitForChild("Agents")),
	Integrations = require(script:WaitForChild("Integrations")),
	Debug = require(script:WaitForChild("GoapDebug")),
})

if RunService:IsClient() then
	exports.Client = require("GoapClient")
end

if RunService:IsServer() then
	exports.Server = require("GoapServer")
end

return exports
