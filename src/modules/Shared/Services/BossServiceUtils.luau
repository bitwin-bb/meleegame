--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Plane = require(script:FindFirstAncestor("game").Shared.Modules.Math.Plane)
local Proj = require(script:FindFirstAncestor("game").Shared.Modules.Math.Proj)
local Vec = require(script:FindFirstAncestor("game").Shared.Modules.Math.Vec)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local BossServiceUtils = {}

export type BossId = "EyeOfCthulhu"
export type BossEncounterState =
	"Dormant"
	| "SpawnIntro"
	| "Phase1Hover"
	| "Phase1ServantBurst"
	| "Phase1ChargeWindup"
	| "Phase1Charge"
	| "Phase1Recovery"
	| "Transform"
	| "Phase2HoverIdle"
	| "Phase2Hover"
	| "Phase2ChargeWindup"
	| "Phase2Charge"
	| "Phase2Recovery"
	| "Phase2RapidChain"
	| "Death"
	| "Despawn"

export type BossSpawnSource = "ManualSummon" | "NaturalSpawn" | "DebugCommand"

export type BossRegistryEntry = {
	id: BossId,
	displayName: string,
	controllerId: string,
	presentationId: string,
	modelHierarchy: string,
	encounterChannel: string,
	manualSummonTokens: { string },
	supportsNaturalSpawn: boolean,
	nightOnlySummon: boolean,
	naturalSpawnAnnouncement: string?,
	singletonPerChannel: boolean,
}

export type BossPresentationState = {
	phaseModel: string,
	isHurtWindowActive: boolean,
	isRoaring: boolean,
	isTransforming: boolean,
	isDying: boolean,
	isDespawning: boolean,
	damagePulseToken: number,
	dashPulseToken: number,
	roarPulseToken: number,
	transformPulseToken: number,
	deathPulseToken: number,
	servantPulseToken: number,
}

export type BossMotionState = {
	state: string,
	position: Vector3?,
	velocity: Vector3,
	hoverAnchor: Vector3?,
	distanceToAnchor: number?,
	lockedChargeDirection: Vector3?,
	chargeTimeRemaining: number?,
	motionOwner: string,
	localPresentationOffset: Vector3?,
}

export type BossSnapshot = {
	id: string,
	bossId: BossId,
	displayName: string,
	encounterChannel: string,
	state: BossEncounterState,
	phase: number,
	hp: number,
	maxHp: number,
	isAlive: boolean,
	position: Vector3?,
	velocity: Vector3,
	facing: Vector3,
	stateTime: number,
	chargeIndex: number,
	targetUserId: number?,
	updatedAt: number,
	lastReason: string,
	presentation: BossPresentationState,
	motion: BossMotionState,
}

