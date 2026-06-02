--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Sensor = require(gameRoot.Shared.Goap.Core.Sensor)
local Utils = require(gameRoot.Shared.Goap.Utils)

local DistanceSensor = {}

local function resolvePosition(valueRaw: any): any?
	local okDirect, directPosition = pcall(function()
		return valueRaw.Position
	end)
	if okDirect and directPosition ~= nil then
		return directPosition
	end
	local okPivot, pivot = pcall(function()
		return valueRaw:GetPivot()
	end)
	if okPivot and pivot ~= nil then
		return pivot.Position
	end
	return nil
end

local function resolveNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return valueRaw
end

function DistanceSensor.new(): any
	return Sensor.new({
		Name = "DistanceSensor",
		Update = function(_, agent)
			local blackboard = agent:GetBlackboard()
			local rootPosition = resolvePosition(blackboard:Get("Root"))
			local targetPosition = resolvePosition(blackboard:Get("Target"))
			local attackRange = math.max(0, resolveNumber(blackboard:Get("AttackRange"), 8))
			if rootPosition == nil or targetPosition == nil then
				Utils.WriteWorldState(agent, "TargetInRange", false)
				return
			end
			local okDistance, distance = pcall(function()
				return (rootPosition - targetPosition).Magnitude
			end)
			local distanceRaw: any = distance
			if not okDistance or typeof(distanceRaw) ~= "number" then
				Utils.WriteWorldState(agent, "TargetInRange", false)
				return
			end
			local distanceValue = distanceRaw :: number
			Utils.WriteWorldState(agent, "TargetDistance", distanceValue)
			Utils.WriteWorldState(agent, "TargetInRange", distanceValue <= attackRange)
		end,
	})
end

DistanceSensor.copy = Table.copy

return DistanceSensor
