
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Sensor = require("Sensor")

local TargetSensor = {}

function TargetSensor.new(): any
	return Sensor.new({
		Name = "TargetSensor",
		Update = function(_, agent)
			local target = agent:GetBlackboard():Get("Target")
			agent:SetWorldState("HasTarget", target ~= nil)
		end,
	})
end

TargetSensor.copy = Table.copy

return TargetSensor
