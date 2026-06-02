--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Sensor = require(gameRoot.Shared.Goap.Core.Sensor)

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
