--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local PriorityScorer = {}
PriorityScorer.__index = PriorityScorer

export type PriorityScorer = typeof(setmetatable(
	{} :: {
		maid: any,
		destroyed: boolean,
	},
	PriorityScorer
))

function PriorityScorer.new(): PriorityScorer
	return setmetatable({
		maid = Maid.new(),
		destroyed = false,
	}, PriorityScorer)
end

function PriorityScorer.GetScore(self: PriorityScorer, goal: any, agent: any): number
	if self.destroyed or typeof(goal) ~= "table" then
		return 0
	end
	local getPriority = goal.GetPriority or goal.getPriority
	if typeof(getPriority) == "function" then
		local ok, result = pcall(getPriority, goal, agent)
		if ok and typeof(result) == "number" and result == result then
			return result
		end
	end
	if typeof(goal.Priority) == "number" and goal.Priority == goal.Priority then
		return goal.Priority
	end
	return 0
end

function PriorityScorer.Destroy(self: PriorityScorer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

PriorityScorer.copy = Table.copy
PriorityScorer.getScore = PriorityScorer.GetScore
PriorityScorer.destroy = PriorityScorer.Destroy

return PriorityScorer
