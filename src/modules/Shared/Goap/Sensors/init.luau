--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Sensor = require(gameRoot.Shared.Goap.Core.Sensor),
	TargetSensor = require(gameRoot.Shared.Goap.Sensors.TargetSensor),
	HealthSensor = require(gameRoot.Shared.Goap.Sensors.HealthSensor),
	DistanceSensor = require(gameRoot.Shared.Goap.Sensors.DistanceSensor),
})
