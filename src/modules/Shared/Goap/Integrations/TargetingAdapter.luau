--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require(script:FindFirstAncestor("Goap").Utils)

local TargetingAdapter = {}

function TargetingAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "TargetingAdapter", Utils.ReadBlackboard(agent, "Targeting", nil))
end

function TargetingAdapter.FindTarget(agent: any): any?
	local targeting = TargetingAdapter.Get(agent)
	local ok, result =
		Utils.CallFirst(targeting, { "FindTarget", "findTarget", "AcquireTarget", "acquireTarget" }, agent)
	if ok and result ~= nil then
		agent:GetBlackboard():Set("Target", result)
		agent:SetWorldState("HasTarget", true)
		return result
	end
	local target = Utils.ReadBlackboard(agent, "Target", nil)
	agent:SetWorldState("HasTarget", target ~= nil)
	return target
end

TargetingAdapter.copy = Table.copy
TargetingAdapter.get = TargetingAdapter.Get
TargetingAdapter.findTarget = TargetingAdapter.FindTarget

return TargetingAdapter
