--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Sensor = require(script:FindFirstAncestor("Goap").Core.Sensor),
	TargetSensor = require(script.TargetSensor),
	HealthSensor = require(script.HealthSensor),
	DistanceSensor = require(script.DistanceSensor),
})
