--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = require(gameRoot.Shared.StateMachine.Utils)

local HasTargetGuard = {}

function HasTargetGuard.Evaluate(machine: any, keyRaw: any?): boolean
	local key = if typeof(keyRaw) == "string" and keyRaw ~= "" then keyRaw else "Target"
	return Utils.Read(machine, key, nil) ~= nil
end

function HasTargetGuard.new(keyRaw: any?): (any) -> boolean
	return function(machine: any): boolean
		return HasTargetGuard.Evaluate(machine, keyRaw)
	end
end

return HasTargetGuard
