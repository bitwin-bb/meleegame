--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local HealthScorer = {}
HealthScorer.__index = HealthScorer

export type HealthScorer = typeof(setmetatable(
	{} :: {
		maid: any,
		destroyed: boolean,
	},
	HealthScorer
))

local function goalWantsSafety(goal: any): boolean
	if typeof(goal) ~= "table" then
		return false
	end
	local desiredState = goal.GetDesiredState and goal:GetDesiredState() or goal.DesiredState
	if typeof(desiredState) ~= "table" then
		return false
	end
	local toTable = desiredState.ToTable or desiredState.toTable
	local values = if typeof(toTable) == "function" then toTable(desiredState) else desiredState
	return values.IsSafe == true or values.HealthLow == false
end

function HealthScorer.new(): HealthScorer
	return setmetatable({
		maid = Maid.new(),
		destroyed = false,
	}, HealthScorer)
end

function HealthScorer.GetScore(self: HealthScorer, goal: any, agent: any): number
	if self.destroyed or typeof(agent) ~= "table" or not goalWantsSafety(goal) then
		return 0
	end
	local getWorldState = agent.GetWorldState or agent.getWorldState
	if typeof(getWorldState) ~= "function" then
		return 0
	end
	return if getWorldState(agent, "HealthLow") == true then 50 else 0
end

function HealthScorer.Destroy(self: HealthScorer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

HealthScorer.copy = Table.copy
HealthScorer.getScore = HealthScorer.GetScore
HealthScorer.destroy = HealthScorer.Destroy

return HealthScorer
