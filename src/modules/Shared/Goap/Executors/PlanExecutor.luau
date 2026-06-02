--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Runtime")
local Maid = packages.Maid
local Table = packages.Table

local ActionRunner = require(gameRoot.Shared.Goap.Executors.ActionRunner)

local PlanExecutor = {}
PlanExecutor.__index = PlanExecutor

export type PlanExecutor = typeof(setmetatable(
	{} :: {
		maid: any,
		ActionRunner: any,
		currentAction: any?,
		destroyed: boolean,
	},
	PlanExecutor
))

local function getEffects(action: any): any
	if typeof(action) ~= "table" then
		return {}
	end
	local getActionEffects = action.GetEffects or action.getEffects
	if typeof(getActionEffects) == "function" then
		return getActionEffects(action)
	end
	return action.Effects or {}
end

local function applyEffects(agent: any, action: any)
	if typeof(agent) ~= "table" then
		return
	end
	local getWorldStateObject = agent.GetWorldStateObject or agent.getWorldStateObject
	if typeof(getWorldStateObject) ~= "function" then
		return
	end
	local worldState = getWorldStateObject(agent)
	if typeof(worldState) ~= "table" then
		return
	end
	local apply = worldState.Apply or worldState.apply
	if typeof(apply) == "function" then
		apply(worldState, getEffects(action))
	end
end

function PlanExecutor.new(configRaw: any?): PlanExecutor
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local actionRunner = if typeof(config.ActionRunner) == "table" then config.ActionRunner else ActionRunner.new()
	local self = setmetatable({
		maid = Maid.new(),
		ActionRunner = actionRunner,
		currentAction = nil,
		destroyed = false,
	}, PlanExecutor)

	self.maid:GiveTask(actionRunner)
	return self
end

function PlanExecutor.Update(self: PlanExecutor, agent: any, plan: any, dtRaw: any): boolean
	if self.destroyed or typeof(plan) ~= "table" then
		return false
	end
	if plan:IsComplete() then
		return true
	end

	local action = plan:GetCurrentAction()
	if action == nil then
		return true
	end
	if action ~= self.currentAction then
		self.currentAction = action
		if not self.ActionRunner:Start(action, agent) then
			return false
		end
	end

	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	if not self.ActionRunner:Update(action, agent, dt) then
		return false
	end
	if self.ActionRunner:IsFinished(action, agent) then
		applyEffects(agent, action)
		plan:Advance()
		self.currentAction = nil
	end
	return true
end

function PlanExecutor.Cancel(self: PlanExecutor, agent: any)
	if self.currentAction ~= nil then
		self.ActionRunner:Cancel(self.currentAction, agent)
		self.currentAction = nil
	end
end

function PlanExecutor.Destroy(self: PlanExecutor)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.currentAction = nil
	self.maid:DoCleaning()
end

PlanExecutor.copy = Table.copy
PlanExecutor.update = PlanExecutor.Update
PlanExecutor.cancel = PlanExecutor.Cancel
PlanExecutor.destroy = PlanExecutor.Destroy

return PlanExecutor
