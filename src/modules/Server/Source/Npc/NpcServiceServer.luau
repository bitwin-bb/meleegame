
local require = require(script.Parent.loader).load(script)

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Bounds = require("Bounds")
local Configs = require("CoreConfigs")
local EnemyHitbox = require("EnemyHitbox")
local EyeOfCthulhuNpc = require("EyeOfCthulhuBoss")
local HpServiceServer = require("HpServiceServer")
local InstanceUtils = require("InstanceUtils")
local LootServiceServer = require("LootServiceServer")
local PacketPayload = require("PacketPayload")
local NpcServicePackets = require("NetPacketsShared").NpcService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestSync")
end

local NevermoreSupport = require("NevermoreSupport")
local NpcServiceUtils = require("NpcServiceUtils")
local PlayerServiceServer = require("PlayerServiceServer")
local BinderSupportServer = require("BinderSupportServer")
local SlimeNpc = require("SlimeNpc")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")

type RuntimeNpc = any
type EnemyHitboxManager = EnemyHitbox.EnemyHitbox
type NpcType = NpcServiceUtils.NpcType
type NpcRuntimeState = string
type BiomeName = string
type StateMachineGraph = NpcServiceUtils.StateMachineGraph
type NpcSnapshot = NpcServiceUtils.NpcSnapshot
type SlimeSpawnConfig = NpcServiceUtils.SlimeSpawnConfig
type SlimeSpawnSettings = NpcServiceUtils.SlimeSpawnSettings
type HpServiceServerObject = {
	DamagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}
type LootServiceServerObject = {
	spawnDropsFromSource: (
		self: LootServiceServerObject,
		sourceRaw: any,
		originRaw: any,
		optionsRaw: any
	) -> { any },
}

type JanitorClass = any

type NpcRuntime = {
	id: string,
	entityId: string,
	npcType: NpcType,
	displayName: string,
	npc: RuntimeNpc,
	slime: RuntimeNpc,
	hp: number,
	maxHp: number,
	isAlive: boolean,
	state: NpcRuntimeState,
	lastReason: string,
	biomeName: BiomeName,
	biomeReady: boolean,
	stateGraph: StateMachineGraph,
	updatedAt: number,
	janitor: JanitorClass,
	isRemoving: boolean,
	enemyHitboxId: string?,
	lastEnemyHitAt: number,
	lastSpriteStateKey: string?,
}

local NpcServiceServer = {}

local DEFAULT_NPC_FOLDER_NAME = "NpcRuntime"
local DEFAULT_STATE_REFRESH_INTERVAL = 0.1
local DEFAULT_BIOME_REFRESH_INTERVAL = 0.35
local DEFAULT_PLAYER_RELATIVE_MIN_Z_OFFSET = 24
local DEFAULT_PLAYER_RELATIVE_MAX_Z_OFFSET = 48
local DEFAULT_PLAYER_RELATIVE_Y_OFFSET = 3
local DEFAULT_PLAYER_RELATIVE_SPAWN_ATTEMPTS_PER_PLAYER = 5
local DEFAULT_SPAWN_SURFACE_RAYCAST_HEIGHT = 96
local DEFAULT_SPAWN_SURFACE_RAYCAST_DEPTH = 224
local DEFAULT_SPAWN_SURFACE_CLEARANCE = 3
local DEFAULT_SPAWN_EMPTY_GAP_HALF_EXTENTS = Vector3.new(2.25, 2.5, 2.25)
local DEFAULT_SPAWN_EMPTY_GAP_FLOOR_BUFFER = 0.2
local DEFAULT_SPAWN_EMPTY_GAP_MAX_PARTS = 24
local DEFAULT_DESPAWN_CHECK_INTERVAL = 0.5
local DEFAULT_DESPAWN_DISTANCE_BUFFER = 8
local DEFAULT_RUNTIME_HURTBOX_SIZE = Vector3.new(4, 3, 4)
local DEFAULT_RUNTIME_HURTBOX_PADDING = Vector3.new(1.2, 0.5, 1.2)
local MIN_RUNTIME_HURTBOX_SIZE = Vector3.new(3.5, 2.75, 3.5)
local PLAYER_COLLISION_GROUP = "PlayersCharacters"
local ENEMY_COLLISION_GROUP = "NpcEnemies"
local WORLD_GENERATION_FOLDER_NAME = "WorldGeneration"
local BIOME_TYPE_CORRUPTION = 2
local NPC_MODULES = {
	Slime = SlimeNpc,
	EyeOfCthulhu = EyeOfCthulhuNpc,
}

local function getSnapshotSpriteStateKey(snapshot: NpcSnapshot): string?
	if snapshot.spritePhase == nil then
		return nil
	end
	return `{snapshot.spritePhase}:{snapshot.spriteFrame or ""}`
end

local function fireForPlayers(players: { Player }, methodName: string, ...: any)
	for _, player in players do
		sendPacket(player, methodName, ...)
	end
end

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end

	return value
end

function NpcServiceServer.CoerceNumber(
	_self: NpcServiceServer,
	valueRaw: any,
	fallback: number,
	minimum: number?,
	maximum: number?
): number
	return CoerceNumber(valueRaw, fallback, minimum, maximum)
end

local function CoerceSizeVector(sizeRaw: any, fallback: Vector3): Vector3
	if typeof(sizeRaw) ~= "Vector3" then
		return fallback
	end
	return Vector3.new(
		math.max(0.05, math.abs(sizeRaw.X)),
		math.max(0.05, math.abs(sizeRaw.Y)),
		math.max(0.05, math.abs(sizeRaw.Z))
	)
end

