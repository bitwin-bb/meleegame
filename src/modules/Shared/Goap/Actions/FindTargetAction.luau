--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(gameRoot.Shared.Goap.Core.Action)
local TargetingAdapter = require(gameRoot.Shared.Goap.Integrations.TargetingAdapter)

local FindTargetAction = {}

function FindTargetAction.new(): any
	return Action.new({
		Name = "FindTarget",
		Cost = 1,
		Effects = {
			HasTarget = true,
		},
		Start = function(_, agent)
			TargetingAdapter.FindTarget(agent)
		end,
		IsFinished = function(_, agent)
			return agent:GetWorldState("HasTarget") == true
		end,
	})
end

FindTargetAction.copy = Table.copy

return FindTargetAction
