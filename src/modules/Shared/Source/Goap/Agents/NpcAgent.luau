
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Actions = require("GoapActions")
local Agent = require("Agent")
local Goals = require("Goals")
local Sensors = require("Sensors")

local NPCAgent = {}

function NPCAgent.new(configRaw: any?): any
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local agent = Agent.new(config)

	agent:AddSensor(Sensors.TargetSensor.new())
	agent:AddSensor(Sensors.HealthSensor.new())
	agent:AddSensor(Sensors.DistanceSensor.new())

	agent:AddGoal(Goals.SurviveGoal.new())
	agent:AddGoal(Goals.HealSelfGoal.new())
	agent:AddGoal(Goals.KillTargetGoal.new())
	agent:AddGoal(Goals.RetreatGoal.new())
	agent:AddGoal(Goals.PatrolGoal.new())
	agent:AddGoal(Goals.InvestigateGoal.new())

	agent:AddAction(Actions.FindTargetAction.new())
	agent:AddAction(Actions.MoveToTargetAction.new())
	agent:AddAction(Actions.AttackTargetAction.new())
	agent:AddAction(Actions.FleeAction.new())
	agent:AddAction(Actions.PatrolAction.new())
	agent:AddAction(Actions.HealSelfAction.new())
	agent:AddAction(Actions.UseAbilityAction.new())

	return agent
end

NPCAgent.copy = Table.copy

return NPCAgent
