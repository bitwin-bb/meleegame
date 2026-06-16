
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Debug")
local Table = packages.Table

local GoalDebugger = require("GoalDebugger")
local PlanPrinter = require("PlanPrinter")
local WorldStateViewer = require("WorldStateViewer")

local GoapDebugger = {}

function GoapDebugger.DescribeAgent(agent: any): string
	if typeof(agent) ~= "table" then
		return "Agent(nil)"
	end
	local goal = if typeof(agent.GetCurrentGoal) == "function" then agent:GetCurrentGoal() else nil
	local plan = if typeof(agent.GetCurrentPlan) == "function" then agent:GetCurrentPlan() else nil
	local worldState = if typeof(agent.GetWorldStateObject) == "function" then agent:GetWorldStateObject() else nil
	local goalText = if goal ~= nil then GoalDebugger.DescribeGoal(goal) else "Goal(nil)"
	local planText = if plan ~= nil then PlanPrinter.ToString(plan) else "Plan(nil)"
	local worldText = WorldStateViewer.ToString(worldState)
	return table.concat({
		"Agent",
		goalText,
		planText,
		worldText,
	}, "\n")
end

function GoapDebugger.PrintAgent(agent: any)
	print(GoapDebugger.DescribeAgent(agent))
end

GoapDebugger.copy = Table.copy
GoapDebugger.describeAgent = GoapDebugger.DescribeAgent
GoapDebugger.printAgent = GoapDebugger.PrintAgent

return GoapDebugger
