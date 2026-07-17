
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Sensor = require("Sensor")

local HealthSensor = {}

local function getNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return valueRaw
end

function HealthSensor.new(): any
	return Sensor.new({
		Name = "HealthSensor",
		Update = function(_, agent)
			local blackboard = agent:GetBlackboard()
			local health = getNumber(blackboard:Get("Health"), 100)
			local maxHealth = math.max(1, getNumber(blackboard:Get("MaxHealth"), health))
			local ratio = math.clamp(getNumber(blackboard:Get("HealthLowRatio"), 0.35), 0, 1)
			agent:SetWorldState("HealthLow", health / maxHealth <= ratio)
		end,
	})
end

HealthSensor.copy = Table.copy

return HealthSensor
