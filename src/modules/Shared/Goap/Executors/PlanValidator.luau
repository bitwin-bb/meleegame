
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Runtime")
local Maid = packages.Maid
local Table = packages.Table

local WorldState = require("WorldState")

local PlanValidator = {}
PlanValidator.__index = PlanValidator

export type PlanValidator = typeof(setmetatable(
	{} :: {
		maid: any,
		destroyed: boolean,
	},
	PlanValidator
))

local function getPreconditions(action: any): any
	if typeof(action) ~= "table" then
		return {}
	end
	local getActionPreconditions = action.GetPreconditions or action.getPreconditions
	if typeof(getActionPreconditions) == "function" then
		return getActionPreconditions(action)
	end
	return action.Preconditions or {}
end

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

local function canRunAction(action: any, agent: any): boolean
	if typeof(action) ~= "table" then
		return false
	end
	local canRun = action.CanRun or action.canRunAction or action.canRun
	if typeof(canRun) ~= "function" then
		return true
	end
	local ok, result = pcall(canRun, action, agent)
	return ok and result == true
end

function PlanValidator.new(): PlanValidator
	return setmetatable({
		maid = Maid.new(),
		destroyed = false,
	}, PlanValidator)
end

function PlanValidator.Validate(self: PlanValidator, agent: any, plan: any): boolean
	if self.destroyed or typeof(plan) ~= "table" then
		return false
	end
	if plan:IsComplete() then
		return true
	end
	local getWorldStateObject = agent.GetWorldStateObject or agent.getWorldStateObject
	if typeof(getWorldStateObject) ~= "function" then
		return false
	end

	local state = WorldState.From(getWorldStateObject(agent))
	local actions = plan:GetActions()
	local startIndex = plan:GetCurrentIndex()
	for index = startIndex, #actions do
		local action = actions[index]
		if not canRunAction(action, agent) or not state:Satisfies(getPreconditions(action)) then
			state:Destroy()
			return false
		end
		state:Apply(getEffects(action))
	end
	state:Destroy()
	return true
end

function PlanValidator.Destroy(self: PlanValidator)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

PlanValidator.copy = Table.copy
return PlanValidator
