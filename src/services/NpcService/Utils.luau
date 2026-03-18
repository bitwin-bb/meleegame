--!strict
local Workspace = game:GetService("Workspace")

local NpcServiceUtils = {}

export type NpcType = "Slime"
export type NpcRuntimeState =
	"Dormant"
	| "Spawning"
	| "AwaitingBiome"
	| "Idle"
	| "Searching"
	| "Aggro"
	| "Attacking"
	| "Dead"
export type BiomeName = "Unknown" | "Forest" | "Desert" | "Snow" | "Jungle"

export type StateMachineGraph = {
	[NpcRuntimeState]: { [NpcRuntimeState]: boolean },
}

export type AnimationEventActionKind = "sound" | "animation"

export type AnimationEventAction = {
	kind: AnimationEventActionKind,
	source: any?,
	sound: any?,
	animation: any?,
	soundName: string?,
	animationName: string?,
	volume: number?,
	playbackSpeed: number?,
	weight: number?,
	fadeTime: number?,
	looped: boolean?,
	autoDestroy: boolean?,
	priority: Enum.AnimationPriority?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
	stopOtherTracks: boolean?,
	playOnClient: boolean?,
}

export type AnimationEventBinding = {
	markers: { [string]: { AnimationEventAction } },
	keyframes: { [string]: { AnimationEventAction } },
}

export type AnimationEventsByTrack = {
	[string]: AnimationEventBinding,
}

export type NpcSnapshot = {
	id: string,
	npcType: NpcType,
	displayName: string,
	state: NpcRuntimeState,
	biomeName: BiomeName,
	biomeReady: boolean,
	hp: number,
	maxHp: number,
	isAlive: boolean,
	position: Vector3?,
	updatedAt: number,
	lastReason: string,
}

export type SlimeSpawnConfig = {
	slimeType: string,
	displayName: string,
	modelName: string,
	modelHierarchy: string?,
	planeX: number?,
	aggroOnPlayer: boolean,
	passiveUntilHit: boolean,
	spawnCFrame: CFrame,
	restDuration: number?,
	hopDuration: number?,
	hopDistance: number?,
	animationEvents: AnimationEventsByTrack?,
}

export type SlimeSpawnSettings = {
	enabled: boolean,
	initialSpawnCount: number,
	maxAlive: number,
	spawnRate: number,
	spawnChance: number,
	despawnDistance: number,
}

local RBX_ASSET_PREFIX = "rbxassetid://"

local DEFAULT_SLIME_SPAWN_SETTINGS: SlimeSpawnSettings = {
	enabled = true,
	initialSpawnCount = 3,
	maxAlive = 8,
	spawnRate = 2,
	spawnChance = 0.4,
	despawnDistance = 220,
}

local DEFAULT_REQUEST_SYNC_METHOD = "requestSync"
local DEFAULT_APPLY_STATE_METHOD = "applyState"
local DEFAULT_NPC_ADDED_METHOD = "onNpcAdded"
local DEFAULT_NPC_REMOVED_METHOD = "onNpcRemoved"
local DEFAULT_NPC_STATE_CHANGED_METHOD = "onNpcStateChanged"
local DEFAULT_NPC_ANIMATION_EVENT_METHOD = "onNpcAnimationEvent"

NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC = DEFAULT_REQUEST_SYNC_METHOD
NpcServiceUtils.CLIENT_METHOD_APPLY_STATE = DEFAULT_APPLY_STATE_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_ADDED = DEFAULT_NPC_ADDED_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_REMOVED = DEFAULT_NPC_REMOVED_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED = DEFAULT_NPC_STATE_CHANGED_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_ANIMATION_EVENT = DEFAULT_NPC_ANIMATION_EVENT_METHOD
NpcServiceUtils.RUNTIME_ID_ATTRIBUTE = "NpcRuntimeId"
NpcServiceUtils.RUNTIME_NPC_TYPE_ATTRIBUTE = "NpcRuntimeType"
NpcServiceUtils.RUNTIME_DISPLAY_NAME_ATTRIBUTE = "NpcDisplayName"

