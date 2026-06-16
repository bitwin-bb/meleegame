
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Core")
local Maid = packages.Maid
local Table = packages.Table

local ThreatScorer = {}
ThreatScorer.__index = ThreatScorer

export type ThreatScorer = typeof(setmetatable(
	{} :: {
		maid: any,
		destroyed: boolean,
	},
	ThreatScorer
))

local function goalWantsTargetDead(goal: any): boolean
	if typeof(goal) ~= "table" then
		return false
	end
	local desiredState = goal.GetDesiredState and goal:GetDesiredState() or goal.DesiredState
	if typeof(desiredState) ~= "table" then
		return false
	end
	local toTable = desiredState.ToTable or desiredState.toTable
	local values = if typeof(toTable) == "function" then toTable(desiredState) else desiredState
	return values.TargetDead == true
end

function ThreatScorer.new(): ThreatScorer
	return setmetatable({
		maid = Maid.new(),
		destroyed = false,
	}, ThreatScorer)
end

function ThreatScorer.GetScore(self: ThreatScorer, goal: any, agent: any): number
	if self.destroyed or typeof(agent) ~= "table" or not goalWantsTargetDead(goal) then
		return 0
	end
	local getWorldState = agent.GetWorldState or agent.getWorldState
	if typeof(getWorldState) ~= "function" then
		return 0
	end
	if getWorldState(agent, "HasTarget") ~= true then
		return 0
	end
	return if getWorldState(agent, "TargetInRange") == true then 15 else 5
end

function ThreatScorer.Destroy(self: ThreatScorer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

ThreatScorer.copy = Table.copy
ThreatScorer.getScore = ThreatScorer.GetScore
ThreatScorer.destroy = ThreatScorer.Destroy

return ThreatScorer
