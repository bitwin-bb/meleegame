local require = require(script.Parent.loader).load(script)

local LootServiceUtils = {}

export type LootRarity = string
export type LootState = string
export type LootMetadata = { [string]: any }

export type LootItemConfig = {
	maxStack: number,
	rarity: LootRarity,
}

export type LootSettings = {
	despawnSeconds: number,
	fixedStep: number,
	maxSimulationStepsPerHeartbeat: number,
	lockTo2DPlane: boolean,
	droppedStateDuration: number,
	settleMinDuration: number,
	settleMaxDuration: number,
	settleLinearSpeedThreshold: number,
	settleAngularSpeedThreshold: number,
	settleStableDuration: number,
	dropImpulseForward: number,
	dropImpulseUp: number,
	dropImpulseRandomHorizontal: number,
	dropImpulseRandomUp: number,
	dropAngularVelocity: number,
	dropBounciness: number,
	dropFriction: number,
	dropElasticityWeight: number,
	pickupScanRadius: number,
	collectDistance: number,
	collectOffsetY: number,
	magnetBaseSpeed: number,
	magnetAcceleration: number,
	magnetMaxSpeed: number,
	magnetSpringFrequency: number,
	magnetSpringFrequencyRamp: number,
	magnetSpringFrequencyCloseBoost: number,
	magnetSpringDamping: number,
	magnetSpeedBlend: number,
	magnetCooldownAfterFailedCollect: number,
	ownerLockSeconds: number,
	playerDropOwnerLockSeconds: number,
	playerDropForwardOffset: number,
	playerDropUpOffset: number,
	spawnHeightOffset: number,
	scatterRadiusMin: number,
	scatterRadiusMax: number,
	dropAmountDefault: number,
	dropAmountMin: number,
	dropAmountMax: number,
}

export type LootRollContext = {
	luck: number?,
	quantityMultiplier: number?,
	sourceType: string?,
}

export type LootRollResult = {
	itemId: string,
	amount: number,
	maxStack: number,
	metadata: LootMetadata?,
	rarity: LootRarity,
	sourceType: string,
}

LootServiceUtils.STATE_DROPPED = "Dropped"
LootServiceUtils.STATE_SETTLING = "Settling"
LootServiceUtils.STATE_IDLE = "Idle"
LootServiceUtils.STATE_MAGNETIZED = "Magnetized"
LootServiceUtils.STATE_COLLECTED = "Collected"

LootServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT = "requestDropFromSlot"
LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SELECTED = "requestDropSelectedSlot"

local DEFAULT_RARITY: LootRarity = "Common"
local DEFAULT_SOURCE_TYPE = "Unknown"
local DEFAULT_ITEM_MAX_STACK = 99

local DEFAULT_ITEM_CONFIG: LootItemConfig = {
	maxStack = DEFAULT_ITEM_MAX_STACK,
	rarity = DEFAULT_RARITY,
}

local DEFAULT_SETTINGS: LootSettings = {
	despawnSeconds = 120,
	fixedStep = 1 / 60,
	maxSimulationStepsPerHeartbeat = 4,
	lockTo2DPlane = true,
	droppedStateDuration = 0.05,
	settleMinDuration = 0.12,
	settleMaxDuration = 1.8,
	settleLinearSpeedThreshold = 1.2,
	settleAngularSpeedThreshold = 3.6,
	settleStableDuration = 0.16,
	dropImpulseForward = 26,
	dropImpulseUp = 18,
	dropImpulseRandomHorizontal = 10,
	dropImpulseRandomUp = 6,
	dropAngularVelocity = 10,
	dropBounciness = 0.35,
	dropFriction = 0.55,
	dropElasticityWeight = 1,
	pickupScanRadius = 16,
	collectDistance = 2.05,
	collectOffsetY = 1.35,
	magnetBaseSpeed = 22,
	magnetAcceleration = 110,
	magnetMaxSpeed = 170,
	magnetSpringFrequency = 9.5,
	magnetSpringFrequencyRamp = 6.5,
	magnetSpringFrequencyCloseBoost = 9.5,
	magnetSpringDamping = 1.05,
	magnetSpeedBlend = 0.52,
	magnetCooldownAfterFailedCollect = 0.25,
	ownerLockSeconds = 1.1,
	playerDropOwnerLockSeconds = 0.45,
	playerDropForwardOffset = 3.5,
	playerDropUpOffset = 1.4,
	spawnHeightOffset = 0.35,
	scatterRadiusMin = 0.9,
	scatterRadiusMax = 3.2,
	dropAmountDefault = 1,
	dropAmountMin = 1,
	dropAmountMax = 9999,
}

