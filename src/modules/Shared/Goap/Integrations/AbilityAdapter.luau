
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require("GoapUtils")

local AbilityAdapter = {}

function AbilityAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "AbilityAdapter", Utils.ReadBlackboard(agent, "Abilities", nil))
end

function AbilityAdapter.UseAbility(agent: any, abilityNameRaw: any?): boolean
	local abilities = AbilityAdapter.Get(agent)
	local abilityName = if typeof(abilityNameRaw) == "string" and abilityNameRaw ~= "" then abilityNameRaw else nil
	local target = Utils.ReadBlackboard(agent, "Target", nil)
	local ok = Utils.CallFirst(abilities, { "UseAbility", "useAbility", "Cast", "cast" }, abilityName, target)
	return ok or abilityName ~= nil
end

AbilityAdapter.copy = Table.copy
AbilityAdapter.get = AbilityAdapter.Get
AbilityAdapter.useAbility = AbilityAdapter.UseAbility

return AbilityAdapter
