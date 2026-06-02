--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Runtime")
local Maid = packages.Maid
local Table = packages.Table

local Blackboard = require(gameRoot.Shared.Goap.Core.Blackboard)
local GoalScorer = require(gameRoot.Shared.Goap.Scorers.GoalScorer)
local HealthScorer = require(gameRoot.Shared.Goap.Scorers.HealthScorer)
local PlanExecutor = require(gameRoot.Shared.Goap.Executors.PlanExecutor)
local PlanValidator = require(gameRoot.Shared.Goap.Executors.PlanValidator)
local Planner = require(gameRoot.Shared.Goap.Core.Planner)
local PriorityScorer = require(gameRoot.Shared.Goap.Scorers.PriorityScorer)
local ThreatScorer = require(gameRoot.Shared.Goap.Scorers.ThreatScorer)
local WorldState = require(gameRoot.Shared.Goap.Core.WorldState)

local Agent = {}
Agent.__index = Agent

export type Agent = typeof(setmetatable(
	{} :: {
		WorldState: any,
		Blackboard: any,
		Goals: { any },
		Actions: { any },
		Sensors: { any },
		Planner: any,
		GoalScorer: any,
		PlanExecutor: any,
		PlanValidator: any,
		CurrentGoal: any?,
		CurrentPlan: any?,
		CurrentAction: any?,
		maid: any,
		needsReplan: boolean,
		destroyed: boolean,
	},
	Agent
))

local function callUpdate(sensor: any, agent: any, dt: number)
	if typeof(sensor) ~= "table" then
		return
	end
	local update = sensor.Update or sensor.updateSensor or sensor.update
	if typeof(update) == "function" then
		pcall(update, sensor, agent, dt)
	end
end

local function callCanRun(goal: any, agent: any): boolean
	if typeof(goal) ~= "table" then
		return false
	end
	local canRun = goal.CanRun or goal.canRunGoal or goal.canRun
	if typeof(canRun) ~= "function" then
		return true
	end
	local ok, result = pcall(canRun, goal, agent)
	return ok and result == true
end

function Agent.new(configRaw: any?): Agent
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local worldState = if typeof(config.WorldState) == "table" then config.WorldState else WorldState.new()
	local blackboard = if typeof(config.Blackboard) == "table" then config.Blackboard else Blackboard.new()
	local self = setmetatable({
		WorldState = worldState,
		Blackboard = blackboard,
		Goals = {},
		Actions = {},
		Sensors = {},
		Planner = if typeof(config.Planner) == "table" then config.Planner else Planner.new(),
		GoalScorer = if typeof(config.GoalScorer) == "table"
			then config.GoalScorer
			else GoalScorer.new({
				PriorityScorer.new(),
				HealthScorer.new(),
				ThreatScorer.new(),
			}),
		PlanExecutor = if typeof(config.PlanExecutor) == "table" then config.PlanExecutor else PlanExecutor.new(),
		PlanValidator = if typeof(config.PlanValidator) == "table" then config.PlanValidator else PlanValidator.new(),
		CurrentGoal = nil,
		CurrentPlan = nil,
		CurrentAction = nil,
		maid = Maid.new(),
		needsReplan = true,
		destroyed = false,
	}, Agent)

	self.maid:GiveTask(self.WorldState)
	self.maid:GiveTask(self.Blackboard)
	self.maid:GiveTask(self.Planner)
	self.maid:GiveTask(self.GoalScorer)
	self.maid:GiveTask(self.PlanExecutor)
	self.maid:GiveTask(self.PlanValidator)
	self.maid:GiveTask(self.WorldState:GetChangedSignal():Connect(function()
		self.needsReplan = true
	end))

	return self
end