local ALLOWED_STATE_TRANSITIONS: { [LootState]: { [LootState]: boolean } } = {
	Dropped = {
		Settling = true,
		Collected = true,
	},
	Settling = {
		Idle = true,
		Collected = true,
	},
	Idle = {
		Magnetized = true,
		Collected = true,
	},
	Magnetized = {
		Idle = true,
		Collected = true,
	},
	Collected = {},
}

type CoerceDDropEntry = {
	itemId: string,
	weight: number,
	amountMin: number,
	amountMax: number,
	chance: number,
	luckChanceScale: number,
	luckWeightScale: number,
	metadata: LootMetadata?,
}

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function CoerceString(raw: any, fallback: string?): string?
	local value = trim(raw)
	if value == "" then
		return fallback
	end
	return value
end

local function token(raw: any): string
	local value = string.lower(trim(raw))
	if value == "" then
		return ""
	end
	return string.gsub(value, "[%s_%-%.]+", "")
end

local function CoerceNumber(raw: any, fallback: number, minValue: number?, maxValue: number?): number
	local value = fallback
	if typeof(raw) == "number" and raw == raw then
		value = raw
	elseif typeof(raw) == "string" then
		local parsed = tonumber(trim(raw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

local function CoerceInteger(raw: any, fallback: number, minValue: number, maxValue: number?): number
	local value = math.floor(CoerceNumber(raw, fallback, minValue, maxValue))
	if value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

local function CoerceVector3(raw: any, fallback: Vector3): Vector3
	if typeof(raw) == "Vector3" then
		return raw
	end

	if typeof(raw) ~= "table" then
		return fallback
	end

	local source = raw :: { [string]: any }
	local xRaw = source.x
	if typeof(xRaw) ~= "number" then
		xRaw = source.X
	end
	local yRaw = source.y
	if typeof(yRaw) ~= "number" then
		yRaw = source.Y
	end
	local zRaw = source.z
	if typeof(zRaw) ~= "number" then
		zRaw = source.Z
	end
	if typeof(xRaw) ~= "number" or typeof(yRaw) ~= "number" or typeof(zRaw) ~= "number" then
		return fallback
	end
	return Vector3.new(xRaw, yRaw, zRaw)
end

local function cloneDeepInternal(value: any, seen: { [any]: any }): any
	if typeof(value) ~= "table" then
		return value
	end

	local existing = seen[value]
	if existing ~= nil then
		return existing
	end

	local output = {}
	seen[value] = output
	for key, nestedValue in value do
		local clonedKey = cloneDeepInternal(key, seen)
		output[clonedKey] = cloneDeepInternal(nestedValue, seen)
	end
	return output
end

local function deepEqualInternal(lhs: any, rhs: any, seen: { [any]: any }): boolean
	if lhs == rhs then
		return true
	end
	if typeof(lhs) ~= "table" or typeof(rhs) ~= "table" then
		return false
	end

	local seenRhs = seen[lhs]
	if seenRhs ~= nil then
		return seenRhs == rhs
	end
	seen[lhs] = rhs

	for key, lhsValue in lhs do
		if not deepEqualInternal(lhsValue, rhs[key], seen) then
			return false
		end
	end
	for key in rhs do
		if lhs[key] == nil then
			return false
		end
	end

	return true
end

local function CoerceRarity(raw: any, fallback: LootRarity?): LootRarity
	if raw == "Common" then
		return "Common"
	end
	if raw == "Uncommon" then
		return "Uncommon"
	end
	if raw == "Rare" then
		return "Rare"
	end
	if raw == "Epic" then
		return "Epic"
	end
	if raw == "Legendary" then
		return "Legendary"
	end
	return fallback or DEFAULT_RARITY
end

local function CoerceState(raw: any, fallback: LootState?): LootState
	if raw == "Dropped" then
		return "Dropped"
	end
	if raw == "Settling" then
		return "Settling"
	end
	if raw == "Idle" then
		return "Idle"
	end
	if raw == "Magnetized" then
		return "Magnetized"
	end
	if raw == "Collected" then
		return "Collected"
	end
	return fallback or "Dropped"
end

local function CoerceMetadata(raw: any): LootMetadata?
	if typeof(raw) ~= "table" then
		return nil
	end
	return cloneDeepInternal(raw, {})
end

local function hasDropTable(dropTablesRaw: any, tableIdRaw: any): boolean
	if typeof(dropTablesRaw) ~= "table" then
		return false
	end
	local tableId = CoerceString(tableIdRaw, nil)
	if tableId == nil then
		return false
	end
	return typeof((dropTablesRaw :: { [string]: any })[tableId]) == "table"
end

local function normalizeDropTableAliasMap(dataRaw: any): { [string]: string }
	local output = {}
	if typeof(dataRaw) ~= "table" then
		return output
	end

	local aliasesRaw = (dataRaw :: { [string]: any }).sourceAliases
	if typeof(aliasesRaw) ~= "table" then
		return output
	end

	for aliasRaw, tableIdRaw in aliasesRaw do
		local alias = token(aliasRaw)
		local tableId = CoerceString(tableIdRaw, nil)
		if alias ~= "" and tableId ~= nil then
			output[alias] = tableId
		end
	end

	return output
end

local function CoerceDropEntry(raw: any): CoerceDDropEntry?
	if typeof(raw) ~= "table" then
		return nil
	end

	local source = raw :: { [string]: any }
	local itemId = CoerceString(source.itemId, nil)
	if itemId == nil then
		return nil
	end

	local weight = CoerceNumber(source.weight, 1, 0, 100000)
	if weight <= 0 then
		return nil
	end

	local amountMin = CoerceInteger(source.amountMin, 1, 1, 100000)
	local amountMax = CoerceInteger(source.amountMax, amountMin, amountMin, 100000)

	return {
		itemId = itemId,
		weight = weight,
		amountMin = amountMin,
		amountMax = amountMax,
		chance = CoerceNumber(source.chance, 1, 0, 1),
		luckChanceScale = CoerceNumber(source.luckChanceScale, 0, -4, 4),
		luckWeightScale = CoerceNumber(source.luckWeightScale, 0, -10000, 10000),
		metadata = CoerceMetadata(source.metadata),
	}
end

local function chooseWeightedEntry(entriesRaw: any, randomObject: Random, luck: number): CoerceDDropEntry?
	if typeof(entriesRaw) ~= "table" then
		return nil
	end

	local weightedEntries: { { entry: CoerceDDropEntry, weight: number } } = {}
	local totalWeight = 0
	for _, rawEntry in entriesRaw do
		local entry = CoerceDropEntry(rawEntry)
		if entry == nil then
			continue
		end

		local chance = math.clamp(entry.chance + luck * entry.luckChanceScale, 0, 1)
		if randomObject:NextNumber() > chance then
			continue
		end

		local weight = math.max(0, entry.weight + luck * entry.luckWeightScale)
		if weight <= 0 then
			continue
		end

		totalWeight += weight
		table.insert(weightedEntries, {
			entry = entry,
			weight = weight,
		})
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = randomObject:NextNumber(0, totalWeight)
	local cursor = 0
	for _, candidate in weightedEntries do
		cursor += candidate.weight
		if roll <= cursor then
			return candidate.entry
		end
	end

	return weightedEntries[#weightedEntries].entry
end

local function appendDropResult(
	output: { LootRollResult },
	dataRaw: any,
	entry: CoerceDDropEntry,
	randomObject: Random,
	quantityMultiplier: number,
	sourceType: string
)
	local baseAmount = if entry.amountMax > entry.amountMin
		then randomObject:NextInteger(entry.amountMin, entry.amountMax)
		else entry.amountMin
	local amount = math.max(1, math.floor(baseAmount * quantityMultiplier + 0.5))
	local itemConfig = LootServiceUtils.GetItemConfig(dataRaw, entry.itemId)
	table.insert(output, {
		itemId = entry.itemId,
		amount = amount,
		maxStack = itemConfig.maxStack,
		metadata = cloneDeepInternal(entry.metadata, {}),
		rarity = itemConfig.rarity,
		sourceType = sourceType,
	})
end

local function getDropTable(dataRaw: any, tableIdRaw: any): { [string]: any }?
	if typeof(dataRaw) ~= "table" then
		return nil
	end
	local dropTablesRaw = (dataRaw :: { [string]: any }).dropTables
	if typeof(dropTablesRaw) ~= "table" then
		return nil
	end

	local tableId = CoerceString(tableIdRaw, nil)
	if tableId == nil then
		return nil
	end
	local dropTable = (dropTablesRaw :: { [string]: any })[tableId]
	if typeof(dropTable) ~= "table" then
		return nil
	end
	return dropTable
end

local function appendUniqueString(output: { string }, seen: { [string]: boolean }, valueRaw: any)
	local value = CoerceString(valueRaw, nil)
	if value == nil then
		return
	end
	if seen[value] then
		return
	end
	seen[value] = true
	table.insert(output, value)
end

function LootServiceUtils.CoerceString(raw: any, fallback: string?): string?
	return CoerceString(raw, fallback)
end

function LootServiceUtils.Token(raw: any): string
	return token(raw)
end

function LootServiceUtils.CoerceNumber(raw: any, fallback: number, minValue: number?, maxValue: number?): number
	return CoerceNumber(raw, fallback, minValue, maxValue)
end

function LootServiceUtils.CoerceInteger(raw: any, fallback: number, minValue: number, maxValue: number?): number
	return CoerceInteger(raw, fallback, minValue, maxValue)
end

function LootServiceUtils.CoerceVector3(raw: any, fallback: Vector3): Vector3
	return CoerceVector3(raw, fallback)
end

function LootServiceUtils.CoerceRarity(raw: any, fallback: LootRarity?): LootRarity
	return CoerceRarity(raw, fallback)
end

function LootServiceUtils.CoerceState(raw: any, fallback: LootState?): LootState
	return CoerceState(raw, fallback)
end

function LootServiceUtils.CloneDeep(value: any): any
	return cloneDeepInternal(value, {})
end

function LootServiceUtils.DeepEqual(lhs: any, rhs: any): boolean
	return deepEqualInternal(lhs, rhs, {})
end

function LootServiceUtils.GetSettings(dataRaw: any): LootSettings
	local settingsRaw = if typeof(dataRaw) == "table" then (dataRaw :: { [string]: any }).settings else nil
	local settings = if typeof(settingsRaw) == "table" then settingsRaw else {} :: any

	local scatterRadiusMin =
		CoerceNumber((settings :: any).scatterRadiusMin, DEFAULT_SETTINGS.scatterRadiusMin, 0, 100)
	local scatterRadiusMax =
		CoerceNumber((settings :: any).scatterRadiusMax, DEFAULT_SETTINGS.scatterRadiusMax, scatterRadiusMin, 100)

	return {
		despawnSeconds = CoerceNumber((settings :: any).despawnSeconds, DEFAULT_SETTINGS.despawnSeconds, 1, 3600),
		fixedStep = CoerceNumber((settings :: any).fixedStep, DEFAULT_SETTINGS.fixedStep, 1 / 240, 1 / 10),
		maxSimulationStepsPerHeartbeat = CoerceInteger(
			(settings :: any).maxSimulationStepsPerHeartbeat,
			DEFAULT_SETTINGS.maxSimulationStepsPerHeartbeat,
			1,
			16
		),
		lockTo2DPlane = if (settings :: any).lockTo2DPlane == nil
			then DEFAULT_SETTINGS.lockTo2DPlane
			else (settings :: any).lockTo2DPlane == true,
		droppedStateDuration = CoerceNumber(
			(settings :: any).droppedStateDuration,
			DEFAULT_SETTINGS.droppedStateDuration,
			0,
			2
		),
		settleMinDuration = CoerceNumber(
			(settings :: any).settleMinDuration,
			DEFAULT_SETTINGS.settleMinDuration,
			0,
			4
		),
		settleMaxDuration = CoerceNumber(
			(settings :: any).settleMaxDuration,
			DEFAULT_SETTINGS.settleMaxDuration,
			0.05,
			12
		),
		settleLinearSpeedThreshold = CoerceNumber(
			(settings :: any).settleLinearSpeedThreshold,
			DEFAULT_SETTINGS.settleLinearSpeedThreshold,
			0.01,
			100
		),
		settleAngularSpeedThreshold = CoerceNumber(
			(settings :: any).settleAngularSpeedThreshold,
			DEFAULT_SETTINGS.settleAngularSpeedThreshold,
			0.01,
			200
		),
		settleStableDuration = CoerceNumber(
			(settings :: any).settleStableDuration,
			DEFAULT_SETTINGS.settleStableDuration,
			0.01,
			4
		),
		dropImpulseForward = CoerceNumber(
			(settings :: any).dropImpulseForward,
			DEFAULT_SETTINGS.dropImpulseForward,
			0,
			300
		),
		dropImpulseUp = CoerceNumber((settings :: any).dropImpulseUp, DEFAULT_SETTINGS.dropImpulseUp, 0, 300),
		dropImpulseRandomHorizontal = CoerceNumber(
			(settings :: any).dropImpulseRandomHorizontal,
			DEFAULT_SETTINGS.dropImpulseRandomHorizontal,
			0,
			300
		),
		dropImpulseRandomUp = CoerceNumber(
			(settings :: any).dropImpulseRandomUp,
			DEFAULT_SETTINGS.dropImpulseRandomUp,
			0,
			300
		),
		dropAngularVelocity = CoerceNumber(
			(settings :: any).dropAngularVelocity,
			DEFAULT_SETTINGS.dropAngularVelocity,
			0,
			200
		),
		dropBounciness = CoerceNumber((settings :: any).dropBounciness, DEFAULT_SETTINGS.dropBounciness, 0, 1),
		dropFriction = CoerceNumber((settings :: any).dropFriction, DEFAULT_SETTINGS.dropFriction, 0, 1),
		dropElasticityWeight = CoerceNumber(
			(settings :: any).dropElasticityWeight,
			DEFAULT_SETTINGS.dropElasticityWeight,
			0,
			100
		),
		pickupScanRadius = CoerceNumber(
			(settings :: any).pickupScanRadius,
			DEFAULT_SETTINGS.pickupScanRadius,
			0.5,
			400
		),
		collectDistance = CoerceNumber((settings :: any).collectDistance, DEFAULT_SETTINGS.collectDistance, 0.1, 30),
		collectOffsetY = CoerceNumber((settings :: any).collectOffsetY, DEFAULT_SETTINGS.collectOffsetY, 0, 20),
		magnetBaseSpeed = CoerceNumber((settings :: any).magnetBaseSpeed, DEFAULT_SETTINGS.magnetBaseSpeed, 0.1, 400),
		magnetAcceleration = CoerceNumber(
			(settings :: any).magnetAcceleration,
			DEFAULT_SETTINGS.magnetAcceleration,
			0,
			4000
		),
		magnetMaxSpeed = CoerceNumber((settings :: any).magnetMaxSpeed, DEFAULT_SETTINGS.magnetMaxSpeed, 0.1, 5000),
		magnetSpringFrequency = CoerceNumber(
			(settings :: any).magnetSpringFrequency,
			DEFAULT_SETTINGS.magnetSpringFrequency,
			0.01,
			120
		),
		magnetSpringFrequencyRamp = CoerceNumber(
			(settings :: any).magnetSpringFrequencyRamp,
			DEFAULT_SETTINGS.magnetSpringFrequencyRamp,
			0,
			200
		),
		magnetSpringFrequencyCloseBoost = CoerceNumber(
			(settings :: any).magnetSpringFrequencyCloseBoost,
			DEFAULT_SETTINGS.magnetSpringFrequencyCloseBoost,
			0,
			200
		),
		magnetSpringDamping = CoerceNumber(
			(settings :: any).magnetSpringDamping,
			DEFAULT_SETTINGS.magnetSpringDamping,
			0,
			20
		),
		magnetSpeedBlend = CoerceNumber((settings :: any).magnetSpeedBlend, DEFAULT_SETTINGS.magnetSpeedBlend, 0, 1),
		magnetCooldownAfterFailedCollect = CoerceNumber(
			(settings :: any).magnetCooldownAfterFailedCollect,
			DEFAULT_SETTINGS.magnetCooldownAfterFailedCollect,
			0,
			4
		),
		ownerLockSeconds = CoerceNumber(
			(settings :: any).ownerLockSeconds,
			DEFAULT_SETTINGS.ownerLockSeconds,
			0,
			120
		),
		playerDropOwnerLockSeconds = CoerceNumber(
			(settings :: any).playerDropOwnerLockSeconds,
			DEFAULT_SETTINGS.playerDropOwnerLockSeconds,
			0,
			120
		),
		playerDropForwardOffset = CoerceNumber(
			(settings :: any).playerDropForwardOffset,
			DEFAULT_SETTINGS.playerDropForwardOffset,
			0,
			100
		),
		playerDropUpOffset = CoerceNumber(
			(settings :: any).playerDropUpOffset,
			DEFAULT_SETTINGS.playerDropUpOffset,
			0,
			100
		),
		spawnHeightOffset = CoerceNumber(
			(settings :: any).spawnHeightOffset,
			DEFAULT_SETTINGS.spawnHeightOffset,
			-50,
			50
		),
		scatterRadiusMin = scatterRadiusMin,
		scatterRadiusMax = scatterRadiusMax,
		dropAmountDefault = CoerceInteger(
			(settings :: any).dropAmountDefault,
			DEFAULT_SETTINGS.dropAmountDefault,
			1,
			9999
		),
		dropAmountMin = CoerceInteger((settings :: any).dropAmountMin, DEFAULT_SETTINGS.dropAmountMin, 1, 9999),
		dropAmountMax = CoerceInteger((settings :: any).dropAmountMax, DEFAULT_SETTINGS.dropAmountMax, 1, 999999),
	}
end

function LootServiceUtils.GetItemConfig(dataRaw: any, itemIdRaw: any): LootItemConfig
	local itemId = CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return DEFAULT_ITEM_CONFIG
	end
	if typeof(dataRaw) ~= "table" then
		return DEFAULT_ITEM_CONFIG
	end
	local itemsRaw = (dataRaw :: { [string]: any }).items
	if typeof(itemsRaw) ~= "table" then
		return DEFAULT_ITEM_CONFIG
	end
	local configRaw = (itemsRaw :: { [string]: any })[itemId]
	if typeof(configRaw) ~= "table" then
		return DEFAULT_ITEM_CONFIG
	end

	local config = configRaw :: { [string]: any }
	return {
		maxStack = CoerceInteger(config.maxStack, DEFAULT_ITEM_MAX_STACK, 1, 9999),
		rarity = CoerceRarity(config.rarity, DEFAULT_RARITY),
	}
end

function LootServiceUtils.GotRopTableId(dataRaw: any, sourceRaw: any, fallbackRaw: any): string?
	local aliases = normalizeDropTableAliasMap(dataRaw)
	local dropTablesRaw = if typeof(dataRaw) == "table" then (dataRaw :: { [string]: any }).dropTables else nil
	local fallback = CoerceString(fallbackRaw, nil)

	local function GetValue(valueRaw: any): string?
		local value = CoerceString(valueRaw, nil)
		if value == nil then
			return nil
		end
		if hasDropTable(dropTablesRaw, value) then
			return value
		end
		local alias = aliases[token(value)]
		if alias ~= nil and hasDropTable(dropTablesRaw, alias) then
			return alias
		end
		return nil
	end

	if typeof(sourceRaw) == "string" then
		return GetValue(sourceRaw) or GetValue(fallback)
	end

	if typeof(sourceRaw) == "table" then
		local source = sourceRaw :: { [string]: any }
		local direct = GetValue(source.dropTableId)
		if direct ~= nil then
			return direct
		end
		for _, fieldValue in
			{
				source.sourceType,
				source.npcType,
				source.displayName,
				source.name,
				source.itemId,
			}
		do
			local Got = GetValue(fieldValue)
			if Got ~= nil then
				return Got
			end
		end
	end

	return GetValue(fallback)
end

function LootServiceUtils.RollDropTable(
	dataRaw: any,
	dropTableIdRaw: any,
	randomObjectRaw: any,
	contextRaw: any
): { LootRollResult }
	local dropTable = getDropTable(dataRaw, dropTableIdRaw)
	if dropTable == nil then
		return {}
	end

	local randomObject = if typeof(randomObjectRaw) == "Random" then randomObjectRaw :: Random else Random.new()
	local context = if typeof(contextRaw) == "table" then contextRaw else {} :: any
	local luck = CoerceNumber((context :: any).luck, 0, -1, 1)
	local quantityMultiplier = CoerceNumber((context :: any).quantityMultiplier, 1, 0.01, 100)
	local sourceType = CoerceString((context :: any).sourceType, CoerceString((dropTable :: any).sourceType, nil))
		or DEFAULT_SOURCE_TYPE

	local rollsMin = CoerceInteger((dropTable :: any).rollsMin, 1, 0, 100)
	local rollsMax = CoerceInteger((dropTable :: any).rollsMax, rollsMin, rollsMin, 100)
	local rollCount = if rollsMax > rollsMin then randomObject:NextInteger(rollsMin, rollsMax) else rollsMin

	local bonusRollChance = CoerceNumber((dropTable :: any).bonusRollChance, 0, 0, 1)
	local bonusRollChanceFromLuck = CoerceNumber((dropTable :: any).bonusRollChanceFromLuck, 0, 0, 1)
	local maxBonusRolls = CoerceInteger((dropTable :: any).maxBonusRolls, 0, 0, 12)
	local effectiveBonusChance = math.clamp(bonusRollChance + luck * bonusRollChanceFromLuck, 0, 1)
	local bonusRolls = 0
	while bonusRolls < maxBonusRolls and randomObject:NextNumber() <= effectiveBonusChance do
		bonusRolls += 1
	end

	local output = {}
	local guaranteedDropsRaw = (dropTable :: any).guaranteedDrops
	if typeof(guaranteedDropsRaw) == "table" then
		for _, rawEntry in guaranteedDropsRaw do
			local entry = CoerceDropEntry(rawEntry)
			if entry ~= nil then
				appendDropResult(output, dataRaw, entry, randomObject, quantityMultiplier, sourceType)
			end
		end
	end

	local totalRolls = rollCount + bonusRolls
	for _ = 1, totalRolls do
		local entry = chooseWeightedEntry((dropTable :: any).entries, randomObject, luck)
		if entry == nil then
			continue
		end

		appendDropResult(output, dataRaw, entry, randomObject, quantityMultiplier, sourceType)
	end

	return output
end

function LootServiceUtils.GotRopAmount(amountRaw: any, fallbackAmountRaw: any): number
	local fallbackAmount = CoerceInteger(
		fallbackAmountRaw,
		DEFAULT_SETTINGS.dropAmountDefault,
		DEFAULT_SETTINGS.dropAmountMin,
		DEFAULT_SETTINGS.dropAmountMax
	)
	return CoerceInteger(amountRaw, fallbackAmount, DEFAULT_SETTINGS.dropAmountMin, DEFAULT_SETTINGS.dropAmountMax)
end

function LootServiceUtils.GetItemNameCandidates(dataRaw: any, itemIdRaw: any): { string }
	local candidates = {}
	local seen = {}

	local itemId = CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return candidates
	end

	appendUniqueString(candidates, seen, itemId)
	appendUniqueString(candidates, seen, token(itemId))
	appendUniqueString(candidates, seen, string.lower(itemId))

	if typeof(dataRaw) ~= "table" then
		return candidates
	end

	local aliasesRoot = (dataRaw :: { [string]: any }).itemAssetAliases
	if typeof(aliasesRoot) ~= "table" then
		return candidates
	end

	local aliasesRaw = (aliasesRoot :: { [string]: any })[itemId]
	if typeof(aliasesRaw) == "table" then
		for _, aliasRaw in aliasesRaw do
			appendUniqueString(candidates, seen, aliasRaw)
		end
	end

	return candidates
end

function LootServiceUtils.CreateLootId(randomObjectRaw: any, itemIdRaw: any): string
	local randomObject = if typeof(randomObjectRaw) == "Random" then randomObjectRaw :: Random else Random.new()
	local itemToken = token(itemIdRaw)
	if itemToken == "" then
		itemToken = "loot"
	end
	local timeToken = math.floor(os.clock() * 1000)
	local randomToken = randomObject:NextInteger(1000, 999999)
	return ("%s_%d_%d"):format(itemToken, timeToken, randomToken)
end

function LootServiceUtils.IsAllowedStateTransition(currentRaw: any, nextRaw: any): boolean
	local currentState = CoerceState(currentRaw, "Dropped")
	local nextState = CoerceState(nextRaw, currentState)
	if currentState == nextState then
		return true
	end
	local allowedNext = ALLOWED_STATE_TRANSITIONS[currentState]
	return allowedNext[nextState] == true
end

return LootServiceUtils
