--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Debug")
local Table = packages.Table

local PlanPrinter = require(script.Parent.PlanPrinter)
local Utils = require(script:FindFirstAncestor("Goap").Utils)
local WorldStateViewer = require(script.Parent.WorldStateViewer)

local GoalDebugger = {}

function GoalDebugger.DescribeGoal(goal: any): string
	if typeof(goal) ~= "table" then
		return "Goal(nil)"
	end
	local desiredState = if typeof(goal.GetDesiredState) == "function"
		then goal:GetDesiredState()
		else goal.DesiredState
	return string.format(
		"Goal(%s, priority=%s)\n%s",
		Utils.GetName(goal, "Goal"),
		tostring(goal.Priority or 0),
		WorldStateViewer.ToString(desiredState)
	)
end

function GoalDebugger.DescribePlanForGoal(goal: any, plan: any): string
	return GoalDebugger.DescribeGoal(goal) .. "\n" .. PlanPrinter.ToString(plan)
end

GoalDebugger.copy = Table.copy
GoalDebugger.describeGoal = GoalDebugger.DescribeGoal
GoalDebugger.describePlanForGoal = GoalDebugger.DescribePlanForGoal

return GoalDebugger
