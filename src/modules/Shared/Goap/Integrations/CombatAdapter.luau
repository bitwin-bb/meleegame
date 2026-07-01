
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require("GoapUtils")

local CombatAdapter = {}

function CombatAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "CombatAdapter", Utils.ReadBlackboard(agent, "Combat", nil))
end

function CombatAdapter.AttackTarget(agent: any): boolean
	local combat = CombatAdapter.Get(agent)
	local target = Utils.ReadBlackboard(agent, "Target", nil)
	local ok = Utils.CallFirst(combat, { "AttackTarget", "attackTarget", "Attack", "attack" }, target)
	return ok or target ~= nil
end

CombatAdapter.copy = Table.copy
return CombatAdapter