export type BossServiceState = {
	byId: { [string]: BossSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

export type BossSpawnRequest = {
	bossId: BossId,
	targetPlayer: Player?,
	spawnSource: BossSpawnSource,
	encounterChannel: string?,
	spawnPosition: Vector3?,
	planeX: number?,
	simulationSpeed: number?,
	aggressiveness: number?,
	expertBehaviorEnabled: boolean?,
}

BossServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
BossServiceUtils.NETWORK_METHOD_REQUEST_MANUAL_SUMMON = "requestManualSummon"
BossServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
BossServiceUtils.CLIENT_METHOD_ON_BOSS_ADDED = "onBossAdded"
BossServiceUtils.CLIENT_METHOD_ON_BOSS_UPDATED = "onBossUpdated"
BossServiceUtils.CLIENT_METHOD_ON_BOSS_REMOVED = "onBossRemoved"
BossServiceUtils.CLIENT_METHOD_ON_ANNOUNCEMENT = "onAnnouncement"
BossServiceUtils.RUNTIME_ID_ATTRIBUTE = "BossRuntimeId"
BossServiceUtils.RUNTIME_BOSS_ID_ATTRIBUTE = "BossRuntimeBossId"
BossServiceUtils.RUNTIME_DISPLAY_NAME_ATTRIBUTE = "BossRuntimeDisplayName"
BossServiceUtils.RUNTIME_CHANNEL_ATTRIBUTE = "BossRuntimeChannel"
BossServiceUtils.NIGHT_START_CLOCK_TIME = 19.5
BossServiceUtils.DAY_START_CLOCK_TIME = 4.5
BossServiceUtils.DEFAULT_STATE_PUSH_INTERVAL = 0.1
BossServiceUtils.DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL = 0.5

local DEFAULT_PRESENTATION: BossPresentationState = {
	phaseModel = "Phase1",
	isHurtWindowActive = false,
	isRoaring = false,
	isTransforming = false,
	isDying = false,
	isDespawning = false,
	damagePulseToken = 0,
	dashPulseToken = 0,
	roarPulseToken = 0,
	transformPulseToken = 0,
	deathPulseToken = 0,
	servantPulseToken = 0,
}

local DEFAULT_MOTION: BossMotionState = {
	state = "Dormant",
	position = nil,
	velocity = Vector3.zero,
	hoverAnchor = nil,
	distanceToAnchor = nil,
	lockedChargeDirection = nil,
	chargeTimeRemaining = nil,
	motionOwner = "None",
	localPresentationOffset = nil,
}

local EYE_OF_CTHULHU_REGISTRY_ENTRY: BossRegistryEntry = {
	id = "EyeOfCthulhu",
	displayName = "Eye of Cthulhu",
	controllerId = "EyeOfCthulhu",
	presentationId = "EyeOfCthulhu",
	modelHierarchy = "EyeOfCthulhu",
	encounterChannel = "world.eyeOfCthulhu",
	manualSummonTokens = { "eye", "eoc", "eyeofcthulhu" },
	supportsNaturalSpawn = true,
	nightOnlySummon = true,
	naturalSpawnAnnouncement = "You feel an evil presence watching you...",
	singletonPerChannel = true,
}

local REGISTRY_BY_ID: { [BossId]: BossRegistryEntry } = {
	EyeOfCthulhu = EYE_OF_CTHULHU_REGISTRY_ENTRY,
}

local REGISTRY_BY_TOKEN = {
	eye = EYE_OF_CTHULHU_REGISTRY_ENTRY,
	eoc = EYE_OF_CTHULHU_REGISTRY_ENTRY,
	eyeofcthulhu = EYE_OF_CTHULHU_REGISTRY_ENTRY,
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeToken(valueRaw: any): string
	return string.lower(string.gsub(trim(valueRaw), "[%s_%-%.]", ""))
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(trim(valueRaw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function clonePresentation(source: BossPresentationState): BossPresentationState
	return {
		phaseModel = source.phaseModel,
		isHurtWindowActive = source.isHurtWindowActive,
		isRoaring = source.isRoaring,
		isTransforming = source.isTransforming,
		isDying = source.isDying,
		isDespawning = source.isDespawning,
		damagePulseToken = source.damagePulseToken,
		dashPulseToken = source.dashPulseToken,
		roarPulseToken = source.roarPulseToken,
		transformPulseToken = source.transformPulseToken,
		deathPulseToken = source.deathPulseToken,
		servantPulseToken = source.servantPulseToken,
	}
end

local function cloneMotionState(source: BossMotionState): BossMotionState
	return {
		state = source.state,
		position = source.position,
		velocity = source.velocity,
		hoverAnchor = source.hoverAnchor,
		distanceToAnchor = source.distanceToAnchor,
		lockedChargeDirection = source.lockedChargeDirection,
		chargeTimeRemaining = source.chargeTimeRemaining,
		motionOwner = source.motionOwner,
		localPresentationOffset = source.localPresentationOffset,
	}
end

local function sanitizeBossId(bossIdRaw: any, fallback: BossId?): BossId?
	if bossIdRaw == "EyeOfCthulhu" then
		return "EyeOfCthulhu"
	end

	local entry = REGISTRY_BY_TOKEN[normalizeToken(bossIdRaw)]
	if entry ~= nil then
		return entry.id
	end
	return fallback
end

local function sanitizeStateName(stateRaw: any, fallback: BossEncounterState): BossEncounterState
	if stateRaw == "Dormant"
		or stateRaw == "SpawnIntro"
		or stateRaw == "Phase1Hover"
		or stateRaw == "Phase1ServantBurst"
		or stateRaw == "Phase1ChargeWindup"
		or stateRaw == "Phase1Charge"
		or stateRaw == "Phase1Recovery"
		or stateRaw == "Transform"
		or stateRaw == "Phase2HoverIdle"
		or stateRaw == "Phase2Hover"
		or stateRaw == "Phase2ChargeWindup"
		or stateRaw == "Phase2Charge"
		or stateRaw == "Phase2Recovery"
		or stateRaw == "Phase2RapidChain"
		or stateRaw == "Death"
		or stateRaw == "Despawn" then
		return stateRaw
	end
	return fallback
end

local function cloneSnapshot(snapshot: BossSnapshot): BossSnapshot
	return {
		id = snapshot.id,
		bossId = snapshot.bossId,
		displayName = snapshot.displayName,
		encounterChannel = snapshot.encounterChannel,
		state = snapshot.state,
		phase = snapshot.phase,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		isAlive = snapshot.isAlive,
		position = snapshot.position,
		velocity = snapshot.velocity,
		facing = snapshot.facing,
		stateTime = snapshot.stateTime,
		chargeIndex = snapshot.chargeIndex,
		targetUserId = snapshot.targetUserId,
		updatedAt = snapshot.updatedAt,
		lastReason = snapshot.lastReason,
		presentation = clonePresentation(snapshot.presentation),
		motion = cloneMotionState(snapshot.motion),
	}
end

function BossServiceUtils.Trim(valueRaw: any): string
	return trim(valueRaw)
end

function BossServiceUtils.NormalizeToken(valueRaw: any): string
	return normalizeToken(valueRaw)
end

function BossServiceUtils.SanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	return sanitizeNumber(valueRaw, fallback, minimum, maximum)
end

function BossServiceUtils.SanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	return sanitizeBoolean(valueRaw, fallback)
end

function BossServiceUtils.CreateDefaultPresentation(): BossPresentationState
	return clonePresentation(DEFAULT_PRESENTATION)
end

function BossServiceUtils.CreateDefaultMotionState(): BossMotionState
	return cloneMotionState(DEFAULT_MOTION)
end

function BossServiceUtils.SanitizePresentation(
	presentationRaw: any,
	fallbackRaw: BossPresentationState?
): BossPresentationState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else DEFAULT_PRESENTATION
	local source = if typeof(presentationRaw) == "table" then presentationRaw else {}

	return {
		phaseModel = if typeof((source :: any).phaseModel) == "string" and (source :: any).phaseModel ~= ""
			then (source :: any).phaseModel
			else fallback.phaseModel,
		isHurtWindowActive = sanitizeBoolean((source :: any).isHurtWindowActive, fallback.isHurtWindowActive),
		isRoaring = sanitizeBoolean((source :: any).isRoaring, fallback.isRoaring),
		isTransforming = sanitizeBoolean((source :: any).isTransforming, fallback.isTransforming),
		isDying = sanitizeBoolean((source :: any).isDying, fallback.isDying),
		isDespawning = sanitizeBoolean((source :: any).isDespawning, fallback.isDespawning),
		damagePulseToken = math.floor(sanitizeNumber((source :: any).damagePulseToken, fallback.damagePulseToken, 0, 10 ^ 9)),
		dashPulseToken = math.floor(sanitizeNumber((source :: any).dashPulseToken, fallback.dashPulseToken, 0, 10 ^ 9)),
		roarPulseToken = math.floor(sanitizeNumber((source :: any).roarPulseToken, fallback.roarPulseToken, 0, 10 ^ 9)),
		transformPulseToken = math.floor(
			sanitizeNumber((source :: any).transformPulseToken, fallback.transformPulseToken, 0, 10 ^ 9)
		),
		deathPulseToken = math.floor(sanitizeNumber((source :: any).deathPulseToken, fallback.deathPulseToken, 0, 10 ^ 9)),
		servantPulseToken = math.floor(
			sanitizeNumber((source :: any).servantPulseToken, fallback.servantPulseToken, 0, 10 ^ 9)
		),
	}
end

function BossServiceUtils.SanitizeMotionState(motionRaw: any, fallbackRaw: BossMotionState?): BossMotionState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else DEFAULT_MOTION
	local source = if typeof(motionRaw) == "table" then motionRaw else {}

	return {
		state = if typeof((source :: any).state) == "string" and (source :: any).state ~= ""
			then (source :: any).state
			else fallback.state,
		position = if typeof((source :: any).position) == "Vector3"
			then (source :: any).position
			else fallback.position,
		velocity = if typeof((source :: any).velocity) == "Vector3"
			then (source :: any).velocity
			else fallback.velocity,
		hoverAnchor = if typeof((source :: any).hoverAnchor) == "Vector3"
			then (source :: any).hoverAnchor
			else fallback.hoverAnchor,
		distanceToAnchor = if typeof((source :: any).distanceToAnchor) == "number"
			then sanitizeNumber((source :: any).distanceToAnchor, 0, 0, 10 ^ 6)
			else fallback.distanceToAnchor,
		lockedChargeDirection = if typeof((source :: any).lockedChargeDirection) == "Vector3"
			then (source :: any).lockedChargeDirection
			else fallback.lockedChargeDirection,
		chargeTimeRemaining = if typeof((source :: any).chargeTimeRemaining) == "number"
			then sanitizeNumber((source :: any).chargeTimeRemaining, 0, 0, 10 ^ 6)
			else fallback.chargeTimeRemaining,
		motionOwner = if typeof((source :: any).motionOwner) == "string" and (source :: any).motionOwner ~= ""
			then (source :: any).motionOwner
			else fallback.motionOwner,
		localPresentationOffset = if typeof((source :: any).localPresentationOffset) == "Vector3"
			then (source :: any).localPresentationOffset
			else fallback.localPresentationOffset,
	}
end

function BossServiceUtils.SanitizeSnapshot(snapshotRaw: any, fallbackRaw: BossSnapshot?): BossSnapshot?
	if typeof(snapshotRaw) ~= "table" then
		return fallbackRaw
	end

	local fallback = fallbackRaw
	local source = snapshotRaw :: { [string]: any }
	local id = trim(source.id)
	if id == "" then
		return fallback
	end

	local bossId = sanitizeBossId(source.bossId, if fallback ~= nil then fallback.bossId else nil)
	if bossId == nil then
		return fallback
	end

	local fallbackMaxHp = if fallback ~= nil then fallback.maxHp else 1
	local maxHp = math.max(1, sanitizeNumber(source.maxHp, fallbackMaxHp, 1, 10 ^ 9))
	local fallbackHp = if fallback ~= nil then fallback.hp else maxHp
	local hp = math.clamp(sanitizeNumber(source.hp, fallbackHp, 0, maxHp), 0, maxHp)
	local state = sanitizeStateName(source.state, if fallback ~= nil then fallback.state else "Dormant")
	local isAlive = sanitizeBoolean(source.isAlive, if fallback ~= nil then fallback.isAlive else state ~= "Death")
	if state == "Death" then
		isAlive = false
		hp = 0
	end

	return {
		id = id,
		bossId = bossId,
		displayName = if typeof(source.displayName) == "string" and source.displayName ~= ""
			then source.displayName
			else if fallback ~= nil then fallback.displayName else id,
		encounterChannel = if typeof(source.encounterChannel) == "string" and source.encounterChannel ~= ""
			then source.encounterChannel
			else if fallback ~= nil then fallback.encounterChannel else REGISTRY_BY_ID[bossId].encounterChannel,
		state = state,
		phase = math.max(0, math.floor(sanitizeNumber(source.phase, if fallback ~= nil then fallback.phase else 0, 0, 16))),
		hp = hp,
		maxHp = maxHp,
		isAlive = isAlive,
		position = if typeof(source.position) == "Vector3"
			then source.position
			else if fallback ~= nil then fallback.position else nil,
		velocity = if typeof(source.velocity) == "Vector3"
			then source.velocity
			else if fallback ~= nil then fallback.velocity else Vector3.zero,
		facing = if typeof(source.facing) == "Vector3"
			then source.facing
			else if fallback ~= nil then fallback.facing else Vector3.zAxis,
		stateTime = sanitizeNumber(source.stateTime, if fallback ~= nil then fallback.stateTime else 0, 0, 10 ^ 9),
		chargeIndex = math.max(
			0,
			math.floor(sanitizeNumber(source.chargeIndex, if fallback ~= nil then fallback.chargeIndex else 0, 0, 1000))
		),
		targetUserId = if typeof(source.targetUserId) == "number"
			then math.floor(source.targetUserId)
			else if fallback ~= nil then fallback.targetUserId else nil,
		updatedAt = sanitizeNumber(source.updatedAt, if fallback ~= nil then fallback.updatedAt else os.clock(), 0, 10 ^ 12),
		lastReason = if typeof(source.lastReason) == "string"
			then source.lastReason
			else if fallback ~= nil then fallback.lastReason else "unknown",
		presentation = BossServiceUtils.SanitizePresentation(
			source.presentation,
			if fallback ~= nil then fallback.presentation else DEFAULT_PRESENTATION
		),
		motion = BossServiceUtils.SanitizeMotionState(
			source.motion,
			if fallback ~= nil then fallback.motion else DEFAULT_MOTION
		),
	}
end

function BossServiceUtils.CreateDefaultState(): BossServiceState
	return {
		byId = {},
		orderedIds = {},
		updatedAt = os.clock(),
	}
end

function BossServiceUtils.CloneState(state: BossServiceState): BossServiceState
	return {
		byId = Sift.Dictionary.map(state.byId, function(snapshot: BossSnapshot): BossSnapshot
			return cloneSnapshot(snapshot)
		end),
		orderedIds = Sift.Array.copy(state.orderedIds),
		updatedAt = state.updatedAt,
	}
end

local function pushSanitizedSnapshot(
	nextState: BossServiceState,
	runtimeId: string,
	snapshotRaw: any,
	fallbackSnapshot: BossSnapshot?
)
	local snapshot = BossServiceUtils.SanitizeSnapshot(snapshotRaw, fallbackSnapshot)
	if snapshot == nil then
		return
	end

	nextState.byId[runtimeId] = snapshot
	nextState.orderedIds[#nextState.orderedIds + 1] = runtimeId
end

function BossServiceUtils.SanitizeState(stateRaw: any, fallbackRaw: BossServiceState?): BossServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else BossServiceUtils.CreateDefaultState()
	local nextState = BossServiceUtils.CreateDefaultState()
	if typeof(stateRaw) ~= "table" then
		nextState.updatedAt = fallback.updatedAt
		return nextState
	end

	local source = stateRaw :: { [string]: any }
	local byIdRaw = (source :: any).byId
	if typeof(byIdRaw) == "table" then
		local orderedIdsRaw = if typeof((source :: any).orderedIds) == "table" then (source :: any).orderedIds else nil
		local seenIds = {}
		if orderedIdsRaw ~= nil then
			for _, runtimeId in orderedIdsRaw do
				if typeof(runtimeId) ~= "string" or runtimeId == "" or seenIds[runtimeId] == true then
					continue
				end
				seenIds[runtimeId] = true

				local snapshotRaw = (byIdRaw :: any)[runtimeId]
				local fallbackSnapshot = fallback.byId[runtimeId]
				pushSanitizedSnapshot(nextState, runtimeId, snapshotRaw, fallbackSnapshot)
			end
		end

		for runtimeId, snapshotRaw in byIdRaw do
			if typeof(runtimeId) ~= "string" or runtimeId == "" or seenIds[runtimeId] == true then
				continue
			end
			local fallbackSnapshot = fallback.byId[runtimeId]
			pushSanitizedSnapshot(nextState, runtimeId, snapshotRaw, fallbackSnapshot)
		end
	elseif typeof((source :: any)[1]) == "table" then
		for _, snapshotRaw in source do
			local snapshot = BossServiceUtils.SanitizeSnapshot(snapshotRaw, nil)
			if snapshot ~= nil then
				nextState.byId[snapshot.id] = snapshot
				nextState.orderedIds[#nextState.orderedIds + 1] = snapshot.id
			end
		end
	end

	nextState.updatedAt = sanitizeNumber((source :: any).updatedAt, os.clock(), 0, 10 ^ 12)
	return nextState
end

function BossServiceUtils.GetRegistryEntryById(bossIdRaw: any): BossRegistryEntry?
	local bossId = sanitizeBossId(bossIdRaw, nil)
	if bossId == nil then
		return nil
	end
	return REGISTRY_BY_ID[bossId]
end

function BossServiceUtils.GetRegistryEntryByToken(tokenRaw: any): BossRegistryEntry?
	return REGISTRY_BY_TOKEN[normalizeToken(tokenRaw)]
end

function BossServiceUtils.GetRegistryEntries(): { BossRegistryEntry }
	return { EYE_OF_CTHULHU_REGISTRY_ENTRY }
end

function BossServiceUtils.SanitizeSpawnRequest(requestRaw: any, fallbackRaw: BossSpawnRequest?): BossSpawnRequest?
	if typeof(requestRaw) ~= "table" then
		return fallbackRaw
	end

	local fallback = fallbackRaw
	local source = requestRaw :: { [string]: any }
	local bossId = sanitizeBossId(source.bossId, if fallback ~= nil then fallback.bossId else nil)
	if bossId == nil then
		return fallback
	end

	local registryEntry = REGISTRY_BY_ID[bossId]
	local targetPlayer = if typeof(source.targetPlayer) == "Instance" and source.targetPlayer:IsA("Player")
		then source.targetPlayer
		else if fallback ~= nil then fallback.targetPlayer else nil

	local spawnSource = source.spawnSource
	if spawnSource ~= "ManualSummon" and spawnSource ~= "NaturalSpawn" and spawnSource ~= "DebugCommand" then
		spawnSource = if fallback ~= nil then fallback.spawnSource else "ManualSummon"
	end

	return {
		bossId = bossId,
		targetPlayer = targetPlayer,
		spawnSource = spawnSource,
		encounterChannel = if typeof(source.encounterChannel) == "string" and source.encounterChannel ~= ""
			then source.encounterChannel
			else if fallback ~= nil and fallback.encounterChannel ~= nil
				then fallback.encounterChannel
				else registryEntry.encounterChannel,
		spawnPosition = if typeof(source.spawnPosition) == "Vector3"
			then source.spawnPosition
			else if fallback ~= nil then fallback.spawnPosition else nil,
		planeX = if typeof(source.planeX) == "number"
			then source.planeX
			else if fallback ~= nil then fallback.planeX else nil,
		simulationSpeed = if source.simulationSpeed ~= nil
			then sanitizeNumber(source.simulationSpeed, 1, 0.05, 5)
			else if fallback ~= nil then fallback.simulationSpeed else nil,
		aggressiveness = if source.aggressiveness ~= nil
			then sanitizeNumber(source.aggressiveness, 1, 0.1, 3)
			else if fallback ~= nil then fallback.aggressiveness else nil,
		expertBehaviorEnabled = if source.expertBehaviorEnabled ~= nil
			then sanitizeBoolean(source.expertBehaviorEnabled, true)
			else if fallback ~= nil then fallback.expertBehaviorEnabled else nil,
	}
end

function BossServiceUtils.ApplyRuntimeModelAttributes(
	modelRaw: any,
	runtimeIdRaw: any,
	bossIdRaw: any,
	displayNameRaw: any,
	channelRaw: any
): boolean
	if typeof(modelRaw) ~= "Instance" or not modelRaw:IsA("Model") then
		return false
	end

	local runtimeId = trim(runtimeIdRaw)
	local bossId = sanitizeBossId(bossIdRaw, nil)
	if runtimeId == "" or bossId == nil then
		return false
	end

	modelRaw:SetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE, runtimeId)
	modelRaw:SetAttribute(BossServiceUtils.RUNTIME_BOSS_ID_ATTRIBUTE, bossId)
	TagBinder.applyTag(modelRaw, TagBinder.Tags.Boss)
	TagBinder.applyTag(modelRaw, TagBinder.Tags.Gore_Boss)
	if bossId == "EyeOfCthulhu" then
		TagBinder.applyTag(modelRaw, TagBinder.Tags.Boss_EyeOfCthulhu)
	end

	local displayName = trim(displayNameRaw)
	if displayName ~= "" then
		modelRaw:SetAttribute(BossServiceUtils.RUNTIME_DISPLAY_NAME_ATTRIBUTE, displayName)
	end

	local encounterChannel = trim(channelRaw)
	if encounterChannel ~= "" then
		modelRaw:SetAttribute(BossServiceUtils.RUNTIME_CHANNEL_ATTRIBUTE, encounterChannel)
	end

	return true
end

function BossServiceUtils.ResolveRuntimeModelFromInstance(instanceRaw: any): Model?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local cursor: Instance? = instanceRaw
	while cursor ~= nil do
		if cursor:IsA("Model") then
			local runtimeId = cursor:GetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE)
			if typeof(runtimeId) == "string" and runtimeId ~= "" then
				return cursor
			end
		end
		cursor = cursor.Parent
	end

	return nil
end

function BossServiceUtils.ResolveRuntimeIdFromInstance(instanceRaw: any): string?
	local model = BossServiceUtils.ResolveRuntimeModelFromInstance(instanceRaw)
	if model == nil then
		return nil
	end

	local runtimeId = model:GetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE)
	if typeof(runtimeId) == "string" and runtimeId ~= "" then
		return runtimeId
	end
	return nil
end

function BossServiceUtils.ResolveBossIdFromInstance(instanceRaw: any): BossId?
	local model = BossServiceUtils.ResolveRuntimeModelFromInstance(instanceRaw)
	if model == nil then
		return nil
	end

	return sanitizeBossId(model:GetAttribute(BossServiceUtils.RUNTIME_BOSS_ID_ATTRIBUTE), nil)
end

function BossServiceUtils.FindFirstDescendantByNormalizedName(root: Instance?, tokensRaw: { string }): Instance?
	if root == nil then
		return nil
	end

	local tokens = {}
	for _, token in tokensRaw do
		tokens[normalizeToken(token)] = true
	end

	for _, descendant in root:GetDescendants() do
		if tokens[normalizeToken(descendant.Name)] == true then
			return descendant
		end
	end

	return nil
end

function BossServiceUtils.ResolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local preferred = { "RootPart", "HumanoidRootPart" }
	for _, partName in preferred do
		local direct = model:FindFirstChild(partName)
		if direct ~= nil and direct:IsA("BasePart") then
			return direct
		end
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

function BossServiceUtils.ResolveCharacterRootPart(playerRaw: any): BasePart?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local character = playerRaw.Character
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	return BossServiceUtils.ResolveRootPart(character)
end

function BossServiceUtils.ResolveCharacterVelocity(playerRaw: any): Vector3
	local rootPart = BossServiceUtils.ResolveCharacterRootPart(playerRaw)
	if rootPart == nil then
		return Vector3.zero
	end
	return rootPart.AssemblyLinearVelocity
end

function BossServiceUtils.ProjectPositionToPlaneX(position: Vector3, planeXRaw: any): Vector3
	if typeof(planeXRaw) ~= "number" or planeXRaw ~= planeXRaw then
		return position
	end
	local plane = Plane.fromPointNormal(Vector3.new(planeXRaw, 0, 0), Vector3.xAxis)
	return Plane.projectPoint(plane, position)
end

function BossServiceUtils.ProjectVectorToPlaneX(vector: Vector3, planeXRaw: any): Vector3
	if typeof(planeXRaw) ~= "number" or planeXRaw ~= planeXRaw then
		return vector
	end
	return Proj.ontoPlane(vector, Vector3.xAxis)
end

function BossServiceUtils.MoveTowardsVector(current: Vector3, target: Vector3, maxDeltaRaw: any): Vector3
	local maxDelta = sanitizeNumber(maxDeltaRaw, 0, 0, nil)
	return Vec.moveTowards(current, target, maxDelta)
end

function BossServiceUtils.ComputeFacingVector(_position: Vector3, desiredDirectionRaw: any, fallbackRaw: Vector3?): Vector3
	local desiredDirection = if typeof(desiredDirectionRaw) == "Vector3" then desiredDirectionRaw else Vector3.zero
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.zAxis
	local fallbackUnit = Vec.unit(fallback, Vector3.zAxis)
	return Vec.unit(desiredDirection, fallbackUnit)
end

function BossServiceUtils.LookCFrame(position: Vector3, facingRaw: any): CFrame
	local facing = BossServiceUtils.ComputeFacingVector(position, facingRaw, Vector3.zAxis)
	return CFrame.lookAt(position, position + facing, Vector3.yAxis)
end

function BossServiceUtils.IsNightClockTime(clockTimeRaw: any): boolean
	local clockTime = sanitizeNumber(clockTimeRaw, 12, 0, 24)
	return clockTime >= BossServiceUtils.NIGHT_START_CLOCK_TIME or clockTime < BossServiceUtils.DAY_START_CLOCK_TIME
end

function BossServiceUtils.DidClockPass(previousClockTimeRaw: any, nextClockTimeRaw: any, thresholdRaw: any): boolean
	local previousClockTime = sanitizeNumber(previousClockTimeRaw, 0, 0, 24)
	local nextClockTime = sanitizeNumber(nextClockTimeRaw, previousClockTime, 0, 24)
	local threshold = sanitizeNumber(thresholdRaw, 0, 0, 24)

	if previousClockTime <= nextClockTime then
		return previousClockTime < threshold and nextClockTime >= threshold
	end

	if previousClockTime < threshold then
		return true
	end
	return nextClockTime >= threshold
end

function BossServiceUtils.ResolveTargetPlayerUserId(playerRaw: any): number?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end
	return playerRaw.UserId
end

function BossServiceUtils.IsPlayerAlive(playerRaw: any): boolean
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return false
	end

	local character = playerRaw.Character
	if character == nil then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

BossServiceUtils.trim = BossServiceUtils.Trim
BossServiceUtils.normalizeToken = BossServiceUtils.NormalizeToken
BossServiceUtils.sanitizeNumber = BossServiceUtils.SanitizeNumber
BossServiceUtils.sanitizeBoolean = BossServiceUtils.SanitizeBoolean
BossServiceUtils.createDefaultPresentation = BossServiceUtils.CreateDefaultPresentation
BossServiceUtils.createDefaultMotionState = BossServiceUtils.CreateDefaultMotionState
BossServiceUtils.sanitizePresentation = BossServiceUtils.SanitizePresentation
BossServiceUtils.sanitizeMotionState = BossServiceUtils.SanitizeMotionState
BossServiceUtils.sanitizeSnapshot = BossServiceUtils.SanitizeSnapshot
BossServiceUtils.createDefaultState = BossServiceUtils.CreateDefaultState
BossServiceUtils.cloneState = BossServiceUtils.CloneState
BossServiceUtils.sanitizeState = BossServiceUtils.SanitizeState
BossServiceUtils.getRegistryEntryById = BossServiceUtils.GetRegistryEntryById
BossServiceUtils.getRegistryEntryByToken = BossServiceUtils.GetRegistryEntryByToken
BossServiceUtils.getRegistryEntries = BossServiceUtils.GetRegistryEntries
BossServiceUtils.sanitizeSpawnRequest = BossServiceUtils.SanitizeSpawnRequest
BossServiceUtils.applyRuntimeModelAttributes = BossServiceUtils.ApplyRuntimeModelAttributes
BossServiceUtils.resolveRuntimeModelFromInstance = BossServiceUtils.ResolveRuntimeModelFromInstance
BossServiceUtils.resolveRuntimeIdFromInstance = BossServiceUtils.ResolveRuntimeIdFromInstance
BossServiceUtils.resolveBossIdFromInstance = BossServiceUtils.ResolveBossIdFromInstance
BossServiceUtils.findFirstDescendantByNormalizedName = BossServiceUtils.FindFirstDescendantByNormalizedName
BossServiceUtils.resolveRootPart = BossServiceUtils.ResolveRootPart
BossServiceUtils.resolveCharacterRootPart = BossServiceUtils.ResolveCharacterRootPart
BossServiceUtils.resolveCharacterVelocity = BossServiceUtils.ResolveCharacterVelocity
BossServiceUtils.projectPositionToPlaneX = BossServiceUtils.ProjectPositionToPlaneX
BossServiceUtils.projectVectorToPlaneX = BossServiceUtils.ProjectVectorToPlaneX
BossServiceUtils.moveTowardsVector = BossServiceUtils.MoveTowardsVector
BossServiceUtils.computeFacingVector = BossServiceUtils.ComputeFacingVector
BossServiceUtils.lookCFrame = BossServiceUtils.LookCFrame
BossServiceUtils.isNightClockTime = BossServiceUtils.IsNightClockTime
BossServiceUtils.didClockPass = BossServiceUtils.DidClockPass
BossServiceUtils.resolveTargetPlayerUserId = BossServiceUtils.ResolveTargetPlayerUserId
BossServiceUtils.isPlayerAlive = BossServiceUtils.IsPlayerAlive

return BossServiceUtils
