--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Debug")
local Table = packages.Table

local Utils = require(gameRoot.Shared.Goap.Utils)

local PlanPrinter = {}

function PlanPrinter.ToLines(plan: any): { string }
	if typeof(plan) ~= "table" then
		return { "Plan(nil)" }
	end
	local actions = if typeof(plan.GetActions) == "function" then plan:GetActions() else {}
	local lines = {
		string.format("Plan(cost=%s, actions=%d)", tostring(plan.GetCost and plan:GetCost() or 0), #actions),
	}
	for index, action in actions do
		lines[#lines + 1] = string.format("%d. %s", index, Utils.GetName(action, "Action"))
	end
	return lines
end

function PlanPrinter.ToString(plan: any): string
	return table.concat(PlanPrinter.ToLines(plan), "\n")
end

PlanPrinter.copy = Table.copy
PlanPrinter.toLines = PlanPrinter.ToLines
PlanPrinter.toString = PlanPrinter.ToString

return PlanPrinter
