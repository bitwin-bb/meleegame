
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Sensor = require("Sensor"),
	TargetSensor = require(script:WaitForChild("TargetSensor")),
	HealthSensor = require(script:WaitForChild("HealthSensor")),
	DistanceSensor = require(script:WaitForChild("DistanceSensor")),
})
