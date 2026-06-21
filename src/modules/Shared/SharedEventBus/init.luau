
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local exports = {
	Utils = require(script:WaitForChild("SharedEventBusUtils")),
	Core = require(script:WaitForChild("SharedEventBusCore")),
}

if RunService:IsClient() then
	exports.Client = require("SharedEventBusClient")
end

if RunService:IsServer() then
	exports.Server = require("SharedEventBusServer")
end

return exports
