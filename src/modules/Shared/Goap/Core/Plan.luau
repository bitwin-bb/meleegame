--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local Plan = {}
Plan.__index = Plan

export type Plan = typeof(setmetatable(
	{} :: {
		actions: { any },
		currentIndex: number,
		cost: number,
		maid: any,
		destroyed: boolean,
	},
	Plan
))

local function resolveCost(actions: { any }, costRaw: any): number
	if typeof(costRaw) == "number" and costRaw == costRaw then
		return math.max(0, costRaw)
	end
	local cost = 0
	for _, action in actions do
		if typeof(action) == "table" and typeof(action.Cost) == "number" then
			cost += math.max(0, action.Cost)
		end
	end
	return cost
end

function Plan.new(actionsRaw: any?, costRaw: any?): Plan
	local actions = if typeof(actionsRaw) == "table" then Table.copy(actionsRaw) else {}
	return setmetatable({
		actions = actions,
		currentIndex = 1,
		cost = resolveCost(actions, costRaw),
		maid = Maid.new(),
		destroyed = false,
	}, Plan)
end

function Plan.GetActions(self: Plan): { any }
	if self.destroyed then
		return {}
	end
	return Table.copy(self.actions)
end

function Plan.GetCurrentAction(self: Plan): any?
	if self.destroyed then
		return nil
	end
	return self.actions[self.currentIndex]
end

function Plan.GetCurrentIndex(self: Plan): number
	return self.currentIndex
end

function Plan.Advance(self: Plan): any?
	if self.destroyed then
		return nil
	end
	self.currentIndex += 1
	return self:GetCurrentAction()
end

function Plan.IsComplete(self: Plan): boolean
	return self.destroyed or self.currentIndex > #self.actions
end

function Plan.Reset(self: Plan)
	if self.destroyed then
		return
	end
	self.currentIndex = 1
end

function Plan.GetCost(self: Plan): number
	return self.cost
end

function Plan.Destroy(self: Plan)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
	table.clear(self.actions)
end

Plan.getActions = Plan.GetActions
Plan.getCurrentAction = Plan.GetCurrentAction
Plan.getCurrentIndex = Plan.GetCurrentIndex
Plan.advance = Plan.Advance
Plan.isComplete = Plan.IsComplete
Plan.reset = Plan.Reset
Plan.getCost = Plan.GetCost
Plan.destroy = Plan.Destroy

return Plan
