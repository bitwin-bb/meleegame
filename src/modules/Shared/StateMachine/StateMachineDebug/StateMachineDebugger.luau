
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
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
StateMachineDebugger.copy = Table.copy

return StateMachineDebugger
