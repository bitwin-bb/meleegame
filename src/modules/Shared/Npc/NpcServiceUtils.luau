
local require = require(script.Parent.loader).load(script)

local Workspace = game:GetService("Workspace")

local TagBinder = require("TagBinder")

local NpcServiceUtils = {}

export type NpcType = string
export type NpcRuntimeState = string
export type BiomeName = string

export type StateMachineGraph = {
	[NpcRuntimeState]: { [NpcRuntimeState]: boolean },
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
	spritePhase: string?,
	spriteFrame: number?,
	spriteFrameRate: number?,
	spritePhaseElapsed: number?,
	spritePhaseDuration: number?,
	spriteFacingSign: number?,
	spriteReceivedAt: number?,
}

export type SlimeSpawnConfig = {
	slimeType: string,
	displayName: string,
	modelName: string,
	planeX: number?,
	aggroOnPlayer: boolean,
	passiveUntilHit: boolean,
	spawnCFrame: CFrame,
	restDuration: number?,
	hopDuration: number?,
	hopDistance: number?,
}

export type SlimeSpawnSettings = {
	enabled: boolean,
	initialSpawnCount: number,
	maxAlive: number,
	spawnRate: number,
	spawnChance: number,
	despawnDistance: number,
}

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

NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC = DEFAULT_REQUEST_SYNC_METHOD
NpcServiceUtils.CLIENT_METHOD_APPLY_STATE = DEFAULT_APPLY_STATE_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_ADDED = DEFAULT_NPC_ADDED_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_REMOVED = DEFAULT_NPC_REMOVED_METHOD
NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED = DEFAULT_NPC_STATE_CHANGED_METHOD
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

function NpcServiceUtils.CreateDefaultStateMachineGraph(): StateMachineGraph
	return cloneStateGraph(DEFAULT_STATE_MACHINE_GRAPH)
end

function NpcServiceUtils.SanitizeSlimeSpawnSettings(settingsRaw: any, fallback: SlimeSpawnSettings?): SlimeSpawnSettings
	local base = if fallback ~= nil then fallback else DEFAULT_SLIME_SPAWN_SETTINGS
	local settings = if typeof(settingsRaw) == "table" then settingsRaw else {} :: any

	return {
		enabled = if typeof((settings :: any).enabled) == "boolean" then (settings :: any).enabled else base.enabled,
		initialSpawnCount = clampInteger((settings :: any).initialSpawnCount, 0, 128, base.initialSpawnCount),
		maxAlive = clampInteger((settings :: any).maxAlive, 1, 256, base.maxAlive),
		spawnRate = clampNumber((settings :: any).spawnRate, 0.05, 600, base.spawnRate),
		spawnChance = clampNumber((settings :: any).spawnChance, 0, 1, base.spawnChance),
		despawnDistance = clampNumber((settings :: any).despawnDistance, 32, 4096, base.despawnDistance),
	}
end