local DEFAULT_STATE_MACHINE_GRAPH: StateMachineGraph = {
	Dormant = {
		Spawning = true,
		Dead = true,
	},
	Spawning = {
		AwaitingBiome = true,
		Idle = true,
		Searching = true,
		Aggro = true,
		Dead = true,
	},
	AwaitingBiome = {
		Idle = true,
		Searching = true,
		Aggro = true,
		Attacking = true,
		Dead = true,
	},
	Idle = {
		Searching = true,
		Aggro = true,
		Attacking = true,
		AwaitingBiome = true,
		Dead = true,
	},
	Searching = {
		Idle = true,
		Aggro = true,
		Attacking = true,
		AwaitingBiome = true,
		Dead = true,
	},
	Aggro = {
		Idle = true,
		Searching = true,
		Attacking = true,
		AwaitingBiome = true,
		Dead = true,
	},
	Attacking = {
		Idle = true,
		Searching = true,
		Aggro = true,
		AwaitingBiome = true,
		Dead = true,
	},
	Dead = {
		Dormant = true,
		Spawning = true,
	},
}

local BIOME_ID_TO_NAME = {
	FOREST = "Forest" :: BiomeName,
	DESERT = "Desert" :: BiomeName,
	SNOW = "Snow" :: BiomeName,
	JUNGLE = "Jungle" :: BiomeName,
}

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function clampInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	return math.floor(clampNumber(valueRaw, minimum, maximum, fallback))
end

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function cloneStateGraph(source: StateMachineGraph): StateMachineGraph
	local out: StateMachineGraph = {}
	for fromState, toStates in source do
		local outTransitions: { [NpcRuntimeState]: boolean } = {}
		for toState, allowed in toStates do
			outTransitions[toState] = allowed == true
		end
		out[fromState] = outTransitions
	end
	return out
end

local function cloneAnimationEventAction(action: AnimationEventAction): AnimationEventAction
	return {
		kind = action.kind,
		source = action.source,
		sound = action.sound,
		animation = action.animation,
		soundName = action.soundName,
		animationName = action.animationName,
		volume = action.volume,
		playbackSpeed = action.playbackSpeed,
		weight = action.weight,
		fadeTime = action.fadeTime,
		looped = action.looped,
		autoDestroy = action.autoDestroy,
		priority = action.priority,
		rollOffMaxDistance = action.rollOffMaxDistance,
		emitterSize = action.emitterSize,
		stopOtherTracks = action.stopOtherTracks,
		playOnClient = action.playOnClient,
	}
end

