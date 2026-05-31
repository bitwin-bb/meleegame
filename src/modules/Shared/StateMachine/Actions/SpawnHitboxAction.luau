--!strict

local Utils = require(script:FindFirstAncestor("StateMachine").Utils)

local SpawnHitboxAction = {}

function SpawnHitboxAction.Perform(machine: any, hitboxConfigRaw: any?)
	local hitbox = Utils.Read(machine, "Hitbox", Utils.Read(machine, "Combat", nil))
	Utils.CallFirst(hitbox, { "SpawnHitbox", "spawnHitbox" }, hitboxConfigRaw)
end

function SpawnHitboxAction.new(hitboxConfigRaw: any?): (any) -> ()
	return function(machine: any)
		SpawnHitboxAction.Perform(machine, hitboxConfigRaw)
	end
end

return SpawnHitboxAction
