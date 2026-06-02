--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Utils = require(gameRoot.Shared.StateMachine.Utils)

local FireRemoteAction = {}

function FireRemoteAction.Perform(machine: any, methodRaw: any?, payloadRaw: any?)
	local methodName = if typeof(methodRaw) == "string" and methodRaw ~= "" then methodRaw else nil
	if methodName == nil then
		return
	end

	local network = Utils.Read(machine, "Network", Utils.Read(machine, "Remote", nil))
	Utils.CallFirst(network, { "Fire", "fire" }, methodName, payloadRaw)
end

function FireRemoteAction.new(methodRaw: any?, payloadRaw: any?): (any) -> ()
	return function(machine: any)
		FireRemoteAction.Perform(machine, methodRaw, payloadRaw)
	end
end

return FireRemoteAction
