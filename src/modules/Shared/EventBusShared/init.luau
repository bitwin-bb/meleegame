
local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local exports = {
	Utils = require(script:WaitForChild("EventBusUtilsShared")),
	Core = require(script:WaitForChild("EventBusCoreShared")),
}

if RunService:IsClient() then
	exports.Client = require("EventBusSharedClient")
end

if RunService:IsServer() then
	exports.Server = require("EventBusSharedServer")
end

return exports
