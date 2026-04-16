--!strict
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local Bounds = require(script:FindFirstAncestor("game").Shared.Modules.Math.Bounds)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local StringUtils = require(script:FindFirstAncestor("game").Shared.Modules.Core.StringUtils)
local InstanceUtils = require(script:FindFirstAncestor("game").Shared.Modules.Platform.InstanceUtils)
local Slime = require(script:FindFirstAncestor("game").Shared.Classes.Npc.AiTypes.slime)
local EnemyHitbox = require(script:FindFirstAncestor("game").Shared.Classes.EnemyHitbox)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcService.NpcServiceUtils)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpService.HpServiceServer)
local AudioServiceServer = require(script:FindFirstAncestor("game").Server.Services.AudioService.AudioServiceServer)
local LootServiceServer = require(script:FindFirstAncestor("game").Server.Services.LootService.LootServiceServer)
local GoreServiceServer = require(script:FindFirstAncestor("game").Server.Services.GoreService.GoreServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local WorldGenerationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldGenerationService.WorldGenerationServiceServer)

type SlimeClass = Slime.Slime
type RuntimeNpc = SlimeClass
type EnemyHitboxManager = EnemyHitbox.EnemyHitbox
type NpcType = NpcServiceUtils.NpcType
type NpcRuntimeState = NpcServiceUtils.NpcRuntimeState
type BiomeName = NpcServiceUtils.BiomeName
type AnimationEventAction = NpcServiceUtils.AnimationEventAction
type AnimationEventsByTrack = NpcServiceUtils.AnimationEventsByTrack
type StateMachineGraph = NpcServiceUtils.StateMachineGraph
type NpcSnapshot = NpcServiceUtils.NpcSnapshot
type SlimeSpawnConfig = NpcServiceUtils.SlimeSpawnConfig
type SlimeSpawnSettings = NpcServiceUtils.SlimeSpawnSettings
type HpServiceServerObject = {
	damagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}
