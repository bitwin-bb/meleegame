--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

local StateMachineDebugger = {}

function StateMachineDebugger.Snapshot(machine: any): { [string]: any }
	local activePath = if typeof(machine.GetActivePath) == "function" then machine:GetActivePath() else {}
	return {
		currentState = if typeof(machine.GetCurrentState) == "function" then machine:GetCurrentState() else nil,
		previousState = if typeof(machine.GetPreviousState) == "function" then machine:GetPreviousState() else nil,
		activePath = activePath,
		elapsed = if typeof(machine.GetElapsed) == "function" then machine:GetElapsed() else 0,
		transitionCount = if typeof(machine.GetTransitionCount) == "function" then machine:GetTransitionCount() else 0,
		running = if typeof(machine.IsRunning) == "function" then machine:IsRunning() else false,
	}
end

StateMachineDebugger.snapshot = StateMachineDebugger.Snapshot
StateMachineDebugger.copy = Table.copy

return StateMachineDebugger