function Agent.AddGoal(self: Agent, goal: any): any
	if self.destroyed or typeof(goal) ~= "table" then
		return goal
	end
	self.Goals[#self.Goals + 1] = goal
	self.maid:GiveTask(goal)
	self.needsReplan = true
	return goal
end

function Agent.AddAction(self: Agent, action: any): any
	if self.destroyed or typeof(action) ~= "table" then
		return action
	end
	self.Actions[#self.Actions + 1] = action
	self.maid:GiveTask(action)
	self.needsReplan = true
	return action
end

function Agent.AddSensor(self: Agent, sensor: any): any
	if self.destroyed or typeof(sensor) ~= "table" then
		return sensor
	end
	self.Sensors[#self.Sensors + 1] = sensor
	self.maid:GiveTask(sensor)
	return sensor
end

function Agent.UpdateSensors(self: Agent, dt: number)
	for _, sensor in self.Sensors do
		callUpdate(sensor, self, dt)
	end
end

function Agent.SelectBestGoal(self: Agent): any?
	local bestGoal = nil
	local bestScore = -math.huge
	for _, goal in self.Goals do
		if not callCanRun(goal, self) then
			continue
		end
		local score = self.GoalScorer:GetScore(goal, self)
		if score > bestScore then
			bestGoal = goal
			bestScore = score
		end
	end
	return bestGoal
end

function Agent.Replan(self: Agent): any?
	if self.destroyed then
		return nil
	end
	local selectedGoal = self:SelectBestGoal()
	if selectedGoal == nil then
		if self.CurrentPlan ~= nil then
			self.CurrentPlan:Destroy()
		end
		self.CurrentGoal = nil
		self.CurrentPlan = nil
		self.CurrentAction = nil
		self.needsReplan = false
		return nil
	end

	local plan = self.Planner:BuildPlan(self, self.WorldState, selectedGoal, self.Actions)
	if self.CurrentPlan ~= nil then
		self.CurrentPlan:Destroy()
	end
	self.CurrentGoal = selectedGoal
	self.CurrentPlan = plan
	self.CurrentAction = if plan ~= nil then plan:GetCurrentAction() else nil
	self.needsReplan = false
	return plan
end

function Agent.Update(self: Agent, dtRaw: any)
	if self.destroyed then
		return
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	self:UpdateSensors(dt)

	local selectedGoal = self:SelectBestGoal()
	if selectedGoal ~= self.CurrentGoal then
		self.needsReplan = true
	end
	if self.needsReplan or self.CurrentPlan == nil or not self.PlanValidator:Validate(self, self.CurrentPlan) then
		self:Replan()
	end

	if self.CurrentPlan == nil then
		return
	end

	local ok = self.PlanExecutor:Update(self, self.CurrentPlan, dt)
	self.CurrentAction = self.CurrentPlan:GetCurrentAction()
	if not ok then
		self.needsReplan = true
		self:Replan()
	end
end

function Agent.SetWorldState(self: Agent, keyRaw: any, value: any)
	self.WorldState:Set(keyRaw, value)
end

function Agent.GetWorldState(self: Agent, keyRaw: any): any?
	return self.WorldState:Get(keyRaw)
end

function Agent.GetWorldStateObject(self: Agent): any
	return self.WorldState
end

function Agent.GetBlackboard(self: Agent): any
	return self.Blackboard
end

function Agent.GetCurrentGoal(self: Agent): any?
	return self.CurrentGoal
end

function Agent.GetCurrentPlan(self: Agent): any?
	return self.CurrentPlan
end

function Agent.GetGoals(self: Agent): { any }
	return Table.copy(self.Goals)
end

function Agent.GetActions(self: Agent): { any }
	return Table.copy(self.Actions)
end

function Agent.GetSensors(self: Agent): { any }
	return Table.copy(self.Sensors)
end

function Agent.Destroy(self: Agent)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.CurrentPlan ~= nil then
		self.CurrentPlan:Destroy()
		self.CurrentPlan = nil
	end
	table.clear(self.Goals)
	table.clear(self.Actions)
	table.clear(self.Sensors)
	self.maid:DoCleaning()
end

Agent.addGoal = Agent.AddGoal
Agent.addAction = Agent.AddAction
Agent.addSensor = Agent.AddSensor
Agent.updateSensors = Agent.UpdateSensors
Agent.selectBestGoal = Agent.SelectBestGoal
Agent.replan = Agent.Replan
Agent.update = Agent.Update
Agent.setWorldState = Agent.SetWorldState
Agent.getWorldState = Agent.GetWorldState
Agent.getWorldStateObject = Agent.GetWorldStateObject
Agent.getBlackboard = Agent.GetBlackboard
Agent.getCurrentGoal = Agent.GetCurrentGoal
Agent.getCurrentPlan = Agent.GetCurrentPlan
Agent.getGoals = Agent.GetGoals
Agent.getActions = Agent.GetActions
Agent.getSensors = Agent.GetSensors
Agent.destroy = Agent.Destroy

return Agent
