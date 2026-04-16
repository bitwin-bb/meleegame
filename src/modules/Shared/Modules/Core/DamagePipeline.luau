--!strict

local DeterministicRNG = require(script.Parent.DeterministicRNG)

local DamagePipeline = {}
DamagePipeline.__index = DamagePipeline

export type StageHandler = (context: any, result: any, pipeline: DamagePipeline) -> ()

export type RegisteredHandler = {
	priority: number,
	order: number,
	handler: StageHandler,
}

export type DamagePipeline = typeof(setmetatable({} :: any, DamagePipeline))

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function clampPriority(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	local value = math.floor(valueRaw)
	if value < -1000000 then
		return -1000000
	end
	if value > 1000000 then
		return 1000000
	end
	return value
end

local function sortHandlers(a: RegisteredHandler, b: RegisteredHandler): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	return a.order < b.order
end

local function runStage(handlers: { RegisteredHandler }, context: any, result: any, pipeline: DamagePipeline)
	for index = 1, #handlers do
		handlers[index].handler(context, result, pipeline)
	end
end

local function defaultCritStage(context: any, result: any)
	local critChance = clampNumber(context.critChance, 0, 0, 1)
	if critChance <= 0 then
		result.wasCrit = false
		return
	end
	local rng = context.rng
	local roll = 1
	if rng ~= nil and typeof((rng :: any).nextNumber) == "function" then
		roll = (rng :: any):nextNumber()
	else
		local fallback = DeterministicRNG.new(context.seed or 1)
		roll = fallback:nextNumber()
	end
	if roll <= critChance then
		local critMultiplier = clampNumber(context.critMultiplier, 1.5, 1, 100)
		result.damage = result.damage * critMultiplier
		result.wasCrit = true
	else
		result.wasCrit = false
	end
end

local function defaultDefenseStage(context: any, result: any)
	local defense = clampNumber(context.defense, 0, -1000000, 1000000)
	local penetration = clampNumber(context.penetration, 0, 0, 1000000)
	local effectiveDefense = math.max(0, defense - penetration)
	result.damage = math.max(0, result.damage - effectiveDefense)
end

local function defaultDamageTypeStage(context: any, result: any)
	if typeof(context.damageTypes) == "table" then
		local total = 0
		local resistances = if typeof(context.resistances) == "table" then context.resistances else {}
		for damageType, amount in context.damageTypes do
			if typeof(amount) ~= "number" then
				continue
			end
			local multiplier = 1
			local resistance = resistances[damageType]
			if typeof(resistance) == "number" then
				multiplier = math.max(0, 1 - resistance)
			end
			total += math.max(0, amount) * multiplier
		end
		result.damage = total
		return
	end

	if typeof(context.damageType) == "string" and typeof(context.resistances) == "table" then
		local resistance = context.resistances[context.damageType]
		if typeof(resistance) == "number" then
			result.damage = result.damage * math.max(0, 1 - resistance)
		end
	end
end

local function defaultStatusStage(context: any, result: any)
	local statuses = if typeof(context.statusEffects) == "table" then context.statusEffects else {}
	if #statuses == 0 then
		return
	end
	local rng = context.rng
	if rng == nil or typeof((rng :: any).nextNumber) ~= "function" then
		rng = DeterministicRNG.new(context.seed or 1)
	end

	for _, effect in statuses do
		if typeof(effect) ~= "table" or typeof(effect.id) ~= "string" then
			continue
		end
		local chance = clampNumber(effect.chance, 1, 0, 1)
		if (rng :: any):nextNumber() <= chance then
			result.statuses[#result.statuses + 1] = {
				id = effect.id,
				duration = clampNumber(effect.duration, 0, 0, 100000),
				potency = clampNumber(effect.potency, 1, 0, 100000),
			}
		end
	end
end

local function defaultKnockbackStage(context: any, result: any)
	local force = clampNumber(context.knockbackForce, 0, 0, 100000)
	if force <= 0 then
		return
	end
	local direction = context.knockbackDirection
	if typeof(direction) ~= "table" then
		return
	end
	local x = clampNumber(direction.x, 0, -1, 1)
	local y = clampNumber(direction.y, 0, -1, 1)
	local z = clampNumber(direction.z, 0, -1, 1)
	result.knockback = {
		x = x * force,
		y = y * force,
		z = z * force,
	}
end

function DamagePipeline.New(): DamagePipeline
	local self = setmetatable({
		handlerOrder = 0,
		preModifiers = {} :: { RegisteredHandler },
		critStage = {} :: { RegisteredHandler },
		defenseStage = {} :: { RegisteredHandler },
		typeStage = {} :: { RegisteredHandler },
		statusStage = {} :: { RegisteredHandler },
		knockbackStage = {} :: { RegisteredHandler },
		postHooks = {} :: { RegisteredHandler },
	}, DamagePipeline)

	self:useCrit(defaultCritStage, -1000)
	self:useDefense(defaultDefenseStage, -1000)
	self:useDamageTypes(defaultDamageTypeStage, -1000)
	self:useStatus(defaultStatusStage, -1000)
	self:useKnockback(defaultKnockbackStage, -1000)

	return self
end

function DamagePipeline._register(self: DamagePipeline, bucket: { RegisteredHandler }, handler: StageHandler, priorityRaw: any)
	if typeof(handler) ~= "function" then
		return
	end
	self.handlerOrder += 1
	bucket[#bucket + 1] = {
		priority = clampPriority(priorityRaw, 0),
		order = self.handlerOrder,
		handler = handler,
	}
	table.sort(bucket, sortHandlers)
end

function DamagePipeline.UsePreModifier(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.preModifiers, handler, priorityRaw)
end

function DamagePipeline.UseCrit(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.critStage, handler, priorityRaw)
end

function DamagePipeline.UseDefense(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.defenseStage, handler, priorityRaw)
end

function DamagePipeline.UseDamageTypes(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.typeStage, handler, priorityRaw)
end

function DamagePipeline.UseStatus(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.statusStage, handler, priorityRaw)
end

function DamagePipeline.UseKnockback(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.knockbackStage, handler, priorityRaw)
end

function DamagePipeline.UsePostHook(self: DamagePipeline, handler: StageHandler, priorityRaw: any)
	self:_register(self.postHooks, handler, priorityRaw)
end

function DamagePipeline.Process(self: DamagePipeline, contextRaw: any): any
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local result = {
		attacker = context.attacker,
		defender = context.defender,
		damage = clampNumber(context.baseDamage, 0, 0, 100000000),
		wasCrit = false,
		statuses = {},
		knockback = nil,
		damageType = context.damageType,
		meta = {},
	}

	runStage(self.preModifiers, context, result, self)
	runStage(self.critStage, context, result, self)
	runStage(self.defenseStage, context, result, self)
	runStage(self.typeStage, context, result, self)
	runStage(self.statusStage, context, result, self)
	runStage(self.knockbackStage, context, result, self)

	result.damage = math.max(0, result.damage)
	result.finalDamage = result.damage
	runStage(self.postHooks, context, result, self)
	return result
end

DamagePipeline.new = DamagePipeline.New
DamagePipeline.usePreModifier = DamagePipeline.UsePreModifier
DamagePipeline.useCrit = DamagePipeline.UseCrit
DamagePipeline.useDefense = DamagePipeline.UseDefense
DamagePipeline.useDamageTypes = DamagePipeline.UseDamageTypes
DamagePipeline.useStatus = DamagePipeline.UseStatus
DamagePipeline.useKnockback = DamagePipeline.UseKnockback
DamagePipeline.usePostHook = DamagePipeline.UsePostHook
DamagePipeline.process = DamagePipeline.Process

return DamagePipeline
