
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require("GoapAction")
local TargetingAdapter = require("TargetingAdapter")

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
