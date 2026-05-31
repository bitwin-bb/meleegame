--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Sensor = require(script:FindFirstAncestor("Goap").Core.Sensor)

local HealthSensor = {}

local function resolveNumber(valueRaw: any, fallback: number): number
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
			local health = resolveNumber(blackboard:Get("Health"), 100)
			local maxHealth = math.max(1, resolveNumber(blackboard:Get("MaxHealth"), health))
			local ratio = math.clamp(resolveNumber(blackboard:Get("HealthLowRatio"), 0.35), 0, 1)
			agent:SetWorldState("HealthLow", health / maxHealth <= ratio)
		end,
	})
end

HealthSensor.copy = Table.copy

return HealthSensor