function NpcServiceUtils.CanTransition(
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

function NpcServiceUtils.ResolveBiomeNameFromWorld(worldRaw: any, worldPosition: Vector3): (BiomeName, boolean)
	if typeof(worldRaw) ~= "table" then
		return "Unknown", false
	end

	local world = worldRaw :: { [string]: any }
	local worldOrigin = if typeof(world.worldOrigin) == "Vector3" then world.worldOrigin else Vector3.zero
	local tileSize = if typeof(world.tileSize) == "number" and world.tileSize > 0 then world.tileSize else 4
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
			return biomeName :: string, true
		end
	end

	return "Unknown", false
end

function NpcServiceUtils.CollectSpawnCFrames(maxCountRaw: any): { CFrame }
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

function NpcServiceUtils.CreateDefaultSlimeSpawnConfigs(spawnCFrames: { CFrame }?): { SlimeSpawnConfig }
	local cframes = spawnCFrames
	if cframes == nil or #cframes == 0 then
		cframes = NpcServiceUtils.CollectSpawnCFrames(3)
	end
	local resolvedCFrames = cframes :: { CFrame }

	local variants = {
		{
			slimeType = "GreenSlime",
			displayName = "Green Slime",
			modelName = "GreenSlime",
			aggroOnPlayer = true,
			passiveUntilHit = true,
		},
	}

	local out = {}
	local planeX = if #resolvedCFrames > 0 then resolvedCFrames[1].Position.X else 0
	for index, spawnCFrame in resolvedCFrames do
		local variant = variants[((index - 1) % #variants) + 1]
		local spawnPosition = spawnCFrame.Position
		local projectedCFrame = CFrame.new(Vector3.new(planeX, spawnPosition.Y, spawnPosition.Z))
		table.insert(out, {
			slimeType = variant.slimeType,
			displayName = variant.displayName,
			modelName = variant.modelName,
			planeX = planeX,
			aggroOnPlayer = variant.aggroOnPlayer,
			passiveUntilHit = variant.passiveUntilHit,
			spawnCFrame = projectedCFrame,
		})
	end

	return out
end

function NpcServiceUtils.ApplyRuntimeModelAttributes(
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
	TagBinder.applyTag(modelRaw, TagBinder.Tags.Npc)
	local npcTypeToken = string.lower(npcType)
	if string.find(npcTypeToken, "slime", 1, true) ~= nil then
		TagBinder.applyTag(modelRaw, TagBinder.Tags.Npc_Slime)
	end
	if string.find(npcTypeToken, "flying", 1, true) ~= nil then
		TagBinder.applyTag(modelRaw, TagBinder.Tags.Npc_Flying)
	end
	if string.find(npcTypeToken, "ground", 1, true) ~= nil then
		TagBinder.applyTag(modelRaw, TagBinder.Tags.Npc_Ground)
	end

	local displayName = trim(displayNameRaw)
	if displayName ~= "" then
		modelRaw:SetAttribute(NpcServiceUtils.RUNTIME_DISPLAY_NAME_ATTRIBUTE, displayName)
	end

	return true
end

function NpcServiceUtils.ResolveRuntimeModelFromInstance(instanceRaw: any): Model?
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

function NpcServiceUtils.ResolveRuntimeIdFromInstance(instanceRaw: any): string?
	local runtimeModel = NpcServiceUtils.ResolveRuntimeModelFromInstance(instanceRaw)
	if runtimeModel == nil then
		return nil
	end

	local runtimeId = runtimeModel:GetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE)
	if typeof(runtimeId) == "string" and runtimeId ~= "" then
		return runtimeId
	end

	return nil
end

function NpcServiceUtils.SanitizeSnapshot(snapshotRaw: any, fallback: NpcSnapshot?): NpcSnapshot?
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
	if
		state ~= "Dormant"
		and state ~= "Spawning"
		and state ~= "AwaitingBiome"
		and state ~= "Idle"
		and state ~= "Searching"
		and state ~= "Aggro"
		and state ~= "Attacking"
		and state ~= "Dead"
	then
		state = if fallbackSnapshot then fallbackSnapshot.state else "Dormant"
	end

	local biomeName = source.biomeName
	if biomeName ~= "Forest" and biomeName ~= "Desert" and biomeName ~= "Snow" and biomeName ~= "Jungle" then
		biomeName = "Unknown"
	end

	local fallbackMaxHp = if fallbackSnapshot ~= nil then fallbackSnapshot.maxHp else 1
	local rawMaxHp = if typeof(source.maxHp) == "number" and source.maxHp == source.maxHp
		then source.maxHp
		else fallbackMaxHp
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
	local spritePhaseRaw = trim(source.spritePhase)
	local spritePhase = if spritePhaseRaw ~= ""
		then spritePhaseRaw
		else if fallbackSnapshot then fallbackSnapshot.spritePhase else nil
	local spriteFrame = if typeof(source.spriteFrame) == "number" and source.spriteFrame == source.spriteFrame
		then math.clamp(math.floor(source.spriteFrame), 1, 1024)
		else if fallbackSnapshot then fallbackSnapshot.spriteFrame else nil
	local spriteFrameRate = if typeof(source.spriteFrameRate) == "number"
			and source.spriteFrameRate == source.spriteFrameRate
		then math.clamp(source.spriteFrameRate, 0.01, 120)
		else if fallbackSnapshot then fallbackSnapshot.spriteFrameRate else nil
	local spritePhaseElapsed = if typeof(source.spritePhaseElapsed) == "number"
			and source.spritePhaseElapsed == source.spritePhaseElapsed
		then math.max(0, source.spritePhaseElapsed)
		else if fallbackSnapshot then fallbackSnapshot.spritePhaseElapsed else nil
	local spritePhaseDuration = if typeof(source.spritePhaseDuration) == "number"
			and source.spritePhaseDuration == source.spritePhaseDuration
		then math.max(0.001, source.spritePhaseDuration)
		else if fallbackSnapshot then fallbackSnapshot.spritePhaseDuration else nil
	local spriteFacingSign = if typeof(source.spriteFacingSign) == "number"
			and source.spriteFacingSign == source.spriteFacingSign
		then math.sign(source.spriteFacingSign)
		else if fallbackSnapshot then fallbackSnapshot.spriteFacingSign else nil
	if spriteFacingSign == 0 then
		spriteFacingSign = if fallbackSnapshot then fallbackSnapshot.spriteFacingSign else nil
	end
	local spriteReceivedAt = if typeof(source.spriteReceivedAt) == "number"
			and source.spriteReceivedAt == source.spriteReceivedAt
		then source.spriteReceivedAt
		else if fallbackSnapshot then fallbackSnapshot.spriteReceivedAt else nil

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
		spritePhase = spritePhase,
		spriteFrame = spriteFrame,
		spriteFrameRate = spriteFrameRate,
		spritePhaseElapsed = spritePhaseElapsed,
		spritePhaseDuration = spritePhaseDuration,
		spriteFacingSign = spriteFacingSign,
		spriteReceivedAt = spriteReceivedAt,
	}
end

NpcServiceUtils.createDefaultStateMachineGraph = NpcServiceUtils.CreateDefaultStateMachineGraph
NpcServiceUtils.sanitizeSlimeSpawnSettings = NpcServiceUtils.SanitizeSlimeSpawnSettings
NpcServiceUtils.canTransition = NpcServiceUtils.CanTransition
NpcServiceUtils.resolveBiomeNameFromWorld = NpcServiceUtils.ResolveBiomeNameFromWorld
NpcServiceUtils.collectSpawnCFrames = NpcServiceUtils.CollectSpawnCFrames
NpcServiceUtils.createDefaultSlimeSpawnConfigs = NpcServiceUtils.CreateDefaultSlimeSpawnConfigs
NpcServiceUtils.applyRuntimeModelAttributes = NpcServiceUtils.ApplyRuntimeModelAttributes
NpcServiceUtils.resolveRuntimeModelFromInstance = NpcServiceUtils.ResolveRuntimeModelFromInstance
NpcServiceUtils.resolveRuntimeIdFromInstance = NpcServiceUtils.ResolveRuntimeIdFromInstance
NpcServiceUtils.sanitizeSnapshot = NpcServiceUtils.SanitizeSnapshot

return NpcServiceUtils
