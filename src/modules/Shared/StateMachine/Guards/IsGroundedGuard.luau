--!strict

local Utils = require(script:FindFirstAncestor("StateMachine").Utils)

local IsGroundedGuard = {}

function IsGroundedGuard.Evaluate(machine: any): boolean
	local grounded = Utils.Read(machine, "IsGrounded", nil)
	if typeof(grounded) == "boolean" then
		return grounded
	end

	local movement = Utils.Read(machine, "Movement", nil)
	local result = Utils.CallFirst(movement, { "IsGrounded", "isGrounded" })
	return result == true
end

function IsGroundedGuard.new(): (any) -> boolean
	return function(machine: any): boolean
		return IsGroundedGuard.Evaluate(machine)
	end
end

return IsGroundedGuard
