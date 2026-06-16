
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local WorldState = require("WorldState")

local Action = {}
Action.__index = Action

export type Action = typeof(setmetatable(
	{} :: {
		Name: string,
		Cost: number,
		Preconditions: any,
		Effects: any,
		maid: any,
		canRun: ((any, any) -> boolean)?,
		start: ((any, any) -> ())?,
		update: ((any, any, number) -> ())?,
		isFinished: ((any, any) -> boolean)?,
		cancel: ((any, any) -> ())?,
		getCost: ((any, any) -> number)?,
		destroyed: boolean,
	},
	Action
))

local function sanitizeCost(costRaw: any, fallback: number): number
	if typeof(costRaw) ~= "number" or costRaw ~= costRaw then
		return fallback
	end
	return math.max(0, costRaw)
end

function Action.new(configRaw: any?): Action
	local config = if typeof(configRaw) == "table" then Table.copy(configRaw) else {}
	local self = setmetatable({
		Name = if typeof(config.Name) == "string" and config.Name ~= "" then config.Name else "Action",
		Cost = sanitizeCost(config.Cost, 1),
		Preconditions = WorldState.new(config.Preconditions),
		Effects = WorldState.new(config.Effects),
		maid = Maid.new(),
		canRun = if typeof(config.CanRun) == "function" then config.CanRun else nil,
		start = if typeof(config.Start) == "function" then config.Start else nil,
		update = if typeof(config.Update) == "function" then config.Update else nil,
		isFinished = if typeof(config.IsFinished) == "function" then config.IsFinished else nil,
		cancel = if typeof(config.Cancel) == "function" then config.Cancel else nil,
		getCost = if typeof(config.GetCost) == "function" then config.GetCost else nil,
		destroyed = false,
	}, Action)

	self.maid:GiveTask(self.Preconditions)
	self.maid:GiveTask(self.Effects)
	return self
end

function Action.CanRun(self: Action, agent: any): boolean
	if self.destroyed then
		return false
	end
	if self.canRun == nil then
		return true
	end
	return self.canRun(self, agent) == true
end

function Action.Start(self: Action, agent: any)
	if self.destroyed or self.start == nil then
		return
	end
	self.start(self, agent)
end

function Action.Update(self: Action, agent: any, dtRaw: any)
	if self.destroyed or self.update == nil then
		return
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	self.update(self, agent, dt)
end

function Action.IsFinished(self: Action, agent: any): boolean
	if self.destroyed then
		return true
	end
	if self.isFinished == nil then
		return true
	end
	return self.isFinished(self, agent) == true
end

function Action.Cancel(self: Action, agent: any)
	if self.destroyed or self.cancel == nil then
		return
	end
	self.cancel(self, agent)
end

function Action.GetCost(self: Action, agent: any): number
	if self.getCost ~= nil then
		return sanitizeCost(self.getCost(self, agent), self.Cost)
	end
	return self.Cost
end

function Action.GetPreconditions(self: Action): any
	return self.Preconditions
end

function Action.GetEffects(self: Action): any
	return self.Effects
end

function Action.Destroy(self: Action)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

Action.canRunAction = Action.CanRun
Action.startAction = Action.Start
Action.updateAction = Action.Update
Action.isFinishedAction = Action.IsFinished
Action.cancelAction = Action.Cancel
Action.getCost = Action.GetCost
Action.getPreconditions = Action.GetPreconditions
Action.getEffects = Action.GetEffects
Action.destroy = Action.Destroy

return Action
