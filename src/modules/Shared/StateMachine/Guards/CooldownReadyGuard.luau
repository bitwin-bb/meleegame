--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Utils = require(script:FindFirstAncestor("StateMachine").Utils)

local AttributeUtils = Nevermore.Get("AttributeUtils")

local CooldownReadyGuard = {}

local function resolveCooldown(valueRaw: any): number
	if typeof(valueRaw) == "number" then
		return valueRaw
	end
	if typeof(valueRaw) == "Instance" then
		if valueRaw:IsA("NumberValue") then
			return valueRaw.Value
		end
		local attribute = AttributeUtils.getAttribute(valueRaw, "Cooldown", nil)
		if typeof(attribute) == "number" then
			return attribute
		end
	end
	return 0
end

function CooldownReadyGuard.Evaluate(machine: any, cooldownKeyRaw: any?, lastTimeKeyRaw: any?): boolean
	local cooldownKey = if typeof(cooldownKeyRaw) == "string" and cooldownKeyRaw ~= ""
		then cooldownKeyRaw
		else "Cooldown"
	local lastTimeKey = if typeof(lastTimeKeyRaw) == "string" and lastTimeKeyRaw ~= ""
		then lastTimeKeyRaw
		else "LastActionTime"
	local cooldown = resolveCooldown(Utils.Read(machine, cooldownKey, 0))
	local lastTime = Utils.Read(machine, lastTimeKey, -math.huge)

	if cooldown <= 0 then
		return true
	end
	if typeof(lastTime) ~= "number" then
		return true
	end
	return os.clock() - lastTime >= cooldown
end

function CooldownReadyGuard.new(configRaw: any?): (any) -> boolean
	local config: any = if typeof(configRaw) == "table" then configRaw else {}
	return function(machine: any): boolean
		return CooldownReadyGuard.Evaluate(
			machine,
			config.CooldownKey or config.cooldownKey,
			config.LastTimeKey or config.lastTimeKey
		)
	end
end

return CooldownReadyGuard
