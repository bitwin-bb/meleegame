
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Planning")
local Maid = packages.Maid
local Table = packages.Table

local Plan = require("Plan")
local WorldState = require("WorldState")

local Planner = {}
Planner.__index = Planner

export type Planner = typeof(setmetatable(
	{} :: {
		MaxIterations: number,
		maid: any,
		destroyed: boolean,
	},
	Planner
))

type Node = {
	state: any,
	actions: { any },
	cost: number,
}

local function sanitizeIterations(iterationsRaw: any): number
	if typeof(iterationsRaw) ~= "number" or iterationsRaw ~= iterationsRaw then
		return 256
	end
	return math.clamp(math.floor(iterationsRaw), 1, 4096)
end

local function getActionName(action: any): string
	if typeof(action) == "table" and typeof(action.Name) == "string" and action.Name ~= "" then
		return action.Name
	end
	return tostring(action)
end

local function getActionPreconditions(action: any): any
	if typeof(action) ~= "table" then
		return {}
	end
	local getPreconditions = action.GetPreconditions or action.getPreconditions
	if typeof(getPreconditions) == "function" then
		return getPreconditions(action)
	end
	return action.Preconditions or {}
end

local function getActionEffects(action: any): any
	if typeof(action) ~= "table" then
		return {}
	end
	local getEffects = action.GetEffects or action.getEffects
	if typeof(getEffects) == "function" then
		return getEffects(action)
	end
	return action.Effects or {}
end

local function getActionCost(action: any, agent: any): number
	if typeof(action) ~= "table" then
		return 0
	end
	local getCost = action.GetCost or action.getCost
	if typeof(getCost) == "function" then
		local ok, result = pcall(getCost, action, agent)
		if ok and typeof(result) == "number" and result == result then
			return math.max(0, result)
		end
	end
	if typeof(action.Cost) == "number" and action.Cost == action.Cost then
		return math.max(0, action.Cost)
	end
	return 1
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

local function getGoalDesiredState(goal: any): any
	if typeof(goal) ~= "table" then
		return {}
	end
	local getDesiredState = goal.GetDesiredState or goal.getDesiredState
	if typeof(getDesiredState) == "function" then
		return getDesiredState(goal)
	end
	return goal.DesiredState or {}
end

local function buildSignature(worldState: any): string
	local values = worldState:ToTable()
	local keys = {}
	for key in values do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local parts = table.create(#keys)
	for _, key in keys do
		parts[#parts + 1] = `{key}={tostring(values[key])}`
	end
	return table.concat(parts, "|")
end

local function copyActions(actions: { any }, nextAction: any): { any }
	local out = Table.copy(actions)
	out[#out + 1] = nextAction
	return out
end

function Planner.new(configRaw: any?): Planner
	local config = if typeof(configRaw) == "table" then configRaw else {}
	return setmetatable({
		MaxIterations = sanitizeIterations(config.MaxIterations),
		maid = Maid.new(),
		destroyed = false,
	}, Planner)
end

function Planner.CanUseAction(self: Planner, worldState: any, action: any): boolean
	if self.destroyed or typeof(worldState) ~= "table" then
		return false
	end
	local satisfies = worldState.Satisfies or worldState.satisfies
	if typeof(satisfies) ~= "function" then
		return false
	end
	return satisfies(worldState, getActionPreconditions(action)) == true
end

function Planner.ApplyAction(self: Planner, worldState: any, action: any): any
	if self.destroyed then
		return WorldState.From(worldState)
	end
	local nextState = WorldState.From(worldState)
	nextState:Apply(getActionEffects(action))
	return nextState
end

function Planner.BuildPlan(self: Planner, agent: any, worldStateRaw: any, goal: any, actionsRaw: any): any?
	if self.destroyed or typeof(actionsRaw) ~= "table" then
		return nil
	end

	local desiredState = getGoalDesiredState(goal)
	local startState = WorldState.From(worldStateRaw)
	local ownedStates = { startState }
	local open: { Node } = {
		{
			state = startState,
			actions = {},
			cost = 0,
		},
	}
	local bestCosts: { [string]: number } = {
		[buildSignature(startState)] = 0,
	}
	local iterations = 0

	while #open > 0 and iterations < self.MaxIterations do
		iterations += 1
		table.sort(open, function(a, b)
			return a.cost < b.cost
		end)

		local node = table.remove(open, 1) :: Node
		if node.state:Satisfies(desiredState) then
			for _, ownedState in ownedStates do
				ownedState:Destroy()
			end
			return Plan.new(node.actions, node.cost)
		end

		for _, action in actionsRaw do
			if not canRunAction(action, agent) or not self:CanUseAction(node.state, action) then
				continue
			end

			local nextState = self:ApplyAction(node.state, action)
			ownedStates[#ownedStates + 1] = nextState
			local nextCost = node.cost + getActionCost(action, agent)
			local signature = buildSignature(nextState)
			local bestCost = bestCosts[signature]
			if bestCost ~= nil and bestCost <= nextCost then
				continue
			end

			bestCosts[signature] = nextCost
			open[#open + 1] = {
				state = nextState,
				actions = copyActions(node.actions, action),
				cost = nextCost,
			}
		end
	end

	for _, ownedState in ownedStates do
		ownedState:Destroy()
	end
	return nil
end

function Planner.Destroy(self: Planner)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

Planner.getActionName = getActionName
Planner.canUseAction = Planner.CanUseAction
Planner.applyAction = Planner.ApplyAction
Planner.buildPlan = Planner.BuildPlan
Planner.destroy = Planner.Destroy

return Planner
