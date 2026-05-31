--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local WorldState = require(script.Parent.WorldState)

local Goal = {}
Goal.__index = Goal

export type Goal = typeof(setmetatable(
	{} :: {
		Name: string,
		Priority: number,
		DesiredState: any,
		maid: any,
		canRun: ((any, any) -> boolean)?,
		getPriority: ((any, any) -> number)?,
		destroyed: boolean,
	},
	Goal
))

local function sanitizePriority(priorityRaw: any, fallback: number): number
	if typeof(priorityRaw) ~= "number" or priorityRaw ~= priorityRaw then
		return fallback
	end
	return priorityRaw
end

function Goal.new(configRaw: any?): Goal
	local config = if typeof(configRaw) == "table" then Table.copy(configRaw) else {}
	local self = setmetatable({
		Name = if typeof(config.Name) == "string" and config.Name ~= "" then config.Name else "Goal",
		Priority = sanitizePriority(config.Priority, 1),
		DesiredState = WorldState.new(config.DesiredState),
		maid = Maid.new(),
		canRun = if typeof(config.CanRun) == "function" then config.CanRun else nil,
		getPriority = if typeof(config.GetPriority) == "function" then config.GetPriority else nil,
		destroyed = false,
	}, Goal)

	self.maid:GiveTask(self.DesiredState)
	return self
end

function Goal.CanRun(self: Goal, agent: any): boolean
	if self.destroyed then
		return false
	end
	if self.canRun == nil then
		return true
	end
	return self.canRun(self, agent) == true
end

function Goal.GetPriority(self: Goal, agent: any): number
	if self.getPriority ~= nil then
		return sanitizePriority(self.getPriority(self, agent), self.Priority)
	end
	return self.Priority
end

function Goal.GetDesiredState(self: Goal): any
	return self.DesiredState
end

function Goal.Destroy(self: Goal)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

Goal.canRunGoal = Goal.CanRun
Goal.getPriority = Goal.GetPriority
Goal.getDesiredState = Goal.GetDesiredState
Goal.destroy = Goal.Destroy

return Goal
