--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

local StateGraphPrinter = {}

function StateGraphPrinter.Print(machine: any): string
	local lines = {}
	local states = if typeof(machine) == "table" then machine.states else nil
	if typeof(states) ~= "table" then
		return ""
	end

	for stateId, state in states do
		table.insert(lines, tostring(stateId))
		local transitions = if typeof(state) == "table" then state.transitions else nil
		if typeof(transitions) == "table" then
			for _, transition in transitions do
				table.insert(lines, string.format("%s -> %s", tostring(stateId), tostring(transition.to)))
			end
		end
	end

	table.sort(lines)
	return table.concat(lines, "\n")
end

StateGraphPrinter.print = StateGraphPrinter.Print
StateGraphPrinter.copy = Table.copy

return StateGraphPrinter
