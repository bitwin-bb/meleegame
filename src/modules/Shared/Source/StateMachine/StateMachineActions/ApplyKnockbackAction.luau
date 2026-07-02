
local require = require(script.Parent.loader).load(script)

local Utils = require("StateMachineUtils")

local ApplyKnockbackAction = {}

function ApplyKnockbackAction.Perform(machine: any, impulseRaw: any?)
	local impulse = if typeof(impulseRaw) == "Vector3"
		then impulseRaw
		else Utils.Read(machine, "Knockback", Vector3.zero)
	if typeof(impulse) ~= "Vector3" then
		return
	end

	local movement = Utils.Read(machine, "Movement", nil)
	if
		Utils.CallFirst(movement, { "ApplyImpulse", "applyImpulse", "ApplyKnockback", "applyKnockback" }, impulse)
		~= nil
	then
		return
	end

	local root = Utils.Read(machine, "Root", nil)
	if typeof(root) == "Instance" and root:IsA("BasePart") then
		root:ApplyImpulse(impulse)
	end
end

function ApplyKnockbackAction.new(impulseRaw: any?): (any) -> ()
	return function(machine: any)
		ApplyKnockbackAction.Perform(machine, impulseRaw)
	end
end

return ApplyKnockbackAction
