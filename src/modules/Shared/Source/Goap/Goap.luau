
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

local exports = Table.copy({
	Nevermore = Nevermore,
	Utils = require("GoapUtils"),

	Core = require("GoapCore"),
	Actions = require("GoapActions"),
	Goals = require("Goals"),
	Sensors = require("Sensors"),
	Scorers = require("Scorers"),
	Executors = require("Executors"),
	Agents = require("Agents"),
	Integrations = require("Integrations"),
	Debug = require("GoapDebug"),
})

if RunService:IsClient() then
	exports.Client = require("GoapClient")
end

if RunService:IsServer() then
	exports.Server = require("GoapServer")
end

return exports