local function computeBoxAabb(cframeRaw: any, sizeRaw: any): (Vector3, Vector3)
	local cframe = if typeof(cframeRaw) == "CFrame" then cframeRaw else CFrame.new()
	local size = CoerceSizeVector(sizeRaw, Vector3.new(0.05, 0.05, 0.05))
	local halfSize = size * 0.5
	local right = cframe.RightVector
	local up = cframe.UpVector
	local look = cframe.LookVector
	local extents = Vector3.new(
		math.abs(right.X) * halfSize.X + math.abs(up.X) * halfSize.Y + math.abs(look.X) * halfSize.Z,
		math.abs(right.Y) * halfSize.X + math.abs(up.Y) * halfSize.Y + math.abs(look.Y) * halfSize.Z,
		math.abs(right.Z) * halfSize.X + math.abs(up.Z) * halfSize.Y + math.abs(look.Z) * halfSize.Z
	)
	local center = cframe.Position
	return center - extents, center + extents
end

local function aabbIntersects(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3): boolean
	return Bounds.Intersects(Bounds.New(aMin, aMax), Bounds.New(bMin, bMax))
end

local function setModelCollisionGroup(model: Model, collisionGroup: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = collisionGroup
		end
	end
end

local function applyRuntimeModelAttributes(runtime: NpcRuntime, model: Model?)
	if model == nil then
		return
	end

	NpcServiceUtils.ApplyRuntimeModelAttributes(model, runtime.id, runtime.npcType, runtime.displayName)
end

local function isValidSurfaceSpawnPart(part: BasePart): boolean
	if not part.CanCollide then
		return false
	end
	if part.LocalTransparencyModifier >= 0.99 then
		return false
	end

	local worldFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(WORLD_GENERATION_FOLDER_NAME)
	if worldFolder == nil then
		return true
	end
	return part:IsDescendantOf(worldFolder)
end

function NpcServiceServer.EnsureNpcFolder(self: NpcServiceServer): Folder
	return WorkspaceFolders.GetOrCreateFolderInGame(DEFAULT_NPC_FOLDER_NAME)
end

function NpcServiceServer.InitNpcModules(self: NpcServiceServer)
	self.npcModulesByType = {}
	for npcType, npcModule in NPC_MODULES do
		self.npcModulesByType[tostring(npcType)] = npcModule
		local init = (npcModule :: any).Init
		if typeof(init) == "function" then
			init(npcModule, self)
		end
	end
end

function NpcServiceServer.GetRuntimeModule(self: NpcServiceServer, runtime: NpcRuntime): any?
	return self.npcModulesByType[runtime.npcType]
end

function NpcServiceServer.EnsureCollisionGroups(self: NpcServiceServer)
	if self.collisionGroupsReady == true then
		return
	end

	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ENEMY_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, ENEMY_COLLISION_GROUP, false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(ENEMY_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(ENEMY_COLLISION_GROUP, ENEMY_COLLISION_GROUP, false)
	end)

	self.collisionGroupsReady = true
end

function NpcServiceServer.ApplyPlayerCollisionGroup(self: NpcServiceServer, player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	self:EnsureCollisionGroups()
	setModelCollisionGroup(character, PLAYER_COLLISION_GROUP)
end

function NpcServiceServer.BindPlayerCollisionGroup(self: NpcServiceServer, player: Player)
	self:ApplyPlayerCollisionGroup(player)

	local previousConnection = self.playerCharacterAddedConnections[player]
	if previousConnection ~= nil then
		previousConnection:Disconnect()
	end

	self.playerCharacterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		self:EnsureCollisionGroups()
		setModelCollisionGroup(character, PLAYER_COLLISION_GROUP)
	end)
end

function NpcServiceServer.UnbindPlayerCollisionGroup(self: NpcServiceServer, player: Player)
	local connection = self.playerCharacterAddedConnections[player]
	if connection ~= nil then
		connection:Disconnect()
		self.playerCharacterAddedConnections[player] = nil
	end
end

function NpcServiceServer.ApplyRuntimeNpcCollisionGroup(self: NpcServiceServer, runtime: NpcRuntime)
	local model = runtime.slime.model
	if model == nil then
		return
	end
	self:EnsureCollisionGroups()
	setModelCollisionGroup(model, ENEMY_COLLISION_GROUP)
end

function NpcServiceServer.GetWorld(self: NpcServiceServer): any?
	local getWorldMethod = (WorldGenerationServiceServer :: any).GetWorld
	if typeof(getWorldMethod) ~= "function" then
		return nil
	end

	local ok, worldOrError = pcall(function()
		return (WorldGenerationServiceServer :: any):GetWorld()
	end)
	if not ok then
		return nil
	end

	if worldOrError ~= self.world then
		self.world = worldOrError
	end
	return self.world
end

function NpcServiceServer.IsCorruptionBiomePosition(self: NpcServiceServer, worldPosition: Vector3): boolean
	local world = self:GetWorld()
	if world == nil then
		return false
	end

	local getBiomeTypeAtWorldPositionMethod = (world :: any).GetBiomeTypeAtWorldPosition
	if typeof(getBiomeTypeAtWorldPositionMethod) ~= "function" then
		return false
	end

	local ok, biomeTypeOrError = pcall(function()
		return (world :: any):GetBiomeTypeAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeTypeOrError) ~= "number" then
		return false
	end

	return math.floor(biomeTypeOrError) == BIOME_TYPE_CORRUPTION
end

function NpcServiceServer.CreateSnapshot(self: NpcServiceServer, runtime: NpcRuntime): NpcSnapshot
	self:SyncRuntimeVitals(runtime)
	local position = runtime.slime:GetPosition()
	local snapshot: NpcSnapshot = {
		id = runtime.id,
		npcType = runtime.npcType,
		displayName = runtime.displayName,
		state = runtime.state,
		biomeName = runtime.biomeName,
		biomeReady = runtime.biomeReady,
		hp = runtime.hp,
		maxHp = runtime.maxHp,
		isAlive = runtime.isAlive,
		position = position,
		updatedAt = runtime.updatedAt,
		lastReason = runtime.lastReason,
	}

	local npcModule = self:GetRuntimeModule(runtime)
	local getSpriteState = if npcModule ~= nil then (npcModule :: any).GetSpriteState else nil
	if typeof(getSpriteState) == "function" then
		local ok, spriteStateRaw = pcall(function()
			return getSpriteState(npcModule, self, runtime)
		end)
		if ok and typeof(spriteStateRaw) == "table" then
			local spriteState = spriteStateRaw :: { [string]: any }
			if typeof(spriteState.spritePhase) == "string" and spriteState.spritePhase ~= "" then
				snapshot.spritePhase = spriteState.spritePhase
			end
			if typeof(spriteState.spriteFrame) == "number" and spriteState.spriteFrame == spriteState.spriteFrame then
				snapshot.spriteFrame = math.max(1, math.floor(spriteState.spriteFrame))
			end
			if
				typeof(spriteState.spriteFrameRate) == "number"
				and spriteState.spriteFrameRate == spriteState.spriteFrameRate
			then
				snapshot.spriteFrameRate = math.clamp(spriteState.spriteFrameRate, 0.01, 120)
			end
			if
				typeof(spriteState.spritePhaseElapsed) == "number"
				and spriteState.spritePhaseElapsed == spriteState.spritePhaseElapsed
			then
				snapshot.spritePhaseElapsed = math.max(0, spriteState.spritePhaseElapsed)
			end
			if
				typeof(spriteState.spritePhaseDuration) == "number"
				and spriteState.spritePhaseDuration == spriteState.spritePhaseDuration
			then
				snapshot.spritePhaseDuration = math.max(0.001, spriteState.spritePhaseDuration)
			end
			if
				typeof(spriteState.spriteFacingSign) == "number"
				and spriteState.spriteFacingSign == spriteState.spriteFacingSign
			then
				local spriteFacingSign = math.sign(spriteState.spriteFacingSign)
				if spriteFacingSign ~= 0 then
					snapshot.spriteFacingSign = spriteFacingSign
				end
			end
		end
	end

	return snapshot
end

function NpcServiceServer.SyncRuntimeVitals(self: NpcServiceServer, runtime: NpcRuntime)
	local npcModule = self:GetRuntimeModule(runtime)
	local syncVitals = if npcModule ~= nil then (npcModule :: any).SyncVitals else nil
	if typeof(syncVitals) == "function" then
		syncVitals(npcModule, runtime)
		return
	end

	local npc = runtime.npc
	runtime.maxHp = npc.maxHp
	runtime.hp = math.clamp(npc.hp, 0, npc.maxHp)
	runtime.isAlive = npc.isAlive
end

function NpcServiceServer.GetRuntime(self: NpcServiceServer, runtimeId: string): NpcRuntime?
	return self.runtimes[runtimeId]
end

function NpcServiceServer.GetUntimeFromModel(self: NpcServiceServer, modelRaw: any): NpcRuntime?
	if typeof(modelRaw) ~= "Instance" or not modelRaw:IsA("Model") then
		return nil
	end

	local cursor: Instance? = modelRaw
	while cursor ~= nil do
		if cursor:IsA("Model") then
			local runtime = self.runtimesByModel[cursor]
			if runtime ~= nil then
				return runtime
			end
		end
		cursor = cursor.Parent
	end

	return nil
end

function NpcServiceServer.GetUntimeFromPart(self: NpcServiceServer, partRaw: any): NpcRuntime?
	if typeof(partRaw) ~= "Instance" or not partRaw:IsA("BasePart") then
		return nil
	end

	local enemyHitbox = self.enemyHitbox
	if enemyHitbox ~= nil then
		local runtimeId = enemyHitbox:GetEnemyIdFromPart(partRaw)
		if runtimeId ~= nil then
			local runtime = self:GetRuntime(runtimeId)
			if runtime ~= nil then
				return runtime
			end
		end
	end

	local parentModel = partRaw:FindFirstAncestorOfClass("Model")
	return self:GetUntimeFromModel(parentModel)
end

function NpcServiceServer.GetUntimeHurtbox(self: NpcServiceServer, runtime: NpcRuntime): (Vector3, Vector3)
	local model = runtime.slime.model
	local center: Vector3? = nil
	local size = DEFAULT_RUNTIME_HURTBOX_SIZE
	if model ~= nil then
		local ok, boundsCFrameOrError, boundsSize = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and typeof(boundsCFrameOrError) == "CFrame" and typeof(boundsSize) == "Vector3" then
			center = boundsCFrameOrError.Position
			size = CoerceSizeVector(boundsSize, DEFAULT_RUNTIME_HURTBOX_SIZE)
		end
	end

	if center == nil then
		local rootPart = InstanceUtils.GetModelRootPart(model)
		if rootPart ~= nil then
			center = rootPart.Position
			size = CoerceSizeVector(rootPart.Size, DEFAULT_RUNTIME_HURTBOX_SIZE)
		else
			local slimePosition = runtime.slime:GetPosition()
			if typeof(slimePosition) == "Vector3" then
				center = slimePosition
			else
				center = Vector3.new()
			end
		end
	end

	local paddedSize = Vector3.new(
		math.max(MIN_RUNTIME_HURTBOX_SIZE.X, size.X + DEFAULT_RUNTIME_HURTBOX_PADDING.X),
		math.max(MIN_RUNTIME_HURTBOX_SIZE.Y, size.Y + DEFAULT_RUNTIME_HURTBOX_PADDING.Y),
		math.max(MIN_RUNTIME_HURTBOX_SIZE.Z, size.Z + DEFAULT_RUNTIME_HURTBOX_PADDING.Z)
	)
	return center :: Vector3, paddedSize
end

function NpcServiceServer.DamageNpcsInBox(
	self: NpcServiceServer,
	queryCFrameRaw: any,
	querySizeRaw: any,
	damageRaw: any,
	source: any?,
	damageContextRaw: any?
): number
	if self.runtimes == nil then
		return 0
	end
	if typeof(queryCFrameRaw) ~= "CFrame" then
		return 0
	end
	if typeof(querySizeRaw) ~= "Vector3" then
		return 0
	end

	local damage = CoerceNumber(damageRaw, 0, 0, 100000)
	if damage <= 0 then
		return 0
	end

	local querySize = CoerceSizeVector(querySizeRaw, Vector3.new(0.05, 0.05, 0.05))
	local queryMin, queryMax = computeBoxAabb(queryCFrameRaw, querySize)
	local totalAppliedDamage = 0
	for _, runtime in self.runtimes do
		if runtime.isRemoving or not runtime.isAlive then
			continue
		end

		local hurtboxCenter, hurtboxSize = self:GetUntimeHurtbox(runtime)
		local hurtboxMin, hurtboxMax = computeBoxAabb(CFrame.new(hurtboxCenter), hurtboxSize)
		if not aabbIntersects(queryMin, queryMax, hurtboxMin, hurtboxMax) then
			continue
		end

		totalAppliedDamage += self:ApplyRuntimeDamage(runtime, damage, source, damageContextRaw)
	end

	return totalAppliedDamage
end

function NpcServiceServer.ApplyRuntimeDamage(
	self: NpcServiceServer,
	runtime: NpcRuntime?,
	rawDamage: any,
	source: any?,
	damageContextRaw: any?
): number
	if runtime == nil then
		return 0
	end
	if runtime.isRemoving or not runtime.isAlive then
		return 0
	end

	local slime = runtime.slime
	if slime.isAlive ~= true then
		return 0
	end

	local damage = CoerceNumber(rawDamage, 0, 0, 100000)
	if damage <= 0 then
		return 0
	end

	local appliedDamage = slime:TakeDamage(damage, source)
	if appliedDamage > 0 then
		self:SyncRuntimeVitals(runtime)
		self:UpdateRuntime(runtime, "externalDamage", false)
	end
	return appliedDamage
end

function NpcServiceServer.DamageNpcFromHitPart(
	self: NpcServiceServer,
	hitPartRaw: any,
	damageRaw: any,
	source: any?,
	damageContextRaw: any?
): number
	if self.runtimes == nil then
		return 0
	end

	local runtime = self:GetUntimeFromPart(hitPartRaw)
	if runtime == nil then
		return 0
	end

	return self:ApplyRuntimeDamage(runtime, damageRaw, source, damageContextRaw)
end

function NpcServiceServer.OnEnemyHitPlayer(self: NpcServiceServer, runtimeIdRaw: any, playerRaw: any, damageRaw: any)
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return
	end
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return
	end

	local runtime = self:GetRuntime(runtimeIdRaw)
	if runtime == nil then
		return
	end
	if runtime.isRemoving or not runtime.isAlive then
		return
	end

	local hpService = HpServiceServer :: any
	local defaultDamage = CoerceNumber(runtime.slime.damage, 0, 0, 100000)
	local damage = CoerceNumber(damageRaw, defaultDamage, 0, 100000)
	if damage <= 0 then
		return
	end

	local healthAfterDamage = hpService:DamagePlayer(playerRaw, damage)
	if healthAfterDamage == nil then
		return
	end

	runtime.lastEnemyHitAt = os.clock()
	self:UpdateRuntime(runtime, "enemyHitPlayer", false)
end

function NpcServiceServer.RegisterRuntimeEnemyHitbox(self: NpcServiceServer, runtime: NpcRuntime)
	local npcModule = self:GetRuntimeModule(runtime)
	local registerEnemyHitbox = if npcModule ~= nil then (npcModule :: any).RegisterEnemyHitbox else nil
	if typeof(registerEnemyHitbox) == "function" then
		registerEnemyHitbox(npcModule, self, runtime)
	end
end

function NpcServiceServer.UnregisterRuntimeEnemyHitbox(self: NpcServiceServer, runtime: NpcRuntime)
	local enemyHitboxId = runtime.enemyHitboxId
	if enemyHitboxId ~= nil and self.enemyHitbox ~= nil then
		self.enemyHitbox:UnregisterEnemy(enemyHitboxId)
	end
	runtime.enemyHitboxId = nil
end

function NpcServiceServer.GetActiveSlimeCount(self: NpcServiceServer): number
	local count = 0
	for _, runtime in self.runtimes do
		if runtime.npcType == "Slime" and runtime.isAlive and not runtime.isRemoving then
			count += 1
		end
	end
	return count
end

function NpcServiceServer.GetNextFallbackSpawnCFrame(self: NpcServiceServer): CFrame
	if #self.spawnCFrames <= 0 then
		self.spawnCFrames = NpcServiceUtils.CollectSpawnCFrames(math.max(1, self.slimeSpawnSettings.maxAlive))
		self.nextSpawnIndex = 1
	end

	local spawnCFrames = self.spawnCFrames
	local index = math.clamp(self.nextSpawnIndex, 1, #spawnCFrames)
	local nextCFrame = spawnCFrames[index]
	self.nextSpawnIndex += 1
	if self.nextSpawnIndex > #spawnCFrames then
		self.nextSpawnIndex = 1
	end

	return nextCFrame
end

function NpcServiceServer.GetSurfaceSpawnCFrame(
	self: NpcServiceServer,
	candidatePosition: Vector3,
	characterToIgnore: Model?
): CFrame?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeInstances: { Instance } = {}
	if characterToIgnore ~= nil then
		table.insert(excludeInstances, characterToIgnore)
	end
	local npcFolder = self.npcFolder :: Folder?
	if npcFolder ~= nil then
		table.insert(excludeInstances, npcFolder)
	end
	raycastParams.FilterDescendantsInstances = excludeInstances
	raycastParams.IgnoreWater = false

	local origin = candidatePosition + Vector3.new(0, DEFAULT_SPAWN_SURFACE_RAYCAST_HEIGHT, 0)
	local direction = Vector3.new(0, -(DEFAULT_SPAWN_SURFACE_RAYCAST_HEIGHT + DEFAULT_SPAWN_SURFACE_RAYCAST_DEPTH), 0)
	local hit = Workspace:Raycast(origin, direction, raycastParams)
	if hit == nil then
		return nil
	end

	local hitPart = hit.Instance
	if not hitPart:IsA("BasePart") then
		return nil
	end
	if not isValidSurfaceSpawnPart(hitPart) then
		return nil
	end
	if hit.Normal.Y < 0.4 then
		return nil
	end

	local snappedPosition =
		Vector3.new(candidatePosition.X, hit.Position.Y + DEFAULT_SPAWN_SURFACE_CLEARANCE, candidatePosition.Z)
	return CFrame.new(snappedPosition)
end

function NpcServiceServer.IsSpawnGapClear(
	self: NpcServiceServer,
	spawnCFrame: CFrame,
	characterToIgnore: Model?
): boolean
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local excludeInstances: { Instance } = {}
	if characterToIgnore ~= nil then
		table.insert(excludeInstances, characterToIgnore)
	end
	local npcFolder = self.npcFolder :: Folder?
	if npcFolder ~= nil then
		table.insert(excludeInstances, npcFolder)
	end
	overlapParams.FilterDescendantsInstances = excludeInstances
	overlapParams.MaxParts = DEFAULT_SPAWN_EMPTY_GAP_MAX_PARTS

	local queryCenter = spawnCFrame.Position
		+ Vector3.new(0, DEFAULT_SPAWN_EMPTY_GAP_HALF_EXTENTS.Y + DEFAULT_SPAWN_EMPTY_GAP_FLOOR_BUFFER, 0)
	local parts =
		Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), DEFAULT_SPAWN_EMPTY_GAP_HALF_EXTENTS * 2, overlapParams)
	for _, part in parts do
		if part:IsA("BasePart") and part.CanCollide then
			return false
		end
	end

	return true
