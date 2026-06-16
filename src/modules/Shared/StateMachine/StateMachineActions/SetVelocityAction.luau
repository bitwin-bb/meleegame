
local require = require(script.Parent.loader).load(script)

local Utils = require("StateMachineUtils")

local SetVelocityAction = {}

function SetVelocityAction.Perform(machine: any, velocityRaw: any?)
	local velocity = if typeof(velocityRaw) == "Vector3"
		then velocityRaw
		else Utils.Read(machine, "Velocity", Vector3.zero)
	if typeof(velocity) ~= "Vector3" then
		return
	end

	local movement = Utils.Read(machine, "Movement", nil)
	if Utils.CallFirst(movement, { "SetVelocity", "setVelocity" }, velocity) ~= nil then
		return
	end

	local root = Utils.Read(machine, "Root", nil)
	if typeof(root) == "Instance" and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = velocity
	end
end

function SetVelocityAction.new(velocityRaw: any?): (any) -> ()
	return function(machine: any)
		SetVelocityAction.Perform(machine, velocityRaw)
	end
end

return SetVelocityAction