local function cloneAnimationActions(actions: { AnimationEventAction }): { AnimationEventAction }
	local out = table.create(#actions)
	for index, action in actions do
		out[index] = cloneAnimationEventAction(action)
	end
	return out
end

local function cloneAnimationEventBinding(binding: AnimationEventBinding): AnimationEventBinding
	local markers: { [string]: { AnimationEventAction } } = {}
	local keyframes: { [string]: { AnimationEventAction } } = {}

	for eventName, actions in binding.markers do
		markers[eventName] = cloneAnimationActions(actions)
	end

	for eventName, actions in binding.keyframes do
		keyframes[eventName] = cloneAnimationActions(actions)
	end

	return {
		markers = markers,
		keyframes = keyframes,
	}
end

local function cloneAnimationEvents(events: AnimationEventsByTrack): AnimationEventsByTrack
	local out: AnimationEventsByTrack = {}
	for trackName, binding in events do
		out[trackName] = cloneAnimationEventBinding(binding)
	end
	return out
end

local function normalizeActionKind(actionRaw: any): AnimationEventActionKind
	local token = string.lower(trim((actionRaw :: any).kind))
	if token == "animation" then
		return "animation"
	end
	if token == "sound" then
		return "sound"
	end
	if (actionRaw :: any).animation ~= nil or (actionRaw :: any).animationName ~= nil then
		return "animation"
	end
	return "sound"
end

local function sanitizeAnimationAction(actionRaw: any): AnimationEventAction?
	if typeof(actionRaw) ~= "table" then
		return nil
	end

	local action = actionRaw :: { [string]: any }
	local kind = normalizeActionKind(action)
	local soundName = trim(action.soundName)
	local animationName = trim(action.animationName)
	local source = action.source

	if kind == "sound" then
		source = if action.sound ~= nil then action.sound else source
	else
		source = if action.animation ~= nil then action.animation else source
	end

	if source == nil and soundName == "" and animationName == "" then
		return nil
	end

	return {
		kind = kind,
		source = source,
		sound = action.sound,
		animation = action.animation,
		soundName = if soundName ~= "" then soundName else nil,
		animationName = if animationName ~= "" then animationName else nil,
		volume = if typeof(action.volume) == "number" then clampNumber(action.volume, 0, 10, 1) else nil,
		playbackSpeed = if typeof(action.playbackSpeed) == "number"
			then clampNumber(action.playbackSpeed, 0.05, 6, 1)
			else nil,
		weight = if typeof(action.weight) == "number" then clampNumber(action.weight, 0.05, 10, 1) else nil,
		fadeTime = if typeof(action.fadeTime) == "number" then clampNumber(action.fadeTime, 0, 10, 0.08) else nil,
		looped = if typeof(action.looped) == "boolean" then action.looped else nil,
		autoDestroy = if typeof(action.autoDestroy) == "boolean" then action.autoDestroy else nil,
		priority = if typeof(action.priority) == "EnumItem" then action.priority else nil,
		rollOffMaxDistance = if typeof(action.rollOffMaxDistance) == "number"
			then clampNumber(action.rollOffMaxDistance, 4, 512, 64)
			else nil,
		emitterSize = if typeof(action.emitterSize) == "number" then clampNumber(action.emitterSize, 0, 64, 4) else nil,
		stopOtherTracks = if typeof(action.stopOtherTracks) == "boolean" then action.stopOtherTracks else nil,
		playOnClient = if typeof(action.playOnClient) == "boolean" then action.playOnClient else nil,
	}
end

local function sanitizeAnimationActions(actionsRaw: any): { AnimationEventAction }
	local out = {}
	if actionsRaw == nil then
		return out
	end

	if typeof(actionsRaw) ~= "table" then
		local singleAction = sanitizeAnimationAction({
			kind = "sound",
			source = actionsRaw,
		})
		if singleAction ~= nil then
			table.insert(out, singleAction)
		end
		return out
	end

	local source = actionsRaw :: { [any]: any }
	if source.kind ~= nil or source.source ~= nil or source.sound ~= nil or source.animation ~= nil then
		local singleAction = sanitizeAnimationAction(source)
		if singleAction ~= nil then
			table.insert(out, singleAction)
		end
		return out
	end

	for _, candidate in source do
		local action = sanitizeAnimationAction(candidate)
		if action ~= nil then
			table.insert(out, action)
		end
	end

	return out
end

local function sanitizeAnimationBinding(bindingRaw: any, fallback: AnimationEventBinding?): AnimationEventBinding
	local source = if typeof(bindingRaw) == "table" then bindingRaw else {}
	local markers: { [string]: { AnimationEventAction } } = {}
	local keyframes: { [string]: { AnimationEventAction } } = {}

	if fallback ~= nil then
		for eventName, fallbackActions in fallback.markers do
			markers[eventName] = cloneAnimationActions(fallbackActions)
		end
		for eventName, fallbackActions in fallback.keyframes do
			keyframes[eventName] = cloneAnimationActions(fallbackActions)
		end
	end

	if typeof((source :: any).markers) == "table" then
		for eventName, actionsRaw in (source :: any).markers do
			if typeof(eventName) == "string" and eventName ~= "" then
				markers[eventName] = sanitizeAnimationActions(actionsRaw)
			end
		end
	end

	if typeof((source :: any).keyframes) == "table" then
		for eventName, actionsRaw in (source :: any).keyframes do
			if typeof(eventName) == "string" and eventName ~= "" then
				keyframes[eventName] = sanitizeAnimationActions(actionsRaw)
			end
		end
	end

	return {
		markers = markers,
		keyframes = keyframes,
	}
end

function NpcServiceUtils.normalizeAssetId(rawId: any): string?
	if typeof(rawId) == "number" then
		if rawId <= 0 then
			return nil
		end
		return RBX_ASSET_PREFIX .. tostring(math.floor(rawId))
	end

	if typeof(rawId) ~= "string" then
		return nil
	end

	local text = string.gsub(rawId, "%s", "")
	if text == "" then
		return nil
	end

	if string.sub(text, 1, #RBX_ASSET_PREFIX) == RBX_ASSET_PREFIX then
		local numericId = string.match(text, "(%d+)")
		if numericId == nil then
			return nil
		end
		return RBX_ASSET_PREFIX .. numericId
	end

	local numericOnly = string.match(text, "^%d+$")
	if numericOnly then
		return RBX_ASSET_PREFIX .. numericOnly
	end

	local trailingNumeric = string.match(text, "(%d+)$")
	if trailingNumeric then
		return RBX_ASSET_PREFIX .. trailingNumeric
	end

	return nil
end

function NpcServiceUtils.resolveAnimationTemplate(raw: any): Animation?
	if typeof(raw) ~= "Instance" then
		return nil
	end
	if raw:IsA("Animation") then
		return raw
	end
	return nil
end

function NpcServiceUtils.resolveAnimationSource(raw: any): (Animation?, string?)
	local template = NpcServiceUtils.resolveAnimationTemplate(raw)
	if template then
		return template, nil
	end

	if typeof(raw) == "table" then
		local source = raw :: { [string]: any }
		local candidateTemplate = NpcServiceUtils.resolveAnimationTemplate(source.animation)
		if candidateTemplate then
			return candidateTemplate, nil
		end

		local candidateId =
			NpcServiceUtils.normalizeAssetId(source.id or source.animationId or source.assetId or source.source)
		if candidateId then
			return nil, candidateId
		end
	end

	local assetId = NpcServiceUtils.normalizeAssetId(raw)
	if assetId then
		return nil, assetId
	end

	return nil, nil
end

function NpcServiceUtils.resolveSoundSource(raw: any): string?
	if typeof(raw) == "Instance" and raw:IsA("Sound") then
		return NpcServiceUtils.normalizeAssetId(raw.SoundId)
	end

	if typeof(raw) == "table" then
		local source = raw :: { [string]: any }
		if typeof(source.sound) == "Instance" and source.sound:IsA("Sound") then
			local candidateId = NpcServiceUtils.normalizeAssetId((source.sound :: Sound).SoundId)
			if candidateId then
				return candidateId
			end
		end

		local candidateId = NpcServiceUtils.normalizeAssetId(source.id or source.soundId or source.assetId or source.source)
		if candidateId then
			return candidateId
		end
	end

	local assetId = NpcServiceUtils.normalizeAssetId(raw)
	if assetId then
		return assetId
	end

	return nil
end

function NpcServiceUtils.findDescendantByNameOfClass(
	root: Instance?,
	expectedNameRaw: any,
	classNameRaw: any
): Instance?
	if root == nil then
		return nil
	end
	if typeof(expectedNameRaw) ~= "string" or expectedNameRaw == "" then
		return nil
	end
	if typeof(classNameRaw) ~= "string" or classNameRaw == "" then
		return nil
	end

	local expectedName = string.lower(expectedNameRaw)
	for _, descendant in root:GetDescendants() do
		if descendant.ClassName == classNameRaw and string.lower(descendant.Name) == expectedName then
			return descendant
		end
	end

	return nil
end

function NpcServiceUtils.createDefaultStateMachineGraph(): StateMachineGraph
	return cloneStateGraph(DEFAULT_STATE_MACHINE_GRAPH)
end

function NpcServiceUtils.sanitizeSlimeSpawnSettings(
	settingsRaw: any,
	fallback: SlimeSpawnSettings?
): SlimeSpawnSettings
	local base = if fallback ~= nil then fallback else DEFAULT_SLIME_SPAWN_SETTINGS
	local settings = if typeof(settingsRaw) == "table" then settingsRaw else {}

	return {
		enabled = if typeof((settings :: any).enabled) == "boolean" then (settings :: any).enabled else base.enabled,
		initialSpawnCount = clampInteger((settings :: any).initialSpawnCount, 0, 128, base.initialSpawnCount),
		maxAlive = clampInteger((settings :: any).maxAlive, 1, 256, base.maxAlive),
		spawnRate = clampNumber((settings :: any).spawnRate, 0.05, 600, base.spawnRate),
		spawnChance = clampNumber((settings :: any).spawnChance, 0, 1, base.spawnChance),
		despawnDistance = clampNumber((settings :: any).despawnDistance, 32, 4096, base.despawnDistance),
	}
end

function NpcServiceUtils.canTransition(
	graph: StateMachineGraph,
	currentState: NpcRuntimeState,
	nextState: NpcRuntimeState
): boolean
	if currentState == nextState then
		return true
	end
	local transitions = graph[currentState]
	if transitions == nil then
		return false
	end
	return transitions[nextState] == true
end

function NpcServiceUtils.createDefaultSlimeAnimationEvents(): AnimationEventsByTrack
	local defaultEvents: AnimationEventsByTrack = {
		Jump = {
			markers = {
				jump = {
					{
						kind = "sound",
						soundName = "Jump",
					},
				},
			},
			keyframes = {
				jump = {
					{
						kind = "sound",
						soundName = "Jump",
					},
				},
			},
		},
		Land = {
			markers = {
				land = {
					{
						kind = "sound",
						soundName = "Land",
					},
				},
			},
			keyframes = {
				land = {
					{
						kind = "sound",
						soundName = "Land",
					},
				},
			},
		},
		Hurt = {
			markers = {
				hit = {
					{
						kind = "sound",
						soundName = "Hurt",
					},
				},
			},
			keyframes = {
				hit = {
					{
						kind = "sound",
						soundName = "Hurt",
					},
				},
			},
		},
	}

	return cloneAnimationEvents(defaultEvents)
end

function NpcServiceUtils.sanitizeAnimationEventsByTrack(
	eventsRaw: any,
	fallback: AnimationEventsByTrack?
): AnimationEventsByTrack
	local source = if typeof(eventsRaw) == "table" then eventsRaw else {}
	local out = if fallback ~= nil then cloneAnimationEvents(fallback) else ({} :: AnimationEventsByTrack)

	for trackName, bindingRaw in source do
		if typeof(trackName) ~= "string" or trackName == "" then
			continue
		end
		local fallbackBinding = out[trackName]
		out[trackName] = sanitizeAnimationBinding(bindingRaw, fallbackBinding)
	end

	return out
end

function NpcServiceUtils.resolveBiomeNameFromWorld(worldRaw: any, worldPosition: Vector3): (BiomeName, boolean)
	if typeof(worldRaw) ~= "table" then
		return "Unknown", false
	end

	local world = worldRaw :: { [string]: any }
	local worldOrigin = if typeof(world.worldOrigin) == "Vector3" then world.worldOrigin else Vector3.zero
	local tileSize = if typeof(world.tileSize) == "number" and world.tileSize > 0 then world.tileSize else 2
	local biomeGenerator = world.biomeGenerator
	local biomeIdMap = world.biomeId

	if typeof(biomeGenerator) ~= "table" then
		return "Unknown", false
	end
	if typeof((biomeGenerator :: any).getColumnProfile) ~= "function" then
		return "Unknown", false
	end

	local tileX = math.floor((worldPosition.Z - worldOrigin.Z) / tileSize)
	local ok, columnOrError = pcall(function()
		return (biomeGenerator :: any):getColumnProfile(tileX)
	end)
	if not ok then
		warn("[NpcService] Failed biome query:", tostring(columnOrError))
		return "Unknown", false
	end
	if typeof(columnOrError) ~= "table" then
		return "Unknown", false
	end

	local biomeId = (columnOrError :: any).biomeId
	if typeof(biomeId) ~= "number" then
		return "Unknown", false
	end
	if typeof(biomeIdMap) ~= "table" then
		return "Unknown", false
	end

	for biomeKey, biomeName in BIOME_ID_TO_NAME do
		if (biomeIdMap :: any)[biomeKey] == biomeId then
			return biomeName, true
		end
	end

	return "Unknown", false
end

function NpcServiceUtils.collectSpawnCFrames(maxCountRaw: any): { CFrame }
	local maxCount = math.max(1, math.floor(clampNumber(maxCountRaw, 1, 128, 8)))
	local out = {}

	local candidateFolders = { "NpcSpawns", "NpcSpawnPoints", "SlimeSpawns" }
	for _, folderName in candidateFolders do
		local folder = Workspace:FindFirstChild(folderName)
		if folder == nil then
			continue
		end

		for _, child in folder:GetDescendants() do
			if #out >= maxCount then
				break
			end

			if child:IsA("BasePart") then
				table.insert(out, child.CFrame)
			elseif child:IsA("Attachment") then
				table.insert(out, child.WorldCFrame)
			end
		end

		if #out >= maxCount then
			break
		end
	end

	if #out == 0 then
		local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			table.insert(out, spawnLocation.CFrame + Vector3.new(0, 4, 0))
		end
	end

	if #out == 0 then
		local basePosition = Vector3.new(0, 8, 0)
		for index = 1, maxCount do
			local zOffset = (index - 1) * 12
			table.insert(out, CFrame.new(basePosition + Vector3.new(0, 0, zOffset)))
		end
	end

	return out
end

function NpcServiceUtils.createDefaultSlimeSpawnConfigs(spawnCFrames: { CFrame }?): { SlimeSpawnConfig }
	local cframes = spawnCFrames
	if cframes == nil or #cframes == 0 then
		cframes = NpcServiceUtils.collectSpawnCFrames(3)
	end

	local variants = {
		{
			slimeType = "GreenSlime",
			displayName = "Green Slime",
			modelName = "GreenSlime",
			modelHierarchy = "Enemies.GreenSlime",
			aggroOnPlayer = true,
			passiveUntilHit = true,
		},
	}

	local defaultAnimationEvents = NpcServiceUtils.createDefaultSlimeAnimationEvents()
	local out = {}
	local planeX = if #cframes > 0 then cframes[1].Position.X else 0
	for index, spawnCFrame in cframes do
		local variant = variants[((index - 1) % #variants) + 1]
		local spawnPosition = spawnCFrame.Position
		local projectedCFrame = CFrame.new(Vector3.new(planeX, spawnPosition.Y, spawnPosition.Z))
		table.insert(out, {
			slimeType = variant.slimeType,
			displayName = variant.displayName,
			modelName = variant.modelName,
			modelHierarchy = variant.modelHierarchy,
			planeX = planeX,
			aggroOnPlayer = variant.aggroOnPlayer,
			passiveUntilHit = variant.passiveUntilHit,
			spawnCFrame = projectedCFrame,
			animationEvents = cloneAnimationEvents(defaultAnimationEvents),
		})
	end

	return out
end

function NpcServiceUtils.applyRuntimeModelAttributes(
	modelRaw: any,
	runtimeIdRaw: any,
	npcTypeRaw: any,
	displayNameRaw: any
): boolean
	if typeof(modelRaw) ~= "Instance" or not modelRaw:IsA("Model") then
		return false
	end

	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return false
	end

	modelRaw:SetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE, runtimeId)

	local npcType = trim(npcTypeRaw)
	if npcType ~= "" then
		modelRaw:SetAttribute(NpcServiceUtils.RUNTIME_NPC_TYPE_ATTRIBUTE, npcType)
	end

	local displayName = trim(displayNameRaw)
	if displayName ~= "" then
		modelRaw:SetAttribute(NpcServiceUtils.RUNTIME_DISPLAY_NAME_ATTRIBUTE, displayName)
	end

	return true
end

function NpcServiceUtils.resolveRuntimeModelFromInstance(instanceRaw: any): Model?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local cursor: Instance? = instanceRaw
	while cursor ~= nil do
		if cursor:IsA("Model") then
			local runtimeId = cursor:GetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE)
			if typeof(runtimeId) == "string" and runtimeId ~= "" then
				return cursor
			end
		end
		cursor = cursor.Parent
	end

	return nil
end

function NpcServiceUtils.resolveRuntimeIdFromInstance(instanceRaw: any): string?
	local runtimeModel = NpcServiceUtils.resolveRuntimeModelFromInstance(instanceRaw)
	if runtimeModel == nil then
		return nil
	end

	local runtimeId = runtimeModel:GetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE)
	if typeof(runtimeId) == "string" and runtimeId ~= "" then
		return runtimeId
	end

	return nil
end

function NpcServiceUtils.sanitizeSnapshot(snapshotRaw: any, fallback: NpcSnapshot?): NpcSnapshot?
	if typeof(snapshotRaw) ~= "table" then
		return fallback
	end

	local source = snapshotRaw :: { [string]: any }
	local id = trim(source.id)
	if id == "" then
		return fallback
	end

	local fallbackSnapshot = fallback
	local state = source.state
	if state ~= "Dormant"
		and state ~= "Spawning"
		and state ~= "AwaitingBiome"
		and state ~= "Idle"
		and state ~= "Searching"
		and state ~= "Aggro"
		and state ~= "Attacking"
		and state ~= "Dead" then
		state = if fallbackSnapshot then fallbackSnapshot.state else "Dormant"
	end

	local biomeName = source.biomeName
	if biomeName ~= "Forest" and biomeName ~= "Desert" and biomeName ~= "Snow" and biomeName ~= "Jungle" then
		biomeName = "Unknown"
	end

	local fallbackMaxHp = if fallbackSnapshot ~= nil then fallbackSnapshot.maxHp else 1
	local rawMaxHp = if typeof(source.maxHp) == "number" and source.maxHp == source.maxHp then source.maxHp else fallbackMaxHp
	local maxHp = math.max(1, rawMaxHp)

	local fallbackHp = if fallbackSnapshot ~= nil then fallbackSnapshot.hp else maxHp
	local rawHp = if typeof(source.hp) == "number" and source.hp == source.hp then source.hp else fallbackHp
	local hp = math.clamp(rawHp, 0, maxHp)

	local isAlive = if typeof(source.isAlive) == "boolean"
		then source.isAlive
		else if fallbackSnapshot ~= nil then fallbackSnapshot.isAlive else state ~= "Dead"
	if state == "Dead" then
		isAlive = false
		hp = 0
	end

	local npcType = if source.npcType == "Slime"
		then "Slime"
		else if fallbackSnapshot then fallbackSnapshot.npcType else "Slime"

	return {
		id = id,
		npcType = npcType,
		displayName = if typeof(source.displayName) == "string" and source.displayName ~= ""
			then source.displayName
			else if fallbackSnapshot then fallbackSnapshot.displayName else id,
		state = state :: NpcRuntimeState,
		biomeName = biomeName :: BiomeName,
		biomeReady = if typeof(source.biomeReady) == "boolean"
			then source.biomeReady
			else if fallbackSnapshot then fallbackSnapshot.biomeReady else false,
		hp = hp,
		maxHp = maxHp,
		isAlive = isAlive,
		position = if typeof(source.position) == "Vector3"
			then source.position
			else if fallbackSnapshot then fallbackSnapshot.position else nil,
		updatedAt = if typeof(source.updatedAt) == "number" and source.updatedAt == source.updatedAt
			then source.updatedAt
			else os.clock(),
		lastReason = if typeof(source.lastReason) == "string"
			then source.lastReason
			else if fallbackSnapshot then fallbackSnapshot.lastReason else "unknown",
	}
end

return NpcServiceUtils
