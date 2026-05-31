--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local GoalScorer = {}
GoalScorer.__index = GoalScorer

export type GoalScorer = typeof(setmetatable(
	{} :: {
		Scorers: { any },
		maid: any,
		destroyed: boolean,
	},
	GoalScorer
))

local function canRunGoal(goal: any, agent: any): boolean
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

local function scoreWith(scorer: any, goal: any, agent: any): number
	if typeof(scorer) ~= "table" then
		return 0
	end
	local getScore = scorer.GetScore or scorer.getScore
	if typeof(getScore) ~= "function" then
		return 0
	end
	local ok, result = pcall(getScore, scorer, goal, agent)
	if ok and typeof(result) == "number" and result == result then
		return result
	end
	return 0
end

function GoalScorer.new(scorersRaw: any?): GoalScorer
	return setmetatable({
		Scorers = if typeof(scorersRaw) == "table" then Table.copy(scorersRaw) else {},
		maid = Maid.new(),
		destroyed = false,
	}, GoalScorer)
end

function GoalScorer.AddScorer(self: GoalScorer, scorer: any): any
	if self.destroyed or typeof(scorer) ~= "table" then
		return scorer
	end
	self.Scorers[#self.Scorers + 1] = scorer
	return scorer
end

function GoalScorer.GetScore(self: GoalScorer, goal: any, agent: any): number
	if self.destroyed or not canRunGoal(goal, agent) then
		return -math.huge
	end
	if #self.Scorers == 0 and typeof(goal) == "table" then
		local getPriority = goal.GetPriority or goal.getPriority
		if typeof(getPriority) == "function" then
			local ok, result = pcall(getPriority, goal, agent)
			if ok and typeof(result) == "number" and result == result then
				return result
			end
		end
	end

	local score = 0
	for _, scorer in self.Scorers do
		score += scoreWith(scorer, goal, agent)
	end
	return score
end

function GoalScorer.Destroy(self: GoalScorer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	table.clear(self.Scorers)
	self.maid:DoCleaning()
end

GoalScorer.copy = Table.copy
GoalScorer.addScorer = GoalScorer.AddScorer
GoalScorer.getScore = GoalScorer.GetScore
GoalScorer.destroy = GoalScorer.Destroy

return GoalScorer