end

function NpcServiceServer.GetNextPlayerRelativeSpawnCFrame(self: NpcServiceServer): CFrame?
	local players = Players:GetPlayers()
	if #players <= 0 then
		return nil
	end

	local startIndex = self.random:NextInteger(1, #players)
	for indexOffset = 0, #players - 1 do
		local index = ((startIndex + indexOffset - 1) % #players) + 1
		local player = players[index]
		local character = player.Character
		if character == nil then
			continue
		end

		local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
		local rootPart = if rootPartCandidate and rootPartCandidate:IsA("BasePart") then rootPartCandidate else nil
		if rootPart == nil then
			local primaryPart = character.PrimaryPart
			if primaryPart and primaryPart:IsA("BasePart") then
				rootPart = primaryPart
			end
		end
		if rootPart == nil then
			continue
		end

		for _ = 1, DEFAULT_PLAYER_RELATIVE_SPAWN_ATTEMPTS_PER_PLAYER do
			local spawnSign = if self.random:NextNumber() < 0.5 then -1 else 1
			local zOffset =
				self.random:NextNumber(DEFAULT_PLAYER_RELATIVE_MIN_Z_OFFSET, DEFAULT_PLAYER_RELATIVE_MAX_Z_OFFSET)
			local yOffset = self.random:NextNumber(0, DEFAULT_PLAYER_RELATIVE_Y_OFFSET)
			local spawnPosition = rootPart.Position + Vector3.new(0, yOffset, spawnSign * zOffset)

			local snappedSpawnCFrame = self:GetSurfaceSpawnCFrame(spawnPosition, character)
			if
				snappedSpawnCFrame ~= nil
				and not self:IsCorruptionBiomePosition(snappedSpawnCFrame.Position)
				and self:IsSpawnGapClear(snappedSpawnCFrame, character)
			then
				return snappedSpawnCFrame
			end
		end
	end

	return nil
end

function NpcServiceServer.GetNearestPlayerDistance(self: NpcServiceServer, position: Vector3): number?
	local nearestDistance: number? = nil

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end

		local rootPart = InstanceUtils.GetModelRootPart(character)
		if rootPart == nil then
			continue
		end

		local distance = (rootPart.Position - position).Magnitude
		if nearestDistance == nil or distance < nearestDistance then
			nearestDistance = distance
		end
	end

	return nearestDistance
end

function NpcServiceServer.DespawnFarRuntimes(self: NpcServiceServer, reasonRaw: any): number
	local settings = self.slimeSpawnSettings
	if not settings.enabled then
		return 0
	end

	local despawnDistance = CoerceNumber(settings.despawnDistance, 0, 0, 100000)
	if despawnDistance <= 0 then
		return 0
	end

	local removalIds = {}
	local distanceThreshold = despawnDistance + DEFAULT_DESPAWN_DISTANCE_BUFFER
	for runtimeId, runtime in self.runtimes do
		if runtime.isRemoving or not runtime.isAlive or runtime.slime.isAlive ~= true then
			continue
		end

		local position = runtime.slime:GetPosition()
		if position == nil then
			table.insert(removalIds, runtimeId)
			continue
		end

		local nearestDistance = self:GetNearestPlayerDistance(position)
		if nearestDistance == nil or nearestDistance > distanceThreshold then
			table.insert(removalIds, runtimeId)
		end
	end

	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "tooFarFromPlayers"
	for _, runtimeId in removalIds do
		self:RemoveRuntime(runtimeId, reason)
	end

	return #removalIds
end

function NpcServiceServer.GetNextSpawnCFrame(self: NpcServiceServer): CFrame?
	return self:GetNextPlayerRelativeSpawnCFrame()
end

function NpcServiceServer.CreateDefaultSpawnConfigAt(self: NpcServiceServer, spawnCFrame: CFrame): SlimeSpawnConfig?
	if self:IsCorruptionBiomePosition(spawnCFrame.Position) then
		return nil
	end

	local configs = NpcServiceUtils.CreateDefaultSlimeSpawnConfigs({ spawnCFrame })
	if #configs <= 0 then
		return nil
	end
	return configs[1]
end

function NpcServiceServer.GetDebugSpawnCFrameForPlayer(self: NpcServiceServer, playerRaw: any, indexRaw: any): CFrame?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return self:GetNextSpawnCFrame()
	end

	local character = playerRaw.Character
	if character == nil then
		return self:GetNextSpawnCFrame()
	end

	local rootPart = InstanceUtils.GetModelRootPart(character)
	if rootPart == nil then
		return self:GetNextSpawnCFrame()
	end

	local index = math.max(1, math.floor(CoerceNumber(indexRaw, 1, 1, 10 ^ 6)))
	local laneIndex = math.floor((index - 1) / 2)
	local directionSign = if index % 2 == 1 then 1 else -1
	local zOffset = DEFAULT_PLAYER_RELATIVE_MIN_Z_OFFSET + laneIndex * 8
	local yOffset = DEFAULT_PLAYER_RELATIVE_Y_OFFSET + math.min(laneIndex, 4)
	local candidatePosition = rootPart.Position + Vector3.new(0, yOffset, directionSign * zOffset)
	local snappedSpawnCFrame = self:GetSurfaceSpawnCFrame(candidatePosition, character)

	if
		snappedSpawnCFrame ~= nil
		and not self:IsCorruptionBiomePosition(snappedSpawnCFrame.Position)
		and self:IsSpawnGapClear(snappedSpawnCFrame, character)
	then
		return snappedSpawnCFrame
	end

	return self:GetNextSpawnCFrame()
end

function NpcServiceServer.SpawnDebugNpcById(
	self: NpcServiceServer,
	npcIdRaw: any,
	playerRaw: any,
	indexRaw: any
): (NpcRuntime?, string?)
	if npcIdRaw ~= "GreenSlime" then
		return nil, "unsupported_npc"
	end

	local spawnCFrame = self:GetDebugSpawnCFrameForPlayer(playerRaw, indexRaw)
	if spawnCFrame == nil then
		return nil, "missing_spawn_cframe"
	end

	local spawnConfig = self:CreateDefaultSpawnConfigAt(spawnCFrame)
	if spawnConfig == nil then
		return nil, "invalid_spawn_configuration"
	end

	spawnConfig.slimeType = "GreenSlime"
	spawnConfig.displayName = "Green Slime"
	spawnConfig.modelName = "GreenSlime"

	local runtime = self:SpawnSlime(spawnConfig)
	if runtime == nil then
		return nil, "spawn_failed"
	end

	return runtime, nil
end

function NpcServiceServer.TryAutoSpawnSlime(self: NpcServiceServer, reasonRaw: any): NpcRuntime?
	local settings = self.slimeSpawnSettings
	if not settings.enabled then
		return nil
	end

	self:DespawnFarRuntimes("spawnPrecheck")

	local activeCount = self:GetActiveSlimeCount()
	if activeCount >= settings.maxAlive then
		return nil
	end

	if settings.spawnChance <= 0 then
		return nil
	end

	local roll = self.random:NextNumber()
	if roll >= settings.spawnChance then
		return nil
	end

	local spawnCFrame = self:GetNextSpawnCFrame()
	if spawnCFrame == nil then
		return nil
	end
	local spawnConfig = self:CreateDefaultSpawnConfigAt(spawnCFrame)
	if spawnConfig == nil then
		return nil
	end

	local runtime = self:SpawnSlime(spawnConfig)
	if runtime ~= nil then
		local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "autoSpawn"
		self:TransitionRuntimeState(runtime, "Spawning", reason, true)
	end
	return runtime
end

function NpcServiceServer.CreateStatePayload(self: NpcServiceServer): { NpcSnapshot }
	local snapshots = {}
	for _, runtime in self.runtimes do
		table.insert(snapshots, self:CreateSnapshot(runtime))
	end
	return snapshots
end

function NpcServiceServer.Broadcast(self: NpcServiceServer, methodName: string, ...: any)
	local recipients = {}
	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			recipients[#recipients + 1] = player
		end
	end
	fireForPlayers(recipients, methodName, ...)
end

function NpcServiceServer.PushState(self: NpcServiceServer, player: Player)
	sendPacket(player, NpcServiceUtils.CLIENT_METHOD_APPLY_STATE, self:CreateStatePayload())
end

function NpcServiceServer.RequestSync(self: NpcServiceServer, player: Player)
	self:PushState(player)
end

function NpcServiceServer.TransitionRuntimeState(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	nextState: NpcRuntimeState,
	reasonRaw: any,
	forceTransition: boolean?
): boolean
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "unknown"
	local currentState = runtime.state
	if nextState == currentState then
		runtime.lastReason = reason
		runtime.updatedAt = os.clock()
		return true
	end

	if forceTransition ~= true and not NpcServiceUtils.CanTransition(runtime.stateGraph, currentState, nextState) then
		return false
	end

	runtime.state = nextState
	runtime.lastReason = reason
	runtime.updatedAt = os.clock()

	local payload = self:CreateSnapshot(runtime) :: any
	payload.previousState = currentState
	self:Broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED, payload)
	return true
end

function NpcServiceServer.RemoveRuntime(self: NpcServiceServer, runtimeIdRaw: any, reasonRaw: any)
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return
	end

	local runtime = self:GetRuntime(runtimeIdRaw)
	if runtime == nil then
		return
	end

	runtime.isRemoving = true
	self.runtimes[runtimeIdRaw] = nil
	self:UnregisterRuntimeEnemyHitbox(runtime)

	local model = runtime.slime.model
	if model and self.runtimesByModel[model] == runtime then
		self.runtimesByModel[model] = nil
	end

	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "removed"
	self:TransitionRuntimeState(runtime, "Dead", reason, true)

	if not (runtime.slime :: any)._isDestroyed then
		runtime.slime:Destroy()
	end

	runtime.janitor:Destroy()
	self:Broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_REMOVED, runtimeIdRaw)
end

function NpcServiceServer.GetUntimeState(self: NpcServiceServer, runtime: NpcRuntime): NpcRuntimeState
	local npcModule = self:GetRuntimeModule(runtime)
	local GetUntimeState = if npcModule ~= nil then (npcModule :: any).GetUntimeState else nil
	if typeof(GetUntimeState) == "function" then
		return GetUntimeState(npcModule, self, runtime)
	end

	local npc = runtime.npc
	if not runtime.isAlive then
		return "Dead"
	end
	if not runtime.biomeReady then
		return "AwaitingBiome"
	end
	if os.clock() - runtime.lastEnemyHitAt <= 0.25 then
		return "Attacking"
	end

	local currentTarget = npc.currentTarget
	local hasTarget = currentTarget ~= nil and npc:IsTargetValid(currentTarget)
	if hasTarget then
		if npc:CanAttackTarget(currentTarget) then
			return "Attacking"
		end
		return "Aggro"
	end

	if npc.state == "Moving" then
		return "Searching"
	end
	return "Idle"
end

function NpcServiceServer.RefreshRuntimeBiome(self: NpcServiceServer, runtime: NpcRuntime)
	local world = self:GetWorld()
	if world == nil then
		runtime.biomeName = "Unknown"
		runtime.biomeReady = false
		return
	end

	local position = runtime.slime:GetPosition()
	if position == nil then
		runtime.biomeName = "Unknown"
		runtime.biomeReady = false
		return
	end

	local biomeName, biomeReady = NpcServiceUtils.GetBiomeNameFromWorld(world, position)
	runtime.biomeName = biomeName
	runtime.biomeReady = biomeReady
end

function NpcServiceServer.UpdateRuntime(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	reason: string,
	refreshBiome: boolean
)
	if runtime.isRemoving then
		return
	end

	local previousState = runtime.state
	local previousHp = runtime.hp
	local previousMaxHp = runtime.maxHp
	local previousAlive = runtime.isAlive

	self:SyncRuntimeVitals(runtime)
	if self.enemyHitbox ~= nil then
		self.enemyHitbox:SetEnemyAlive(runtime.id, runtime.isAlive)
	end

	if refreshBiome then
		self:RefreshRuntimeBiome(runtime)
	end

	local desiredState = self:GetUntimeState(runtime)
	local transitioned = self:TransitionRuntimeState(runtime, desiredState, reason, false)
	local snapshot = if transitioned then self:CreateSnapshot(runtime) else nil
	local spriteStateKey = if snapshot ~= nil then getSnapshotSpriteStateKey(snapshot) else runtime.lastSpriteStateKey
	if transitioned and runtime.state ~= previousState then
		runtime.lastSpriteStateKey = spriteStateKey
	end
	local shouldBroadcastSameState = transitioned
		and runtime.state == previousState
		and (
			runtime.hp ~= previousHp
			or runtime.maxHp ~= previousMaxHp
			or runtime.isAlive ~= previousAlive
			or spriteStateKey ~= runtime.lastSpriteStateKey
		)
	if shouldBroadcastSameState then
		local payload = snapshot :: any
		payload.previousState = previousState
		self:Broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED, payload)
		runtime.lastSpriteStateKey = spriteStateKey
	end
