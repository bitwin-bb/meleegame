--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = require(gameRoot.Shared.StateMachine.Utils)

local HealthBelowGuard = {}

function HealthBelowGuard.Evaluate(machine: any, thresholdRaw: any?, keyRaw: any?): boolean
	local key = if typeof(keyRaw) == "string" and keyRaw ~= "" then keyRaw else "Health"
	local threshold = if typeof(thresholdRaw) == "number" then thresholdRaw else 0
	local health = Utils.Read(machine, key, nil)
	return typeof(health) == "number" and health <= threshold
end

function HealthBelowGuard.new(thresholdRaw: any?, keyRaw: any?): (any) -> boolean
	return function(machine: any): boolean
		return HealthBelowGuard.Evaluate(machine, thresholdRaw, keyRaw)
	end
end

return HealthBelowGuard
