local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuffConstants = require("BuffConstants")

local buffUtils = {}

export type BuffEffects = { [string]: any }

export type BuffRecord = {
	id: string,
	name: string,
	kind: string,
	duration: number,
	description: string,
	affects: string,
	effects: BuffEffects,
	appliedAt: number,
	expiresAt: number?,
	stacks: number,
	maxStacks: number,
	stackMode: string,
	source: string?,
	icon: string?,
	hidden: boolean?,
	remainingSeconds: number?,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.gsub(valueRaw, "^%s*(.-)%s*$", "%1")
end

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(valueRaw)
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	return math.clamp(value, minimum, maximum)
end

local function CoerceBoolean(valueRaw: any, fallback: boolean?): boolean?
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function getTable(valueRaw: any): { [string]: any }
	if typeof(valueRaw) == "table" then
		return valueRaw :: { [string]: any }
	end
	return {}
end

function buffUtils.Trim(valueRaw: any): string
	return trim(valueRaw)
end

function buffUtils.CoerceKind(kindRaw: any, fallbackRaw: any?): string
	if kindRaw == BuffConstants.KIND_DEBUFF then
		return BuffConstants.KIND_DEBUFF
	end
	if kindRaw == BuffConstants.KIND_BUFF then
		return BuffConstants.KIND_BUFF
	end
	if fallbackRaw == BuffConstants.KIND_DEBUFF then
		return BuffConstants.KIND_DEBUFF
	end
	return BuffConstants.KIND_BUFF
end

function buffUtils.CoerceName(nameRaw: any): string
	local name = trim(nameRaw)
	if name == "" then
		return BuffConstants.UNKNOWN_BUFF_NAME
	end
	return name
end

function buffUtils.CoerceDuration(durationRaw: any): number
	return CoerceNumber(
		durationRaw,
		BuffConstants.DEFAULT_DURATION_SECONDS,
		BuffConstants.MIN_DURATION_SECONDS,
		BuffConstants.MAX_DURATION_SECONDS
	)
end

function buffUtils.CoerceStacks(stacksRaw: any): number
	return math.max(1, math.floor(CoerceNumber(stacksRaw, BuffConstants.DEFAULT_STACKS, 1, 999)))
end

function buffUtils.CoerceMaxStacks(maxStacksRaw: any): number
	return math.max(1, math.floor(CoerceNumber(maxStacksRaw, BuffConstants.DEFAULT_MAX_STACKS, 1, 999)))
end

function buffUtils.CoerceStackMode(stackModeRaw: any): string
	if BuffConstants.IsStackMode(stackModeRaw) then
		return stackModeRaw
	end
	return BuffConstants.STACK_MODE_REFRESH
end

function buffUtils.CloneEffects(effectsRaw: any): BuffEffects
	if typeof(effectsRaw) ~= "table" then
		return {}
	end
	return Table.deepCopy(effectsRaw :: BuffEffects)
end

function buffUtils.CloneRecord(record: BuffRecord): BuffRecord
	local clone = Table.copy(record) :: BuffRecord
	clone.effects = buffUtils.CloneEffects(record.effects)
	return clone
end

function buffUtils.CreateReplicatedRecord(record: BuffRecord, nowRaw: any?): BuffRecord
	local clone = buffUtils.CloneRecord(record)
	clone.effects = {}
	clone.remainingSeconds = buffUtils.GetRemainingSeconds(record, nowRaw)
	return clone
end

function buffUtils.CreateReplicatedRecords(records: { BuffRecord }, nowRaw: any?): { BuffRecord }
	local output = {}
	for _, record in records do
		table.insert(output, buffUtils.CreateReplicatedRecord(record, nowRaw))
	end
	return output
end

function buffUtils.CloneRecords(records: { BuffRecord }): { BuffRecord }
	local output = {}
	for _, record in records do
		table.insert(output, buffUtils.CloneRecord(record))
	end
	return output
end

function buffUtils.CreateId(kindRaw: any, nameRaw: any): string
	local kind = buffUtils.CoerceKind(kindRaw)
	local name = buffUtils.CoerceName(nameRaw)
	return `{kind}:{string.lower(name)}`
end

function buffUtils.GetRemainingSeconds(recordRaw: any, nowRaw: any?): number?
	local record = getTable(recordRaw)
	local expiresAt = record.expiresAt
	if typeof(expiresAt) ~= "number" then
		return nil
	end

	local now = if typeof(nowRaw) == "number" then nowRaw else os.clock()
	return math.max(0, expiresAt - now)
end

function buffUtils.IsExpired(recordRaw: any, nowRaw: any?): boolean
	local remaining = buffUtils.GetRemainingSeconds(recordRaw, nowRaw)
	return remaining ~= nil and remaining <= 0
end

function buffUtils.CreateRecord(
	kindRaw: any,
	nameRaw: any,
	durationRaw: any,
	effectsRaw: any,
	descriptionRaw: any,
	affectsRaw: any,
	optionsRaw: any?
): BuffRecord
	local source = getTable(if typeof(nameRaw) == "table" then nameRaw else optionsRaw)
	local positional = typeof(nameRaw) ~= "table"

	local kind = buffUtils.CoerceKind(source.kind or source.type or source.category or kindRaw)
	local name = buffUtils.CoerceName(if positional then nameRaw else source.name or source.buffName or source.id)
	local duration =
		buffUtils.CoerceDuration(if positional then durationRaw else source.duration or source.durationSeconds)
	local effects = buffUtils.CloneEffects(if positional then effectsRaw else source.effects or source.specialEffects)
	local description = trim(if positional then descriptionRaw else source.description or source.tooltip)
	local affects = trim(if positional then affectsRaw else source.affects or source.playerEffect or source.affectsPlayer)
	local appliedAt = CoerceNumber(source.appliedAt, os.clock(), 0, math.huge)
	local id = trim(source.id)
	if id == "" then
		id = buffUtils.CreateId(kind, name)
	end

	local maxStacks = buffUtils.CoerceMaxStacks(source.maxStacks)
	local stacks = math.min(buffUtils.CoerceStacks(source.stacks), maxStacks)
	local expiresAt = nil
	if duration > 0 then
		expiresAt = appliedAt + duration
	end

	return {
		id = id,
		name = name,
		kind = kind,
		duration = duration,
		description = if description ~= "" then description else BuffConstants.DEFAULT_DESCRIPTION,
		affects = if affects ~= "" then affects else BuffConstants.DEFAULT_AFFECTS,
		effects = effects,
		appliedAt = appliedAt,
		expiresAt = expiresAt,
		stacks = stacks,
		maxStacks = maxStacks,
		stackMode = buffUtils.CoerceStackMode(source.stackMode or effects.stackMode),
		source = trim(source.source),
		icon = trim(source.icon or source.iconId),
		hidden = CoerceBoolean(source.hidden, nil),
	}
end

function buffUtils.MergeRecord(existing: BuffRecord, incoming: BuffRecord): BuffRecord
	if incoming.stackMode == BuffConstants.STACK_MODE_IGNORE then
		return buffUtils.CloneRecord(existing)
	end

	local merged = buffUtils.CloneRecord(incoming)
	merged.stacks = math.min(existing.stacks + incoming.stacks, incoming.maxStacks)

	if incoming.stackMode == BuffConstants.STACK_MODE_EXTEND and existing.expiresAt ~= nil and incoming.duration > 0 then
		merged.appliedAt = existing.appliedAt
		merged.expiresAt = existing.expiresAt + incoming.duration
		merged.duration = math.max(0, merged.expiresAt - merged.appliedAt)
	end

	return merged
end

function buffUtils.ApplyOverrides(recordRaw: any, overridesRaw: any?): BuffRecord
	local base = if typeof(recordRaw) == "table" then recordRaw :: { [string]: any } else {}
	local overrides = getTable(overridesRaw)
	local merged = Table.merge(base, overrides)

	if overrides.effects ~= nil and typeof(base.effects) == "table" and typeof(overrides.effects) == "table" then
		merged.effects = Table.merge(base.effects, overrides.effects)
	end

	return buffUtils.CreateRecord(merged.kind, merged, nil, nil, nil, nil, nil)
end












return buffUtils
