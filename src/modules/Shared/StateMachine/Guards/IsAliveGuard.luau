--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = require(gameRoot.Shared.StateMachine.Utils)

local IsAliveGuard = {}

function IsAliveGuard.Evaluate(machine: any): boolean
	local health = Utils.Read(machine, "Health", nil)
	if typeof(health) == "number" then
		return health > 0
	end

	local humanoid = Utils.Read(machine, "Humanoid", nil)
	if typeof(humanoid) == "Instance" and humanoid:IsA("Humanoid") then
		return humanoid.Health > 0
	end
	return true
end

function IsAliveGuard.new(): (any) -> boolean
	return function(machine: any): boolean
		return IsAliveGuard.Evaluate(machine)
	end
end

return IsAliveGuard