type AudioServiceServerObject = {
	playSfxForAll: (self: AudioServiceServerObject, soundAssetIdRaw: any, optionsRaw: any) -> (),
}
type LootServiceServerObject = {
	spawnDropsFromSource: (
		self: LootServiceServerObject,
		sourceRaw: any,
		originRaw: any,
		optionsRaw: any
	) -> { any },
}
type GoreServiceServerObject = {
	registerNpcEntity: (self: GoreServiceServerObject, runtimeIdRaw: any, modelRaw: any, configRaw: any?) -> boolean,
	unregisterNpcEntity: (self: GoreServiceServerObject, runtimeIdRaw: any) -> boolean,
	onNpcDamaged: (self: GoreServiceServerObject, runtimeIdRaw: any, originRaw: any, damageRaw: any?) -> boolean,
	onNpcDied: (self: GoreServiceServerObject, runtimeIdRaw: any, originRaw: any) -> boolean,
	emitNpcSlimeBlood: (
		self: GoreServiceServerObject,
		runtimeIdRaw: any,
		originRaw: any,
		emitCountRaw: any?,
		followDurationRaw: any?,
		dropletAmountRaw: any?
	) -> boolean,
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type NpcRuntime = {
	id: string,
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
	animationEvents: AnimationEventsByTrack,
	stateGraph: StateMachineGraph,
	updatedAt: number,
	janitor: JanitorClass,
	animationEventJanitor: JanitorClass,
	animationEventsBound: boolean,
	isRemoving: boolean,
	deathGoreEmitted: boolean,
	enemyHitboxId: string?,
	lastEnemyHitAt: number,
	lastPreDamageSlimeBloodAt: number,
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
local DEFAULT_SLIME_HP = 14
local DEFAULT_SLIME_DAMAGE_BLOOD_AMOUNT = 50
local DEFAULT_SLIME_DEATH_BLOOD_AMOUNT = 100
local DEFAULT_SLIME_BLOOD_POOL_SIZE = NumberRange.new(0.95, 1.7)
local DEFAULT_SLIME_BLOOD_POOL_SIZE_Y = NumberRange.new(0.16, 0.28)
local DEFAULT_SLIME_BLOOD_POOL_STARTING_SIZE = Vector3.new(0.2, 0.42, 0.2)
local DEFAULT_SLIME_BLOOD_POOL_MAX_SIZE = 1.8
local DEFAULT_SLIME_BLOOD_POOL_EXPANSE_DIVIDER = 2
local DEFAULT_RUNTIME_HURTBOX_SIZE = Vector3.new(4, 3, 4)
local DEFAULT_RUNTIME_HURTBOX_PADDING = Vector3.new(1.2, 0.5, 1.2)
local MIN_RUNTIME_HURTBOX_SIZE = Vector3.new(3.5, 2.75, 3.5)
local PLAYER_COLLISION_GROUP = "PlayersCharacters"
local ENEMY_COLLISION_GROUP = "NpcEnemies"
local WORLD_GENERATION_FOLDER_NAME = "WorldGeneration"
local EFFECTS_JUNK_FOLDER_NAME = "EffectsJunk"
local BIOME_TYPE_CORRUPTION = 2
local DEFAULT_SLIME_BLOOD_PARTICLES_PER_EMITTER = 18
local DEFAULT_SLIME_DEATH_SLIME_BLOOD_PARTICLES_PER_EMITTER = 30
local DEFAULT_SLIME_DEATH_SLIME_BLOOD_DROPLET_AMOUNT = 70
local DEFAULT_SLIME_BLOOD_CLEANUP_BUFFER_SECONDS = 1.5
local MIN_SLIME_BLOOD_CLEANUP_SECONDS = 2
local SLIME_BLOOD_EMIT_WINDOW_SECONDS = 0.1
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_EMIT_COUNT = 22
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_FOLLOW_DURATION = 0.1
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_DROPLET_AMOUNT = 8
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_LOW_HP_RATIO = 0.35
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_MIN_HP = 3
local DEFAULT_PRE_DAMAGE_SLIME_BLOOD_COOLDOWN = 0.12
local DEFAULT_FALLBACK_SLIME_BLOOD_COLOR = Color3.fromRGB(39, 145, 58)
local MISSING_SLIME_BLOOD_TEMPLATE_WARNING =
	"[NpcService] Missing slime blood template. Expected ReplicatedStorage.Assets.Effects.SlimeBlood. Using fallback emitter."
local NPC_AUDIO = (AudioRegistry :: any).Npcs or {}
local SLIME_AUDIO = (NPC_AUDIO :: any).Slimes or {}
local DEFAULT_SLIME_AUDIO_BINDINGS = (SLIME_AUDIO :: any).Default or {}
local GREEN_SLIME_AUDIO_BINDINGS = (SLIME_AUDIO :: any).GreenSlime or DEFAULT_SLIME_AUDIO_BINDINGS
local SLIME_GEL_DROP_ITEM_ID = "Gel"
local SLIME_GEL_DROP_AMOUNT = 1
local SLIME_AUDIO_KEY_BY_TOKEN = {
	jump = "Jump",
	land = "Land",
	hurt = "Hurt",
	hit = "Hurt",
	death = "Death",
}

local function isSlimeRuntime(runtime: NpcRuntime): boolean
	return runtime.npcType == "Slime"
end

local function fireForPlayers(networker: Networker.Server, players: { Player }, methodName: string, ...: any)
	for _, player in players do
		networker:fire(player, methodName, ...)
	end
end

local function resolveAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local nextAnimator = Instance.new("Animator")
	nextAnimator.Name = "Animator"
	nextAnimator.Parent = humanoid
	return nextAnimator
end

local function resolveAnimatorFromModel(model: Model): Animator?
	local animationController = model:FindFirstChildOfClass("AnimationController")
	if animationController == nil then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("AnimationController") then
				animationController = descendant
				break
			end
		end
	end

	if animationController == nil then
		return nil
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if animator ~= nil then
		return animator
	end

	local nextAnimator = Instance.new("Animator")
	nextAnimator.Name = "Animator"
	nextAnimator.Parent = animationController
	return nextAnimator
end

local function asAnimationTrack(value: any): AnimationTrack?
	if value == nil then
		return nil
	end

	local ok = pcall(function()
		local _ = (value :: any).KeyframeReached
	end)
	if ok then
		return value :: AnimationTrack
	end
	return nil
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
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

local function sanitizeSizeVector(sizeRaw: any, fallback: Vector3): Vector3
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
	local size = sanitizeSizeVector(sizeRaw, Vector3.new(0.05, 0.05, 0.05))
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
	return Bounds.intersects(Bounds.new(aMin, aMax), Bounds.new(bMin, bMax))
end

local function setModelCollisionGroup(model: Model, collisionGroup: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = collisionGroup
		end
	end
end

local function getOrCreateEffectsJunkFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(EFFECTS_JUNK_FOLDER_NAME)
end

local function resolveSlimeBloodEffectTemplate(): BasePart?
	local directTemplate = InstanceUtils.resolveBasePartByPath(ReplicatedStorage, { "Assets", "Effects", "SlimeBlood" })
	if directTemplate ~= nil then
		return directTemplate
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = if assets ~= nil then assets:FindFirstChild("Effects") else nil

	if effects ~= nil then
		local directChild = effects:FindFirstChild("SlimeBlood")
		local directPart = InstanceUtils.resolveFirstBasePart(directChild)
		if directPart ~= nil then
			return directPart
		end

		local nestedByToken = InstanceUtils.findDescendantBasePartByToken(effects, "SlimeBlood")
		if nestedByToken ~= nil then
			return nestedByToken
		end
	end

	local anywhereInReplicatedStorage = InstanceUtils.findDescendantBasePartByToken(ReplicatedStorage, "SlimeBlood")
	if anywhereInReplicatedStorage ~= nil then
		return anywhereInReplicatedStorage
	end

	if effects ~= nil then
		local bloodDirectPart = InstanceUtils.resolveFirstBasePart(effects:FindFirstChild("Blood"))
		if bloodDirectPart ~= nil then
			return bloodDirectPart
		end

		local bloodNestedPart = InstanceUtils.findDescendantBasePartByToken(effects, "Blood")
		if bloodNestedPart ~= nil then
			return bloodNestedPart
		end
	end

	return nil
end

local function createFallbackSlimeBloodEffect(): BasePart
	local part = Instance.new("Part")
	part.Name = "SlimeBlood"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Color = DEFAULT_FALLBACK_SLIME_BLOOD_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FallbackSlimeBloodEmitter"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(DEFAULT_FALLBACK_SLIME_BLOOD_COLOR)
	emitter.Lifetime = NumberRange.new(0.25, 0.9)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Drag = 3
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = part

	return part
end

local function applyRuntimeModelAttributes(runtime: NpcRuntime, model: Model?)
	if model == nil then
		return
	end

	NpcServiceUtils.applyRuntimeModelAttributes(model, runtime.id, runtime.npcType, runtime.displayName)
end

local function isValidSurfaceSpawnPart(part: BasePart): boolean
	if not part.CanCollide then
		return false
	end
	if part.LocalTransparencyModifier >= 0.99 then
		return false
	end

	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_GENERATION_FOLDER_NAME)
	if worldFolder == nil then
		return true
	end
	return part:IsDescendantOf(worldFolder)
end

function NpcServiceServer.EnsureNpcFolder(self: NpcServiceServer): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(DEFAULT_NPC_FOLDER_NAME)
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
	self:ensureCollisionGroups()
	setModelCollisionGroup(character, PLAYER_COLLISION_GROUP)
end

function NpcServiceServer.BindPlayerCollisionGroup(self: NpcServiceServer, player: Player)
	self:applyPlayerCollisionGroup(player)

	local previousConnection = self.playerCharacterAddedConnections[player]
	if previousConnection ~= nil then
		previousConnection:Disconnect()
	end

	self.playerCharacterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		self:ensureCollisionGroups()
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
	self:ensureCollisionGroups()
	setModelCollisionGroup(model, ENEMY_COLLISION_GROUP)
end

local function resolveSlimeAudioBindings(runtime: NpcRuntime): { [string]: any }
	if isSlimeRuntime(runtime) and (runtime.slime :: any).isGreenSlime then
		return GREEN_SLIME_AUDIO_BINDINGS
	end
	return DEFAULT_SLIME_AUDIO_BINDINGS
end

function NpcServiceServer.ResolveRuntimeSoundSource(self: NpcServiceServer, runtime: NpcRuntime, soundNameRaw: any): any?
	if typeof(soundNameRaw) ~= "string" or soundNameRaw == "" then
		return nil
	end

	local token = StringUtils.compactToken(soundNameRaw)
	local soundKey = if isSlimeRuntime(runtime) then SLIME_AUDIO_KEY_BY_TOKEN[token] else nil
	if soundKey ~= nil then
		local soundAssetIds = AudioServiceUtils.collectSoundAssetIds(resolveSlimeAudioBindings(runtime)[soundKey])
		if #soundAssetIds > 0 then
			return soundAssetIds[self.random:NextInteger(1, #soundAssetIds)]
		end
	end

	return NpcServiceUtils.findDescendantByNameOfClass(runtime.slime.model, soundNameRaw, "Sound")
end

function NpcServiceServer.PlayRuntimeNamedSound(self: NpcServiceServer, runtime: NpcRuntime, soundName: string): boolean
	local played = self:tryPlaySoundAction(runtime, {
		kind = "sound",
		soundName = soundName,
		autoDestroy = true,
	})
	return played
end

function NpcServiceServer.ResolveWorld(self: NpcServiceServer): any?
	local getWorldMethod = (WorldGenerationServiceServer :: any).getWorld
	if typeof(getWorldMethod) ~= "function" then
		return nil
	end

	local ok, worldOrError = pcall(function()
		return (WorldGenerationServiceServer :: any):getWorld()
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
	local world = self:resolveWorld()
	if world == nil then
		return false
	end

	local getBiomeTypeAtWorldPositionMethod = (world :: any).getBiomeTypeAtWorldPosition
	if typeof(getBiomeTypeAtWorldPositionMethod) ~= "function" then
		return false
	end

	local ok, biomeTypeOrError = pcall(function()
		return (world :: any):getBiomeTypeAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeTypeOrError) ~= "number" then
		return false
	end

	return math.floor(biomeTypeOrError) == BIOME_TYPE_CORRUPTION
end

function NpcServiceServer.CreateSnapshot(self: NpcServiceServer, runtime: NpcRuntime): NpcSnapshot
	self:syncRuntimeVitals(runtime)
	local position = runtime.slime:getPosition()
	return {
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
end

function NpcServiceServer.SyncRuntimeVitals(self: NpcServiceServer, runtime: NpcRuntime)
	local slime = runtime.slime
	runtime.maxHp = slime.maxHp
	runtime.hp = math.clamp(slime.hp, 0, slime.maxHp)
	runtime.isAlive = slime.isAlive
end

function NpcServiceServer.GetRuntime(self: NpcServiceServer, runtimeId: string): NpcRuntime?
	return self.runtimes[runtimeId]
end

function NpcServiceServer.ResolveRuntimeFromModel(self: NpcServiceServer, modelRaw: any): NpcRuntime?
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

function NpcServiceServer.ResolveRuntimeFromPart(self: NpcServiceServer, partRaw: any): NpcRuntime?
	if typeof(partRaw) ~= "Instance" or not partRaw:IsA("BasePart") then
		return nil
	end

	local enemyHitbox = self.enemyHitbox
	if enemyHitbox ~= nil then
		local runtimeId = enemyHitbox:resolveEnemyIdFromPart(partRaw)
		if runtimeId ~= nil then
			local runtime = self:getRuntime(runtimeId)
			if runtime ~= nil then
				return runtime
			end
		end
	end

	local parentModel = partRaw:FindFirstAncestorOfClass("Model")
	return self:resolveRuntimeFromModel(parentModel)
end

function NpcServiceServer.ResolveRuntimeHurtbox(self: NpcServiceServer, runtime: NpcRuntime): (Vector3, Vector3)
	local model = runtime.slime.model
	local center: Vector3? = nil
	local size = DEFAULT_RUNTIME_HURTBOX_SIZE
	if model ~= nil then
		local ok, boundsCFrameOrError, boundsSize = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and typeof(boundsCFrameOrError) == "CFrame" and typeof(boundsSize) == "Vector3" then
			center = boundsCFrameOrError.Position
			size = sanitizeSizeVector(boundsSize, DEFAULT_RUNTIME_HURTBOX_SIZE)
		end
	end

	if center == nil then
		local rootPart = InstanceUtils.resolveModelRootPart(model)
		if rootPart ~= nil then
			center = rootPart.Position
			size = sanitizeSizeVector(rootPart.Size, DEFAULT_RUNTIME_HURTBOX_SIZE)
		else
			local slimePosition = runtime.slime:getPosition()
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
	return center, paddedSize
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

	local damage = sanitizeNumber(damageRaw, 0, 0, 100000)
	if damage <= 0 then
		return 0
	end

	local querySize = sanitizeSizeVector(querySizeRaw, Vector3.new(0.05, 0.05, 0.05))
	local queryMin, queryMax = computeBoxAabb(queryCFrameRaw, querySize)
	local totalAppliedDamage = 0
	for _, runtime in self.runtimes do
		if runtime.isRemoving or not runtime.isAlive then
			continue
		end

		local hurtboxCenter, hurtboxSize = self:resolveRuntimeHurtbox(runtime)
		local hurtboxMin, hurtboxMax = computeBoxAabb(CFrame.new(hurtboxCenter), hurtboxSize)
		if not aabbIntersects(queryMin, queryMax, hurtboxMin, hurtboxMax) then
			continue
		end

		totalAppliedDamage += self:applyRuntimeDamage(runtime, damage, source, damageContextRaw)
	end

	return totalAppliedDamage
end

function NpcServiceServer.EmitRuntimePreDamageSlimeBlood(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	damage: number,
	source: any?,
	damageContextRaw: any?
)
	if StringUtils.compactToken(damageContextRaw) ~= "melee" then
		return
	end
	if runtime.npcType ~= "Slime" then
		return
	end
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return
	end

	local goreService = self.goreService
	if goreService == nil then
		return
	end

	local now = os.clock()
	if now - runtime.lastPreDamageSlimeBloodAt < DEFAULT_PRE_DAMAGE_SLIME_BLOOD_COOLDOWN then
		return
	end

	local hp = math.max(0, runtime.hp)
	local maxHp = math.max(1, runtime.maxHp)
	local lowHpThreshold = math.max(
		DEFAULT_PRE_DAMAGE_SLIME_BLOOD_MIN_HP,
		math.floor(maxHp * DEFAULT_PRE_DAMAGE_SLIME_BLOOD_LOW_HP_RATIO + 0.5)
	)
	local likelyLethalHit = hp <= math.max(1, damage)
	local isLowHp = hp <= lowHpThreshold
	if not isLowHp and not likelyLethalHit then
		return
	end

	runtime.lastPreDamageSlimeBloodAt = now

	local origin: any = runtime.slime.rootPart
	if origin == nil or origin.Parent == nil then
		local modelRoot = InstanceUtils.resolveModelRootPart(runtime.slime.model)
		if modelRoot ~= nil then
			origin = modelRoot
		else
			local position = runtime.slime:getPosition()
			if position ~= nil then
				origin = position
			end
		end
	end
	if typeof(origin) == "Instance" and origin:IsA("BasePart") then
		origin = origin.Position
	end

	goreService:emitNpcSlimeBlood(
		runtime.id,
		origin,
		DEFAULT_PRE_DAMAGE_SLIME_BLOOD_EMIT_COUNT,
		DEFAULT_PRE_DAMAGE_SLIME_BLOOD_FOLLOW_DURATION,
		DEFAULT_PRE_DAMAGE_SLIME_BLOOD_DROPLET_AMOUNT
	)
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

	local damage = sanitizeNumber(rawDamage, 0, 0, 100000)
	if damage <= 0 then
		return 0
	end

	self:emitRuntimePreDamageSlimeBlood(runtime, damage, source, damageContextRaw)

	local appliedDamage = slime:takeDamage(damage, source)
	if appliedDamage > 0 then
		self:syncRuntimeVitals(runtime)
		self:updateRuntime(runtime, "externalDamage", false)
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

	local runtime = self:resolveRuntimeFromPart(hitPartRaw)
	if runtime == nil then
		return 0
	end

	return self:applyRuntimeDamage(runtime, damageRaw, source, damageContextRaw)
end

function NpcServiceServer.OnEnemyHitPlayer(
	self: NpcServiceServer,
	runtimeIdRaw: any,
	playerRaw: any,
	damageRaw: any
)
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return
	end
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return
	end

	local runtime = self:getRuntime(runtimeIdRaw)
	if runtime == nil then
		return
	end
	if runtime.isRemoving or not runtime.isAlive then
		return
	end

	local hpService = HpServiceServer :: HpServiceServerObject
	local defaultDamage = sanitizeNumber(runtime.slime.damage, 0, 0, 100000)
	local damage = sanitizeNumber(damageRaw, defaultDamage, 0, 100000)
	if damage <= 0 then
		return
	end

	local healthAfterDamage = hpService:damagePlayer(playerRaw, damage)
	if healthAfterDamage == nil then
		return
	end

	runtime.lastEnemyHitAt = os.clock()
	self:updateRuntime(runtime, "enemyHitPlayer", false)
end

function NpcServiceServer.RegisterRuntimeEnemyHitbox(self: NpcServiceServer, runtime: NpcRuntime)
	if not isSlimeRuntime(runtime) then
		return
	end

	local enemyHitbox = self.enemyHitbox
	if enemyHitbox == nil then
		return
	end

	local runtimeId = runtime.id
	local didRegister = enemyHitbox:registerEnemy({
		id = runtimeId,
		owner = runtime,
		model = runtime.slime.model,
		getModel = function(ownerRuntime: NpcRuntime): Model?
			return ownerRuntime.slime.model
		end,
		getCenter = function(ownerRuntime: NpcRuntime): Vector3?
			local center = self:resolveRuntimeHurtbox(ownerRuntime)
			return center
		end,
		getAlive = function(ownerRuntime: NpcRuntime): boolean
			return ownerRuntime.isAlive and not ownerRuntime.isRemoving and ownerRuntime.slime.isAlive
		end,
		getDamage = function(ownerRuntime: NpcRuntime): number
			return sanitizeNumber(ownerRuntime.slime.damage, 0, 0, 100000)
		end,
		getAttackCooldown = function(ownerRuntime: NpcRuntime): number
			return sanitizeNumber(ownerRuntime.slime.combat.attackCooldown, 0.85, 0.05, 30)
		end,
		getHurtboxSize = function(ownerRuntime: NpcRuntime, _model: Model?, _rootPart: BasePart?): Vector3
			local _, hurtboxSize = self:resolveRuntimeHurtbox(ownerRuntime)
			return hurtboxSize
		end,
		getAttackSize = function(ownerRuntime: NpcRuntime, model: Model?, rootPart: BasePart?): Vector3
			local basePart = if rootPart ~= nil then rootPart else InstanceUtils.resolveModelRootPart(model)
			local baseSize = if basePart ~= nil then basePart.Size else DEFAULT_RUNTIME_HURTBOX_SIZE
			local slime = ownerRuntime.slime
			local attackRange = sanitizeNumber(slime.combat.attackRange, 3.5, 0.5, 25)
			local hopReach = sanitizeNumber(slime.hopDistance, 6, 1, 60) * 0.5
			local effectiveReach = math.max(attackRange, hopReach, 4)
			return Vector3.new(
				math.max(4, baseSize.X + 2),
				math.max(3, baseSize.Y + 1),
				math.max(6, baseSize.Z + effectiveReach * 2)
			)
		end,
		canHitPlayer = function(ownerRuntime: NpcRuntime, player: Player): boolean
			local slime = ownerRuntime.slime
			if ownerRuntime.isRemoving or not ownerRuntime.isAlive or not slime.isAlive then
				return false
			end
			if not slime.aggroOnPlayer then
				return false
			end
			if slime.passiveUntilHit and not slime.hasBeenHit then
				return false
			end

			local distance = slime:getDistanceTo(player)
			if distance == nil then
				return false
			end
			local maxContactDistance = math.max(5.5, sanitizeNumber(slime.hopDistance, 6, 1, 60) * 0.5 + 2)
			return distance <= maxContactDistance
		end,
		onHitPlayer = function(ownerRuntime: NpcRuntime, player: Player, damage: number)
			self:onEnemyHitPlayer(ownerRuntime.id, player, damage)
		end,
	})

	if didRegister then
		runtime.enemyHitboxId = runtimeId
	end
end

function NpcServiceServer.UnregisterRuntimeEnemyHitbox(self: NpcServiceServer, runtime: NpcRuntime)
	local enemyHitboxId = runtime.enemyHitboxId
	if enemyHitboxId ~= nil and self.enemyHitbox ~= nil then
		self.enemyHitbox:unregisterEnemy(enemyHitboxId)
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
		self.spawnCFrames = NpcServiceUtils.collectSpawnCFrames(math.max(1, self.slimeSpawnSettings.maxAlive))
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

function NpcServiceServer.ResolveSurfaceSpawnCFrame(
	self: NpcServiceServer,
	candidatePosition: Vector3,
	characterToIgnore: Model?
): CFrame?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeInstances = {}
	if characterToIgnore ~= nil then
		table.insert(excludeInstances, characterToIgnore)
	end
	if self.npcFolder ~= nil then
		table.insert(excludeInstances, self.npcFolder)
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

	local excludeInstances = {}
	if characterToIgnore ~= nil then
		table.insert(excludeInstances, characterToIgnore)
	end
	if self.npcFolder ~= nil then
		table.insert(excludeInstances, self.npcFolder)
	end
	overlapParams.FilterDescendantsInstances = excludeInstances
	overlapParams.MaxParts = DEFAULT_SPAWN_EMPTY_GAP_MAX_PARTS

	local queryCenter =
		spawnCFrame.Position + Vector3.new(0, DEFAULT_SPAWN_EMPTY_GAP_HALF_EXTENTS.Y + DEFAULT_SPAWN_EMPTY_GAP_FLOOR_BUFFER, 0)
	local parts = Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), DEFAULT_SPAWN_EMPTY_GAP_HALF_EXTENTS * 2, overlapParams)
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
			local zOffset = self.random:NextNumber(DEFAULT_PLAYER_RELATIVE_MIN_Z_OFFSET, DEFAULT_PLAYER_RELATIVE_MAX_Z_OFFSET)
			local yOffset = self.random:NextNumber(0, DEFAULT_PLAYER_RELATIVE_Y_OFFSET)
			local spawnPosition = rootPart.Position + Vector3.new(0, yOffset, spawnSign * zOffset)

			local snappedSpawnCFrame = self:resolveSurfaceSpawnCFrame(spawnPosition, character)
			if snappedSpawnCFrame ~= nil and not self:isCorruptionBiomePosition(snappedSpawnCFrame.Position) and self:isSpawnGapClear(snappedSpawnCFrame, character) then
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

		local rootPart = InstanceUtils.resolveModelRootPart(character)
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

	local despawnDistance = sanitizeNumber(settings.despawnDistance, 0, 0, 100000)
	if despawnDistance <= 0 then
		return 0
	end

	local removalIds = {}
	local distanceThreshold = despawnDistance + DEFAULT_DESPAWN_DISTANCE_BUFFER
	for runtimeId, runtime in self.runtimes do
		if runtime.isRemoving or not runtime.isAlive or runtime.slime.isAlive ~= true then
			continue
		end

		local position = runtime.slime:getPosition()
		if position == nil then
			table.insert(removalIds, runtimeId)
			continue
		end

		local nearestDistance = self:getNearestPlayerDistance(position)
		if nearestDistance == nil or nearestDistance > distanceThreshold then
			table.insert(removalIds, runtimeId)
		end
	end

	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "tooFarFromPlayers"
	for _, runtimeId in removalIds do
		self:removeRuntime(runtimeId, reason)
	end

	return #removalIds
end

function NpcServiceServer.GetNextSpawnCFrame(self: NpcServiceServer): CFrame?
	return self:getNextPlayerRelativeSpawnCFrame()
end

function NpcServiceServer.CreateDefaultSpawnConfigAt(self: NpcServiceServer, spawnCFrame: CFrame): SlimeSpawnConfig?
	if self:isCorruptionBiomePosition(spawnCFrame.Position) then
		return nil
	end

	local configs = NpcServiceUtils.createDefaultSlimeSpawnConfigs({ spawnCFrame })
	if #configs <= 0 then
		return nil
	end
	return configs[1]
end

function NpcServiceServer.GetDebugSpawnCFrameForPlayer(
	self: NpcServiceServer,
	playerRaw: any,
	indexRaw: any
): CFrame?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return self:getNextSpawnCFrame()
	end

	local character = playerRaw.Character
	if character == nil then
		return self:getNextSpawnCFrame()
	end

	local rootPart = InstanceUtils.resolveModelRootPart(character)
	if rootPart == nil then
		return self:getNextSpawnCFrame()
	end

	local index = math.max(1, math.floor(sanitizeNumber(indexRaw, 1, 1, 10 ^ 6)))
	local laneIndex = math.floor((index - 1) / 2)
	local directionSign = if index % 2 == 1 then 1 else -1
	local zOffset = DEFAULT_PLAYER_RELATIVE_MIN_Z_OFFSET + laneIndex * 8
	local yOffset = DEFAULT_PLAYER_RELATIVE_Y_OFFSET + math.min(laneIndex, 4)
	local candidatePosition = rootPart.Position + Vector3.new(0, yOffset, directionSign * zOffset)
	local snappedSpawnCFrame = self:resolveSurfaceSpawnCFrame(candidatePosition, character)

	if snappedSpawnCFrame ~= nil
		and not self:isCorruptionBiomePosition(snappedSpawnCFrame.Position)
		and self:isSpawnGapClear(snappedSpawnCFrame, character)
	then
		return snappedSpawnCFrame
	end

	return self:getNextSpawnCFrame()
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

	local spawnCFrame = self:getDebugSpawnCFrameForPlayer(playerRaw, indexRaw)
	if spawnCFrame == nil then
		return nil, "missing_spawn_cframe"
	end

	local spawnConfig = self:createDefaultSpawnConfigAt(spawnCFrame)
	if spawnConfig == nil then
		return nil, "invalid_spawn_configuration"
	end

	spawnConfig.slimeType = "GreenSlime"
	spawnConfig.displayName = "Green Slime"
	spawnConfig.modelName = "GreenSlime"
	spawnConfig.modelHierarchy = "Enemies.GreenSlime"

	local runtime = self:spawnSlime(spawnConfig)
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

	self:despawnFarRuntimes("spawnPrecheck")

	local activeCount = self:getActiveSlimeCount()
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

	local spawnCFrame = self:getNextSpawnCFrame()
	if spawnCFrame == nil then
		return nil
	end
	local spawnConfig = self:createDefaultSpawnConfigAt(spawnCFrame)
	if spawnConfig == nil then
		return nil
	end

	local runtime = self:spawnSlime(spawnConfig)
	if runtime ~= nil then
		local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "autoSpawn"
		self:transitionRuntimeState(runtime, "Spawning", reason, true)
	end
	return runtime
end

function NpcServiceServer.CreateStatePayload(self: NpcServiceServer): { NpcSnapshot }
	local snapshots = {}
	for _, runtime in self.runtimes do
		table.insert(snapshots, self:createSnapshot(runtime))
	end
	return snapshots
end

function NpcServiceServer.Broadcast(self: NpcServiceServer, methodName: string, ...: any)
	local recipients = {}
	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			recipients[#recipients + 1] = player
		end
	end
	fireForPlayers(self.networker, recipients, methodName, ...)
end

function NpcServiceServer.PushState(self: NpcServiceServer, player: Player)
	self.networker:fire(player, NpcServiceUtils.CLIENT_METHOD_APPLY_STATE, self:createStatePayload())
end

function NpcServiceServer.RequestSync(self: NpcServiceServer, player: Player)
	self:pushState(player)
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

	if forceTransition ~= true and not NpcServiceUtils.canTransition(runtime.stateGraph, currentState, nextState) then
		return false
	end

	runtime.state = nextState
	runtime.lastReason = reason
	runtime.updatedAt = os.clock()

	local payload = self:createSnapshot(runtime) :: any
	payload.previousState = currentState
	self:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED, payload)
	return true
end

function NpcServiceServer.RemoveRuntime(self: NpcServiceServer, runtimeIdRaw: any, reasonRaw: any)
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return
	end

	local runtime = self:getRuntime(runtimeIdRaw)
	if runtime == nil then
		return
	end

	runtime.isRemoving = true
	self.runtimes[runtimeIdRaw] = nil
	self:unregisterRuntimeEnemyHitbox(runtime)
	if self.goreService ~= nil then
		self.goreService:unregisterNpcEntity(runtime.id)
	end

	local model = runtime.slime.model
	if model and self.runtimesByModel[model] == runtime then
		self.runtimesByModel[model] = nil
	end

	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "removed"
	self:transitionRuntimeState(runtime, "Dead", reason, true)

	if not (runtime.slime :: any)._isDestroyed then
		runtime.slime:destroy()
	end

	runtime.animationEventJanitor:Destroy()
	runtime.janitor:Destroy()
	self:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_REMOVED, runtimeIdRaw)
end

function NpcServiceServer.SyncRuntimeGoreRegistration(self: NpcServiceServer, runtime: NpcRuntime)
	local goreService = self.goreService
	if goreService == nil then
		return
	end

	local model = runtime.slime.model
	if model == nil or model.Parent == nil then
		goreService:unregisterNpcEntity(runtime.id)
		return
	end

	local goreConfig = nil
	if runtime.npcType == "Slime" then
		goreConfig = {
			damageBloodAmount = DEFAULT_SLIME_DAMAGE_BLOOD_AMOUNT,
			deathBloodAmount = DEFAULT_SLIME_DEATH_BLOOD_AMOUNT,
			bloodSettings = {
				DefaultSize = DEFAULT_SLIME_BLOOD_POOL_SIZE,
				SizeY = DEFAULT_SLIME_BLOOD_POOL_SIZE_Y,
				StartingSize = DEFAULT_SLIME_BLOOD_POOL_STARTING_SIZE,
				MaximumSize = DEFAULT_SLIME_BLOOD_POOL_MAX_SIZE,
				ExpanseDivider = DEFAULT_SLIME_BLOOD_POOL_EXPANSE_DIVIDER,
			},
		}
	end

	goreService:registerNpcEntity(runtime.id, model, goreConfig)
end

function NpcServiceServer.ResolveRuntimeDeathOrigin(self: NpcServiceServer, runtime: NpcRuntime): Vector3?
	local deathPosition = runtime.slime:getPosition()
	if deathPosition ~= nil then
		return deathPosition
	end

	local rootPart = InstanceUtils.resolveModelRootPart(runtime.slime.model)
	if rootPart ~= nil then
		return rootPart.Position
	end

	return nil
end

function NpcServiceServer.EmitRuntimeDeathGore(self: NpcServiceServer, runtime: NpcRuntime, originRaw: any?): boolean
	if runtime.deathGoreEmitted then
		return true
	end

	local goreService = self.goreService
	if goreService == nil then
		return false
	end

	local origin = if typeof(originRaw) == "Vector3" then originRaw else self:resolveRuntimeDeathOrigin(runtime)
	if origin == nil then
		return false
	end

	local didEmit = goreService:onNpcDied(runtime.id, origin)
	if didEmit then
		runtime.deathGoreEmitted = true
		return true
	end

	self:syncRuntimeGoreRegistration(runtime)
	didEmit = goreService:onNpcDied(runtime.id, origin)
	if didEmit then
		runtime.deathGoreEmitted = true
	end

	return didEmit
end

function NpcServiceServer.EmitRuntimeSlimeBlood(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	emitCountRaw: any?,
	dropletAmountRaw: any?
): boolean
	if runtime.npcType ~= "Slime" then
		return false
	end

	local slimeBloodTemplate = resolveSlimeBloodEffectTemplate()
	local bloodEffect =
		(if slimeBloodTemplate ~= nil then slimeBloodTemplate:Clone() else createFallbackSlimeBloodEffect()) :: BasePart
	if slimeBloodTemplate == nil then
		if self.missingSlimeBloodTemplateWarningShown ~= true then
			self.missingSlimeBloodTemplateWarningShown = true
		end
	end

	local sourcePart = runtime.slime.rootPart
	if sourcePart == nil or sourcePart.Parent == nil then
		sourcePart = InstanceUtils.resolveModelRootPart(runtime.slime.model)
	end
	if sourcePart == nil then
		bloodEffect:Destroy()
		return false
	end

	local particlesPerEmitter =
		math.floor(sanitizeNumber(emitCountRaw, DEFAULT_SLIME_BLOOD_PARTICLES_PER_EMITTER, 1, 200) + 0.5)

	local bloodRuntimeModel = Instance.new("Model")
	bloodRuntimeModel.Name = "SlimeBloodRuntime"
	bloodEffect.Name = "SlimeBlood"
	bloodEffect.CFrame = sourcePart.CFrame
	bloodEffect.Anchored = true
	bloodEffect.CanCollide = false
	bloodEffect.CanTouch = false
	bloodEffect.CanQuery = false
	bloodEffect.Parent = bloodRuntimeModel
	bloodRuntimeModel.PrimaryPart = bloodEffect
	bloodRuntimeModel.Parent = getOrCreateEffectsJunkFolder()

	local emitted = false
	local maxLifetime = 0
	local effectEmitters = {} :: { ParticleEmitter }
	for _, descendant in bloodEffect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local lifetime = descendant.Lifetime
			local maxEmitterLifetime = math.max(0, lifetime.Min, lifetime.Max)
			descendant.Enabled = true
			descendant:Emit(particlesPerEmitter)
			maxLifetime = math.max(maxLifetime, maxEmitterLifetime)
			emitted = true
			table.insert(effectEmitters, descendant)
		end
	end

	if not emitted then
		bloodRuntimeModel:Destroy()
		return false
	end

	local temporarySlimeBloodGoreRuntimeId: string? = nil
	local goreService = self.goreService
	local dropletAmount = math.floor(sanitizeNumber(dropletAmountRaw, 0, 0, 200) + 0.5)
	if goreService ~= nil and dropletAmount > 0 then
		local uniqueSuffix = math.floor(os.clock() * 1000) + self.random:NextInteger(1, 1_000_000)
		temporarySlimeBloodGoreRuntimeId = ("%s_slimeblood_%d"):format(runtime.id, uniqueSuffix)

		local didRegister = goreService:registerNpcEntity(temporarySlimeBloodGoreRuntimeId, bloodRuntimeModel, {
			damageBloodAmount = DEFAULT_SLIME_DAMAGE_BLOOD_AMOUNT,
			deathBloodAmount = DEFAULT_SLIME_DEATH_BLOOD_AMOUNT,
			deathGibCount = 0,
			emitDeathGibs = false,
			bloodSettings = {
				DefaultSize = DEFAULT_SLIME_BLOOD_POOL_SIZE,
				SizeY = DEFAULT_SLIME_BLOOD_POOL_SIZE_Y,
				StartingSize = DEFAULT_SLIME_BLOOD_POOL_STARTING_SIZE,
				MaximumSize = DEFAULT_SLIME_BLOOD_POOL_MAX_SIZE,
				ExpanseDivider = DEFAULT_SLIME_BLOOD_POOL_EXPANSE_DIVIDER,
			},
		})
		if didRegister then
			goreService:onNpcDamaged(temporarySlimeBloodGoreRuntimeId, bloodEffect, dropletAmount)
		else
			temporarySlimeBloodGoreRuntimeId = nil
		end
	end

	task.delay(SLIME_BLOOD_EMIT_WINDOW_SECONDS, function()
		for _, emitter in effectEmitters do
			if emitter.Parent ~= nil then
				emitter.Enabled = false
			end
		end
	end)

	local cleanupDelay =
		math.max(
			MIN_SLIME_BLOOD_CLEANUP_SECONDS,
			SLIME_BLOOD_EMIT_WINDOW_SECONDS + maxLifetime + DEFAULT_SLIME_BLOOD_CLEANUP_BUFFER_SECONDS
		)
	task.delay(cleanupDelay, function()
		local activeGoreService = self.goreService
		if temporarySlimeBloodGoreRuntimeId ~= nil and activeGoreService ~= nil then
			activeGoreService:unregisterNpcEntity(temporarySlimeBloodGoreRuntimeId)
		end
		if bloodRuntimeModel.Parent ~= nil then
			bloodRuntimeModel:Destroy()
		end
	end)

	return true
end

function NpcServiceServer.ResolveRuntimeState(self: NpcServiceServer, runtime: NpcRuntime): NpcRuntimeState
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
	local hasTarget = currentTarget ~= nil and npc:isTargetValid(currentTarget)
	if hasTarget then
		if npc:canAttackTarget(currentTarget) then
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
	local world = self:resolveWorld()
	if world == nil then
		runtime.biomeName = "Unknown"
		runtime.biomeReady = false
		return
	end

	local position = runtime.slime:getPosition()
	if position == nil then
		runtime.biomeName = "Unknown"
		runtime.biomeReady = false
		return
	end

	local biomeName, biomeReady = NpcServiceUtils.resolveBiomeNameFromWorld(world, position)
	runtime.biomeName = biomeName
	runtime.biomeReady = biomeReady
end

function NpcServiceServer.TryPlaySoundAction(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	action: AnimationEventAction
): (boolean, any?, { [string]: any }?)
	local slimeModel = runtime.slime.model
	local soundSource = if action.sound ~= nil then action.sound else action.source
	if soundSource == nil and action.soundName ~= nil then
		soundSource = self:resolveRuntimeSoundSource(runtime, action.soundName)
	end

	local soundAssetId = NpcServiceUtils.resolveSoundSource(soundSource)
	if soundAssetId == nil then
		return false, nil, nil
	end

	local soundService = self.soundService
	if soundService == nil or (soundService :: any).networker == nil then
		return false, nil, nil
	end

	local parent = runtime.slime.rootPart
	if parent == nil then
		parent = slimeModel
	end
	if parent == nil then
		return false, nil, nil
	end

	local options: { [string]: any } = {
		category = "SFX",
		looped = action.looped,
		volume = action.volume,
		playbackSpeed = action.playbackSpeed,
		autoDestroy = action.autoDestroy,
		rollOffMaxDistance = action.rollOffMaxDistance,
		emitterSize = action.emitterSize,
		parent = parent,
	}

	soundService:playSfxForAll(soundAssetId, options)
	return true, nil, nil
end

function NpcServiceServer.TryPlayAnimationAction(self: NpcServiceServer, runtime: NpcRuntime, action: AnimationEventAction): boolean
	local slimeModel = runtime.slime.model
	local animationSource = if action.animation ~= nil then action.animation else action.source
	if animationSource == nil and action.animationName ~= nil then
		animationSource = NpcServiceUtils.findDescendantByNameOfClass(slimeModel, action.animationName, "Animation")
	end

	local animationTemplate, animationAssetId = NpcServiceUtils.resolveAnimationSource(animationSource)
	if animationTemplate == nil and animationAssetId == nil then
		return false
	end

	local animator: Animator? = nil
	local humanoid = runtime.slime.humanoid
	if humanoid ~= nil then
		animator = resolveAnimator(humanoid)
	end
	if animator == nil and slimeModel ~= nil then
		animator = resolveAnimatorFromModel(slimeModel)
	end
	if animator == nil then
		return false
	end

	if action.stopOtherTracks == true then
		for _, playingTrack in (animator :: Animator):GetPlayingAnimationTracks() do
			playingTrack:Stop(math.min(0.1, if action.fadeTime then action.fadeTime else 0.08))
		end
	end

	local animationObject = animationTemplate
	local shouldDestroyAnimationObject = false
	if animationObject == nil and animationAssetId ~= nil then
		local generated = Instance.new("Animation")
		generated.Name = "NpcEventAnimation"
		generated.AnimationId = animationAssetId
		animationObject = generated
		shouldDestroyAnimationObject = true
	end

	if animationObject == nil then
		return false
	end

	local ok, trackOrError = pcall(function()
		return (animator :: Animator):LoadAnimation(animationObject :: Animation)
	end)
	if shouldDestroyAnimationObject then
		local animationObjectTyped = animationObject :: Animation
		animationObjectTyped:Destroy()
	end
	if not ok then
		return false
	end

	local track = trackOrError :: AnimationTrack
	if action.looped ~= nil then
		track.Looped = action.looped
	end
	if action.priority ~= nil then
		track.Priority = action.priority
	end

	local fadeTime = if action.fadeTime ~= nil then action.fadeTime else 0.08
	local weight = if action.weight ~= nil then action.weight else 1
	local speed = if action.playbackSpeed ~= nil then action.playbackSpeed else 1
	track:Play(fadeTime, weight, speed)

	if action.autoDestroy == true and not track.Looped then
		local stoppedConnection: RBXScriptConnection?
		stoppedConnection = track.Stopped:Connect(function()
			if stoppedConnection then
				stoppedConnection:Disconnect()
				stoppedConnection = nil
			end
			pcall(function()
				track:Destroy()
			end)
		end)
		runtime.animationEventJanitor:GiveChore(stoppedConnection)
	end

	return true
end

function NpcServiceServer.OnRuntimeAnimationEvent(
	self: NpcServiceServer,
	runtime: NpcRuntime,
	trackName: string,
	eventType: string,
	eventName: string,
	parameter: any,
	actions: { AnimationEventAction }
)
	if runtime.isRemoving then
		return
	end

	local clientEffects = {}
	for _, action in actions do
		if action.kind == "sound" then
			local played, clientSource, clientOptions = self:tryPlaySoundAction(runtime, action)
			if played and action.playOnClient == true and clientSource ~= nil then
				table.insert(clientEffects, {
					kind = "sound",
					source = clientSource,
					options = clientOptions,
				})
			end
		elseif action.kind == "animation" then
			local played = self:tryPlayAnimationAction(runtime, action)
			if played and action.playOnClient == true then
				table.insert(clientEffects, {
					kind = "animation",
					source = action.source,
				})
			end
		end
	end

	self:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_ANIMATION_EVENT, {
		id = runtime.id,
		npcType = runtime.npcType,
		trackName = trackName,
		eventType = eventType,
		eventName = eventName,
		parameter = parameter,
		state = runtime.state,
		biomeName = runtime.biomeName,
		biomeReady = runtime.biomeReady,
		updatedAt = os.clock(),
		clientEffects = clientEffects,
	})
end

function NpcServiceServer.EnsureRuntimeAnimationEventBindings(self: NpcServiceServer, runtime: NpcRuntime)
	if runtime.animationEventsBound then
		return
	end
	if not isSlimeRuntime(runtime) then
		return
	end

	local slimeAny = runtime.slime :: any
	if slimeAny._slimeAnimationsLoaded ~= true then
		return
	end

	local slimeTracks = slimeAny._slimeAnimations
	if typeof(slimeTracks) ~= "table" then
		return
	end

	runtime.animationEventJanitor:Clean()
	local boundConnections = 0

	for trackName, binding in runtime.animationEvents do
		local track = asAnimationTrack((slimeTracks :: any)[trackName])
		if track == nil then
			continue
		end

		for markerName, actions in binding.markers do
			if #actions <= 0 then
				continue
			end

			local ok, markerSignalOrError = pcall(function()
				return track:GetMarkerReachedSignal(markerName)
			end)
			if ok and markerSignalOrError ~= nil then
				runtime.animationEventJanitor:GiveChore((markerSignalOrError :: any):Connect(function(parameter: string)
					self:onRuntimeAnimationEvent(runtime, trackName, "Marker", markerName, parameter, actions)
				end))
				boundConnections += 1
			else
			end
		end

		if next(binding.keyframes) ~= nil then
			runtime.animationEventJanitor:GiveChore(track.KeyframeReached:Connect(function(keyframeName: string)
				local actions = binding.keyframes[keyframeName]
				if actions ~= nil and #actions > 0 then
					self:onRuntimeAnimationEvent(runtime, trackName, "Keyframe", keyframeName, nil, actions)
				end
			end))
			boundConnections += 1
		end
	end

	runtime.animationEventsBound = boundConnections > 0
end

function NpcServiceServer.UpdateRuntime(self: NpcServiceServer, runtime: NpcRuntime, reason: string, refreshBiome: boolean)
	if runtime.isRemoving then
		return
	end

	local previousState = runtime.state
	local previousHp = runtime.hp
	local previousMaxHp = runtime.maxHp
	local previousAlive = runtime.isAlive

	self:syncRuntimeVitals(runtime)
	if self.enemyHitbox ~= nil then
		self.enemyHitbox:setEnemyAlive(runtime.id, runtime.isAlive)
	end

	if refreshBiome then
		self:refreshRuntimeBiome(runtime)
	end

	self:ensureRuntimeAnimationEventBindings(runtime)

	local desiredState = self:resolveRuntimeState(runtime)
	local transitioned = self:transitionRuntimeState(runtime, desiredState, reason, false)
	if transitioned
		and runtime.state == previousState
		and (runtime.hp ~= previousHp or runtime.maxHp ~= previousMaxHp or runtime.isAlive ~= previousAlive) then
		local payload = self:createSnapshot(runtime) :: any
		payload.previousState = previousState
		self:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_STATE_CHANGED, payload)
	end
end

function NpcServiceServer.TrackRuntime(self: NpcServiceServer, runtime: NpcRuntime)
	self.runtimes[runtime.id] = runtime

	local model = runtime.slime.model
	if model ~= nil then
		self.runtimesByModel[model] = runtime
		applyRuntimeModelAttributes(runtime, model)
	end
	self:syncRuntimeGoreRegistration(runtime)

	runtime.janitor:GiveChore(runtime.slime.signals.spawned:Connect(function(modelInstance: Model)
		self.runtimesByModel[modelInstance] = runtime
		applyRuntimeModelAttributes(runtime, modelInstance)
		runtime.animationEventsBound = false
		runtime.deathGoreEmitted = false
		runtime.lastPreDamageSlimeBloodAt = -math.huge
		self:syncRuntimeGoreRegistration(runtime)
		self:applyRuntimeNpcCollisionGroup(runtime)
		if self.enemyHitbox ~= nil then
			self.enemyHitbox:setEnemyModel(runtime.id, modelInstance)
			self.enemyHitbox:setEnemyAlive(runtime.id, runtime.slime.isAlive)
		end
		self:syncRuntimeVitals(runtime)
		self:updateRuntime(runtime, "spawned", true)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.stateChanged:Connect(function()
		self:updateRuntime(runtime, "npcStateChanged", false)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.targetChanged:Connect(function()
		self:updateRuntime(runtime, "targetChanged", false)
	end))

	runtime.janitor:GiveChore(runtime.npc.signals.attacked:Connect(function()
		runtime.lastEnemyHitAt = os.clock()
		self:updateRuntime(runtime, "npcAttacked", false)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.damaged:Connect(function(damageAmount: number, _source: any?, hpRaw: number?)
		if self.goreService ~= nil then
			local didEmit = self.goreService:onNpcDamaged(runtime.id, runtime.slime.rootPart, damageAmount)
			if not didEmit then
				self:syncRuntimeGoreRegistration(runtime)
				self.goreService:onNpcDamaged(runtime.id, runtime.slime.rootPart, damageAmount)
			end
		end

		if not runtime.deathGoreEmitted and typeof(hpRaw) == "number" and hpRaw <= 0 then
			local deathOrigin = self:resolveRuntimeDeathOrigin(runtime)
			self:emitRuntimeDeathGore(runtime, deathOrigin)
		end

		self:syncRuntimeVitals(runtime)
		self:updateRuntime(runtime, "damaged", false)
	end))

	runtime.janitor:GiveChore(runtime.slime.signals.died:Connect(function()
		self:emitRuntimeDeathGore(runtime, nil)
		runtime.isAlive = false
		runtime.hp = 0
		self:playRuntimeNamedSound(runtime, "Death")
		if self.enemyHitbox ~= nil then
			self.enemyHitbox:setEnemyAlive(runtime.id, false)
		end
		local lootService = self.lootService
		if lootService ~= nil then
			local deathPosition = runtime.slime:getPosition()
			if deathPosition == nil then
				local rootPart = InstanceUtils.resolveModelRootPart(runtime.slime.model)
				if rootPart ~= nil then
					deathPosition = rootPart.Position
				end
			end
			if deathPosition ~= nil then
				lootService:spawnLootRuntime(SLIME_GEL_DROP_ITEM_ID, SLIME_GEL_DROP_AMOUNT, deathPosition, {
					sourceType = runtime.displayName,
				})
				lootService:spawnDropsFromSource(runtime.displayName, deathPosition, {
					sourceType = runtime.displayName,
				})
			end
		end
		self:transitionRuntimeState(runtime, "Dead", "died", true)
		task.delay(2, function()
			local activeRuntime = self:getRuntime(runtime.id)
			if activeRuntime == nil then
				return
			end
			if activeRuntime.slime.isAlive then
				return
			end
			self:removeRuntime(runtime.id, "deathCleanup")
		end)
	end))

	local runtimeModel = runtime.slime.model
	if runtimeModel then
		runtime.janitor:GiveChore(runtimeModel.Destroying:Connect(function()
			if runtime.isRemoving then
				return
			end
			self:removeRuntime(runtime.id, "modelDestroyed")
		end))
	end

	self:applyRuntimeNpcCollisionGroup(runtime)
	self:registerRuntimeEnemyHitbox(runtime)
end

function NpcServiceServer.SpawnSlime(self: NpcServiceServer, spawnConfig: SlimeSpawnConfig): NpcRuntime?
	local modelName = if spawnConfig.modelHierarchy ~= nil and spawnConfig.modelHierarchy ~= ""
		then spawnConfig.modelHierarchy
		else spawnConfig.modelName

	local slime = Slime.new({
		archetype = spawnConfig.slimeType,
		displayName = spawnConfig.displayName,
		modelName = modelName,
		slimeType = spawnConfig.slimeType,
		hp = DEFAULT_SLIME_HP,
		maxHp = DEFAULT_SLIME_HP,
		aggroOnPlayer = spawnConfig.aggroOnPlayer,
		passiveUntilHit = spawnConfig.passiveUntilHit,
		lockTo2DPlane = true,
		planeX = spawnConfig.planeX,
		restDuration = spawnConfig.restDuration,
		hopDuration = spawnConfig.hopDuration,
		hopDistance = spawnConfig.hopDistance,
		movement = {
			canWander = false,
			thinkInterval = 0.1,
			autoRotate = false,
		},
		combat = {
			attackRange = 0,
			attackCooldown = 1.1,
		},
		lifecycle = {
			spawnParent = self.npcFolder,
			autoDestroyModelOnDeath = true,
			autoStart = false,
		},
	})

	local model = slime:start(spawnConfig.spawnCFrame)
	if model == nil then
		slime:destroy()
		return nil
	end

	local runtimeJanitor = Janitor.new()
	local animationEventJanitor = Janitor.new()
	runtimeJanitor:GiveChore(animationEventJanitor)

	local defaultAnimationEvents = NpcServiceUtils.createDefaultSlimeAnimationEvents()
	local runtime: NpcRuntime = {
		id = slime.uniqueId,
		npcType = "Slime",
		displayName = spawnConfig.displayName,
		npc = slime,
		slime = slime,
		hp = slime.hp,
		maxHp = slime.maxHp,
		isAlive = slime.isAlive,
		state = "Dormant",
		lastReason = "spawn",
		biomeName = "Unknown",
		biomeReady = false,
		animationEvents = NpcServiceUtils.sanitizeAnimationEventsByTrack(spawnConfig.animationEvents, defaultAnimationEvents),
		stateGraph = NpcServiceUtils.createDefaultStateMachineGraph(),
		updatedAt = os.clock(),
		janitor = runtimeJanitor,
		animationEventJanitor = animationEventJanitor,
		animationEventsBound = false,
		isRemoving = false,
		deathGoreEmitted = false,
		enemyHitboxId = nil,
		lastEnemyHitAt = -math.huge,
		lastPreDamageSlimeBloodAt = -math.huge,
	}

	self:trackRuntime(runtime)
	self:transitionRuntimeState(runtime, "Spawning", "spawn", true)
	self:updateRuntime(runtime, "spawn", true)
	self:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_ADDED, self:createSnapshot(runtime))
	return runtime
end

function NpcServiceServer.SpawnInitialSlimes(self: NpcServiceServer)
	local settings = self.slimeSpawnSettings
	if not settings.enabled then
		return
	end

	local maxInitial = math.min(settings.initialSpawnCount, settings.maxAlive)
	for _ = 1, maxInitial do
		local spawnCFrame = self:getNextSpawnCFrame()
		if spawnCFrame == nil then
			continue
		end
		local spawnConfig = self:createDefaultSpawnConfigAt(spawnCFrame)
		if spawnConfig ~= nil then
			self:spawnSlime(spawnConfig)
		end
	end
end

function NpcServiceServer.OnHeartbeat(self: NpcServiceServer, dt: number)
	local settings = self.slimeSpawnSettings
	self.despawnRefreshAccumulator += dt
	if self.despawnRefreshAccumulator >= DEFAULT_DESPAWN_CHECK_INTERVAL then
		self.despawnRefreshAccumulator = 0
		self:despawnFarRuntimes("heartbeatDistance")
	end

	if settings.enabled then
		self.spawnAccumulator += dt
		while self.spawnAccumulator >= settings.spawnRate do
			self.spawnAccumulator -= settings.spawnRate
			self:tryAutoSpawnSlime("spawnRateTick")
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
		self:resolveWorld()
	end

	for _, runtime in self.runtimes do
		self:updateRuntime(runtime, "heartbeat", shouldRefreshBiome)
	end
end

function NpcServiceServer.Init(self: NpcServiceServer)
	self.networker = Networker.server.new("NpcService", self, {
		self.RequestSync,
	})
	self.runtimes = {}
	self.runtimesByModel = {}
	self.world = nil
	self.soundService = AudioServiceServer :: AudioServiceServerObject
	self.lootService = LootServiceServer :: LootServiceServerObject
	self.goreService = GoreServiceServer :: GoreServiceServerObject
	self.collisionGroupsReady = false
	self.playerCharacterAddedConnections = {}
	self:ensureCollisionGroups()
	self.enemyHitbox = EnemyHitbox.new({
		cellSize = 8,
		playerCellSize = 8,
	})
	self.npcFolder = self:ensureNpcFolder()
	local rawNpcSettings = if typeof(Configs) == "table" then (Configs :: any).npcSettings else nil
	local rawSlimeSettings = if typeof(rawNpcSettings) == "table" then (rawNpcSettings :: any).slime else nil
	self.slimeSpawnSettings = NpcServiceUtils.sanitizeSlimeSpawnSettings(rawSlimeSettings, nil)
	self.spawnCFrames = NpcServiceUtils.collectSpawnCFrames(math.max(1, self.slimeSpawnSettings.maxAlive))
	self.nextSpawnIndex = 1
	self.spawnAccumulator = 0
	self.despawnRefreshAccumulator = 0
	self.random = Random.new()
	self.missingSlimeBloodTemplateWarningShown = false
	self.stateRefreshAccumulator = 0
	self.biomeRefreshAccumulator = 0

	for _, player in Players:GetPlayers() do
		self:bindPlayerCollisionGroup(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:bindPlayerCollisionGroup(player)
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:pushState(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:unbindPlayerCollisionGroup(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:onHeartbeat(dt)
	end)

	self:spawnInitialSlimes()
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
		connection:Disconnect()
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
		self:removeRuntime(runtimeId, "serviceDestroyed")
	end

	if self.enemyHitbox ~= nil then
		self.enemyHitbox:destroy()
		self.enemyHitbox = nil
	end

	if self.networker then
		self.networker:destroy()
	end
	self.soundService = nil
	self.lootService = nil
	self.goreService = nil
end

NpcServiceServer.ensureNpcFolder = NpcServiceServer.EnsureNpcFolder
NpcServiceServer.ensureCollisionGroups = NpcServiceServer.EnsureCollisionGroups
NpcServiceServer.applyPlayerCollisionGroup = NpcServiceServer.ApplyPlayerCollisionGroup
NpcServiceServer.bindPlayerCollisionGroup = NpcServiceServer.BindPlayerCollisionGroup
NpcServiceServer.unbindPlayerCollisionGroup = NpcServiceServer.UnbindPlayerCollisionGroup
NpcServiceServer.applyRuntimeNpcCollisionGroup = NpcServiceServer.ApplyRuntimeNpcCollisionGroup
NpcServiceServer.resolveRuntimeSoundSource = NpcServiceServer.ResolveRuntimeSoundSource
NpcServiceServer.playRuntimeNamedSound = NpcServiceServer.PlayRuntimeNamedSound
NpcServiceServer.resolveWorld = NpcServiceServer.ResolveWorld
NpcServiceServer.isCorruptionBiomePosition = NpcServiceServer.IsCorruptionBiomePosition
NpcServiceServer.createSnapshot = NpcServiceServer.CreateSnapshot
NpcServiceServer.syncRuntimeVitals = NpcServiceServer.SyncRuntimeVitals
NpcServiceServer.getRuntime = NpcServiceServer.GetRuntime
NpcServiceServer.resolveRuntimeFromModel = NpcServiceServer.ResolveRuntimeFromModel
NpcServiceServer.resolveRuntimeFromPart = NpcServiceServer.ResolveRuntimeFromPart
NpcServiceServer.resolveRuntimeHurtbox = NpcServiceServer.ResolveRuntimeHurtbox
NpcServiceServer.damageNpcsInBox = NpcServiceServer.DamageNpcsInBox
NpcServiceServer.emitRuntimePreDamageSlimeBlood = NpcServiceServer.EmitRuntimePreDamageSlimeBlood
NpcServiceServer.applyRuntimeDamage = NpcServiceServer.ApplyRuntimeDamage
NpcServiceServer.damageNpcFromHitPart = NpcServiceServer.DamageNpcFromHitPart
NpcServiceServer.onEnemyHitPlayer = NpcServiceServer.OnEnemyHitPlayer
NpcServiceServer.registerRuntimeEnemyHitbox = NpcServiceServer.RegisterRuntimeEnemyHitbox
NpcServiceServer.unregisterRuntimeEnemyHitbox = NpcServiceServer.UnregisterRuntimeEnemyHitbox
NpcServiceServer.getActiveSlimeCount = NpcServiceServer.GetActiveSlimeCount
NpcServiceServer.getNextFallbackSpawnCFrame = NpcServiceServer.GetNextFallbackSpawnCFrame
NpcServiceServer.resolveSurfaceSpawnCFrame = NpcServiceServer.ResolveSurfaceSpawnCFrame
NpcServiceServer.isSpawnGapClear = NpcServiceServer.IsSpawnGapClear
NpcServiceServer.getNextPlayerRelativeSpawnCFrame = NpcServiceServer.GetNextPlayerRelativeSpawnCFrame
NpcServiceServer.getNearestPlayerDistance = NpcServiceServer.GetNearestPlayerDistance
NpcServiceServer.despawnFarRuntimes = NpcServiceServer.DespawnFarRuntimes
NpcServiceServer.getNextSpawnCFrame = NpcServiceServer.GetNextSpawnCFrame
NpcServiceServer.createDefaultSpawnConfigAt = NpcServiceServer.CreateDefaultSpawnConfigAt
NpcServiceServer.getDebugSpawnCFrameForPlayer = NpcServiceServer.GetDebugSpawnCFrameForPlayer
NpcServiceServer.spawnDebugNpcById = NpcServiceServer.SpawnDebugNpcById
NpcServiceServer.tryAutoSpawnSlime = NpcServiceServer.TryAutoSpawnSlime
NpcServiceServer.createStatePayload = NpcServiceServer.CreateStatePayload
NpcServiceServer.broadcast = NpcServiceServer.Broadcast
NpcServiceServer.pushState = NpcServiceServer.PushState
NpcServiceServer.requestSync = NpcServiceServer.RequestSync
NpcServiceServer.transitionRuntimeState = NpcServiceServer.TransitionRuntimeState
NpcServiceServer.removeRuntime = NpcServiceServer.RemoveRuntime
NpcServiceServer.syncRuntimeGoreRegistration = NpcServiceServer.SyncRuntimeGoreRegistration
NpcServiceServer.resolveRuntimeDeathOrigin = NpcServiceServer.ResolveRuntimeDeathOrigin
NpcServiceServer.emitRuntimeDeathGore = NpcServiceServer.EmitRuntimeDeathGore
NpcServiceServer.emitRuntimeSlimeBlood = NpcServiceServer.EmitRuntimeSlimeBlood
NpcServiceServer.resolveRuntimeState = NpcServiceServer.ResolveRuntimeState
NpcServiceServer.refreshRuntimeBiome = NpcServiceServer.RefreshRuntimeBiome
NpcServiceServer.tryPlaySoundAction = NpcServiceServer.TryPlaySoundAction
NpcServiceServer.tryPlayAnimationAction = NpcServiceServer.TryPlayAnimationAction
NpcServiceServer.onRuntimeAnimationEvent = NpcServiceServer.OnRuntimeAnimationEvent
NpcServiceServer.ensureRuntimeAnimationEventBindings = NpcServiceServer.EnsureRuntimeAnimationEventBindings
NpcServiceServer.updateRuntime = NpcServiceServer.UpdateRuntime
NpcServiceServer.trackRuntime = NpcServiceServer.TrackRuntime
NpcServiceServer.spawnSlime = NpcServiceServer.SpawnSlime
NpcServiceServer.spawnInitialSlimes = NpcServiceServer.SpawnInitialSlimes
NpcServiceServer.onHeartbeat = NpcServiceServer.OnHeartbeat
NpcServiceServer.init = NpcServiceServer.Init
NpcServiceServer.destroy = NpcServiceServer.Destroy

type NpcServiceServer = typeof(NpcServiceServer) & {
	networker: Networker.Server,
	runtimes: { [string]: NpcRuntime },
	runtimesByModel: { [Model]: NpcRuntime },
	enemyHitbox: EnemyHitboxManager?,
	soundService: AudioServiceServerObject?,
	lootService: LootServiceServerObject?,
	goreService: GoreServiceServerObject?,
	collisionGroupsReady: boolean,
	playerCharacterAddedConnections: { [Player]: RBXScriptConnection },
	world: any?,
	npcFolder: Folder,
	slimeSpawnSettings: SlimeSpawnSettings,
	spawnCFrames: { CFrame },
	nextSpawnIndex: number,
	spawnAccumulator: number,
	despawnRefreshAccumulator: number,
	random: Random,
	missingSlimeBloodTemplateWarningShown: boolean,
	stateRefreshAccumulator: number,
	biomeRefreshAccumulator: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return NpcServiceServer :: NpcServiceServer
