
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require("GoapUtils")

local StateMachineAdapter = {}

function StateMachineAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "StateMachine", Utils.ReadBlackboard(agent, "StateMachineAdapter", nil))
end

function StateMachineAdapter.ChangeState(agent: any, stateNameRaw: any): boolean
	local stateName = if typeof(stateNameRaw) == "string" and stateNameRaw ~= "" then stateNameRaw else nil
	if stateName == nil then
		return false
	end
	local stateMachine = StateMachineAdapter.Get(agent)
	local ok =
		Utils.CallFirst(stateMachine, { "ChangeState", "changeState", "TransitionTo", "transitionTo" }, stateName)
	return ok
end

StateMachineAdapter.copy = Table.copy
return StateMachineAdapter