end

function NpcServiceServer.TrackRuntime(self: NpcServiceServer, runtime: NpcRuntime)
	self.runtimes[runtime.id] = runtime

	local model = runtime.slime.model
	if model ~= nil then
		self.runtimesByModel[model] = runtime
		applyRuntimeModelAttributes(runtime, model)
	end

	runtime.janitor:GiveChore(runtime.slime.signals.spawned:Connect(function(modelInstance: Model)
		self.runtimesByModel[modelInstance] = runtime
		applyRuntimeModelAttributes(runtime, modelInstance)
		self:ApplyRuntimeNpcCollisionGroup(runtime)
		if self.enemyHitbox ~= nil then
			self.enemyHitbox:SetEnemyModel(runtime.id, modelInstance)
			self.enemyHitbox:SetEnemyAlive(runtime.id, runtime.slime.isAlive)
		end
		self:SyncRuntimeVitals(runtime)
		self:UpdateRuntime(runtime, "spawned", true)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.stateChanged:Connect(function()
		self:UpdateRuntime(runtime, "npcStateChanged", false)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.targetChanged:Connect(function()
		self:UpdateRuntime(runtime, "targetChanged", false)
	end))

	runtime.janitor:GiveChore(runtime.npc.signals.attacked:Connect(function()
		runtime.lastEnemyHitAt = os.clock()
		self:UpdateRuntime(runtime, "npcAttacked", false)
	end))

	runtime.janitor:GiveChore(
		runtime.slime.signals.damaged:Connect(function(damageAmount: number, _source: any?, hpRaw: number?)
			local _ = damageAmount
			local _hp = hpRaw
			self:SyncRuntimeVitals(runtime)
			self:UpdateRuntime(runtime, "damaged", false)
		end)
	)

	runtime.janitor:GiveChore(runtime.slime.signals.died:Connect(function()
		runtime.isAlive = false
		runtime.hp = 0
		if self.enemyHitbox ~= nil then
			self.enemyHitbox:SetEnemyAlive(runtime.id, false)
		end
		local npcModule = self:GetRuntimeModule(runtime)
		local spawnLoot = if npcModule ~= nil then (npcModule :: any).SpawnLoot else nil
		if typeof(spawnLoot) == "function" then
			spawnLoot(npcModule, self, runtime)
		end
		self:TransitionRuntimeState(runtime, "Dead", "died", true)
		task.delay(2, function()
			local activeRuntime = self:GetRuntime(runtime.id)
			if activeRuntime == nil then
				return
			end
			if activeRuntime.slime.isAlive then
				return
			end
			self:RemoveRuntime(runtime.id, "deathCleanup")
		end)
	end))

	local runtimeModel = runtime.slime.model
	if runtimeModel then
		runtime.janitor:GiveChore(runtimeModel.Destroying:Connect(function()
			if runtime.isRemoving then
				return
			end
			self:RemoveRuntime(runtime.id, "modelDestroyed")
		end))
	end

	self:ApplyRuntimeNpcCollisionGroup(runtime)
	self:RegisterRuntimeEnemyHitbox(runtime)
end

function NpcServiceServer.SpawnSlime(self: NpcServiceServer, spawnConfig: SlimeSpawnConfig): NpcRuntime?
	local npcModule = self.npcModulesByType.Slime
	if npcModule == nil or typeof((npcModule :: any).Spawn) ~= "function" then
		return nil
	end
	local runtime = (npcModule :: any):Spawn(self, spawnConfig)
	return runtime :: NpcRuntime?
end

function NpcServiceServer.SpawnInitialSlimes(self: NpcServiceServer)
	local settings = self.slimeSpawnSettings
	if not settings.enabled then
		return
	end

	local maxInitial = math.min(settings.initialSpawnCount, settings.maxAlive)
	for _ = 1, maxInitial do
		local spawnCFrame = self:GetNextSpawnCFrame()
		if spawnCFrame == nil then
			continue
		end
		local spawnConfig = self:CreateDefaultSpawnConfigAt(spawnCFrame)
		if spawnConfig ~= nil then
			self:SpawnSlime(spawnConfig)
		end
	end
end

function NpcServiceServer.OnHeartbeat(self: NpcServiceServer, dt: number)
	local settings = self.slimeSpawnSettings
	self.despawnRefreshAccumulator += dt
	if self.despawnRefreshAccumulator >= DEFAULT_DESPAWN_CHECK_INTERVAL then
		self.despawnRefreshAccumulator = 0
		self:DespawnFarRuntimes("heartbeatDistance")
	end

	if settings.enabled then
		self.spawnAccumulator += dt
		while self.spawnAccumulator >= settings.spawnRate do
			self.spawnAccumulator -= settings.spawnRate
			self:TryAutoSpawnSlime("spawnRateTick")
		end
	end

	self.stateRefreshAccumulator += dt
	self.biomeRefreshAccumulator += dt

	local shouldRefreshState = self.stateRefreshAccumulator >= DEFAULT_STATE_REFRESH_INTERVAL
	local shouldRefreshBiome = self.biomeRefreshAccumulator >= DEFAULT_BIOME_REFRESH_INTERVAL
	if not shouldRefreshState and not shouldRefreshBiome then
		return
	end

	if shouldRefreshState then
		self.stateRefreshAccumulator = 0
	end
	if shouldRefreshBiome then
		self.biomeRefreshAccumulator = 0
		self:GetWorld()
	end

	for _, runtime in self.runtimes do
		self:UpdateRuntime(runtime, "heartbeat", shouldRefreshBiome)
	end
end

function NpcServiceServer.Init(self: NpcServiceServer)
	bindPackets(self)
	self.npcModulesByType = {}
	self:InitNpcModules()
	self.runtimes = {}
	self.runtimesByModel = {}
	self.world = nil
	self.lootService = LootServiceServer :: any
	self.collisionGroupsReady = false
	self.playerCharacterAddedConnections = {}
	self:EnsureCollisionGroups()
	self.enemyHitbox = EnemyHitbox.New({
		cellSize = 8,
		playerCellSize = 8,
	})
	self.npcFolder = self:EnsureNpcFolder()
	local rawNpcSettings = if typeof(Configs) == "table" then (Configs :: any).npcSettings else nil
	local rawSlimeSettings = if typeof(rawNpcSettings) == "table" then (rawNpcSettings :: any).slime else nil
	self.slimeSpawnSettings = NpcServiceUtils.CoerceSlimeSpawnSettings(rawSlimeSettings, nil)
	self.spawnCFrames = NpcServiceUtils.CollectSpawnCFrames(math.max(1, self.slimeSpawnSettings.maxAlive))
	self.nextSpawnIndex = 1
	self.spawnAccumulator = 0
	self.despawnRefreshAccumulator = 0
	self.random = Random.new()
	self.stateRefreshAccumulator = 0
	self.biomeRefreshAccumulator = 0
	self.binders = NevermoreSupport.GetService(BinderSupportServer)

	for _, player in Players:GetPlayers() do
		self:BindPlayerCollisionGroup(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:BindPlayerCollisionGroup(player)
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			self:PushState(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UnbindPlayerCollisionGroup(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:OnHeartbeat(dt)
	end)

	self:SpawnInitialSlimes()
end

function NpcServiceServer.Destroy(self: NpcServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player, connection in self.playerCharacterAddedConnections do
		if connection ~= nil then
			connection:Disconnect()
		end
		self.playerCharacterAddedConnections[player] = nil
	end

	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	local runtimeIds = {}
	for runtimeId in self.runtimes do
		table.insert(runtimeIds, runtimeId)
	end
	for _, runtimeId in runtimeIds do
		self:RemoveRuntime(runtimeId, "serviceDestroyed")
	end

	if self.enemyHitbox ~= nil then
		self.enemyHitbox:Destroy()
		self.enemyHitbox = nil
	end

	self.lootService = nil
end

type NpcServiceServer = typeof(NpcServiceServer) & {
	npcModulesByType: { [string]: any },
	runtimes: { [string]: NpcRuntime },
	runtimesByModel: { [Model]: NpcRuntime },
	enemyHitbox: EnemyHitboxManager?,
	lootService: LootServiceServerObject?,
	collisionGroupsReady: boolean,
	playerCharacterAddedConnections: { [Player]: RBXScriptConnection? },
	world: any?,
	npcFolder: Folder,
	slimeSpawnSettings: SlimeSpawnSettings,
	spawnCFrames: { CFrame },
	nextSpawnIndex: number,
	spawnAccumulator: number,
	despawnRefreshAccumulator: number,
	random: Random,
	stateRefreshAccumulator: number,
	biomeRefreshAccumulator: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
	binders: any,
}

return NpcServiceServer :: NpcServiceServer
