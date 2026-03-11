--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Audio = require(ReplicatedStorage.Shared.Modules.Items.Audio)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

local PlayerServiceUtils = {}

export type FacingSign = number
export type MoveSpringOptions = {
	damping: number?,
	frequency: number?,
	mass: number?,
	tension: number?,
	friction: number?,
	position: number?,
	velocity: number?,
	impulse: number?,
	restingVelocity: number?,
	restingPosition: number?,
}
export type HeadLookSpringOptions = MoveSpringOptions

export type CharacterRig = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
}
export type LandingSoundConfig = {
	soundAssetIds: { string },
	volume: number,
	playbackSpeedMin: number,
	playbackSpeedMax: number,
	rollOffMaxDistance: number,
	emitterSize: number,
}
export type LandingPlaybackOptions = {
	parent: BasePart,
	volume: number,
	playbackSpeed: number,
	rollOffMaxDistance: number,
	emitterSize: number,
	looped: boolean,
	autoDestroy: boolean,
}
export type InvincibilityFramesConfig = {
	duration: number,
	flickerInterval: number,
	highlightFillTransparency: number,
	highlightOutlineTransparency: number,
}

local DEFAULT_FACING_SIGN: FacingSign = 1
local DEFAULT_HORIZONTAL_DEADZONE = 0.1
local DEFAULT_MOVE_AXIS_DEADZONE = 0.025
local DEFAULT_SIDEWAYS_MOVE_SCALE = 1
local DEFAULT_ACCELERATION_EXPONENT = 1.15
local DEFAULT_MOVE_SPRING: MoveSpringOptions = {
	frequency = 2.5,
	damping = 1,
}
local DEFAULT_GROUND_RAYCAST_DISTANCE = 0.8
local DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT = 0.25
local DEFAULT_LANDING_SOUND_COOLDOWN = 0.16
local DEFAULT_LANDING_MIN_IMPACT_SPEED = 12
local DEFAULT_MOUSE_FACING_DEADZONE_PIXELS = 2
local DEFAULT_MOUSE_FACING_FLIP_HYSTERESIS_PIXELS = 16
local DEFAULT_MOUSE_FACING_FLIP_MIN_INTERVAL = 0.12
local DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES = 1.5
local DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES = 28
local DEFAULT_HEAD_LOOK_MAX_SCREEN_DISTANCE_PIXELS = 320
local DEFAULT_HEAD_LOOK_MAX_WORLD_DISTANCE = 12
local DEFAULT_HEAD_LOOK_DEADZONE_PIXELS = 6
local DEFAULT_HEAD_LOOK_SPRING: HeadLookSpringOptions = {
	frequency = 5,
	damping = 0.9,
}
local DEFAULT_DEATH_RESPAWN_HEALTH_SCALE = 0.5
local DEFAULT_INVINCIBILITY_FRAMES_DURATION = 0.75
local DEFAULT_INVINCIBILITY_FRAMES_FLICKER_INTERVAL = 0.08
local DEFAULT_INVINCIBILITY_HIGHLIGHT_FILL_TRANSPARENCY = 0.38
local DEFAULT_INVINCIBILITY_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0
local NETWORK_METHOD_SET_WORLD_READY_FOR_MOVEMENT = "setWorldReadyForMovement"
local NETWORK_METHOD_APPLY_MOVEMENT_LOCK = "applyMovementLock"
local DEFAULT_MOVEMENT_LOCK_ATTRIBUTE = "PlayerService_MovementLocked"
local DEFAULT_WORLD_UNLOCK_CHECK_INTERVAL = 0.08
local DEFAULT_WORLD_UNLOCK_RAYCAST_DISTANCE = 240
local GAME_FOLDER_NAME = "Game"
local WORLD_GENERATION_FOLDER_NAME = "WorldGeneration"
local EFFECTS_JUNK_FOLDER_NAME = "EffectsJunk"
local MIN_RESPAWN_MAX_HEALTH = 1
local MIN_LANDING_ROLLOFF_MAX_DISTANCE = 36
local MIN_LANDING_EMITTER_SIZE = 4
local MIN_INVINCIBILITY_FRAMES_DURATION = 0.05
local MIN_INVINCIBILITY_FRAMES_FLICKER_INTERVAL = 0.02
local DEFAULT_BLOOD_PARTICLES_PER_EMITTER = 10
local BLOOD_EMIT_WINDOW_SECONDS = 0.1
local DEFAULT_BLOOD_CLEANUP_BUFFER_SECONDS = 1.5
local MIN_BLOOD_CLEANUP_SECONDS = 2
local HALF_TURN_RADIANS = math.pi
local FULL_TURN_RADIANS = math.pi * 2
local QUARTER_TURN_RADIANS = math.pi * 0.5
local PLAYER_AUDIO = (Audio :: any).Player or {}
local PLAYER_LAND_AUDIO = PLAYER_AUDIO.Land or {}

local function createAudioBackedLandingConfig(audioEntries: any, config: LandingSoundConfig): LandingSoundConfig
	return {
		soundAssetIds = AudioServiceUtils.collectSoundAssetIds(audioEntries),
		volume = config.volume,
		playbackSpeedMin = config.playbackSpeedMin,
		playbackSpeedMax = config.playbackSpeedMax,
		rollOffMaxDistance = config.rollOffMaxDistance,
		emitterSize = config.emitterSize,
	}
end

local HORIZONTAL_FACING_KEYS: { [Enum.KeyCode]: FacingSign } = {
	[Enum.KeyCode.A] = -1,
	[Enum.KeyCode.Left] = -1,
	[Enum.KeyCode.D] = 1,
	[Enum.KeyCode.Right] = 1,
}
local DEFAULT_LANDING_SOUND: LandingSoundConfig = {
	soundAssetIds = {},
	volume = 0.58,
	playbackSpeedMin = 0.84,
	playbackSpeedMax = 0.94,
	rollOffMaxDistance = 1000,
	emitterSize = 6,
}
DEFAULT_LANDING_SOUND = createAudioBackedLandingConfig(PLAYER_LAND_AUDIO.Default, DEFAULT_LANDING_SOUND)

local LANDING_SOUNDS_BY_SURFACE: { [string]: LandingSoundConfig } = {
	Grass = createAudioBackedLandingConfig(PLAYER_LAND_AUDIO.Grass, {
		soundAssetIds = {},
		volume = 0.55,
		playbackSpeedMin = 0.82,
		playbackSpeedMax = 0.93,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
	Ground = createAudioBackedLandingConfig(PLAYER_LAND_AUDIO.Ground, {
		soundAssetIds = {},
		volume = 0.58,
		playbackSpeedMin = 0.83,
		playbackSpeedMax = 0.95,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
	Sand = createAudioBackedLandingConfig(PLAYER_LAND_AUDIO.Sand, {
		soundAssetIds = {},
		volume = 0.54,
		playbackSpeedMin = 0.8,
		playbackSpeedMax = 0.91,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
	Snow = createAudioBackedLandingConfig(PLAYER_LAND_AUDIO.Snow, {
		soundAssetIds = {},
		volume = 0.52,
		playbackSpeedMin = 0.76,
		playbackSpeedMax = 0.89,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
}

local LANDING_SOUND_ALIASES: { [string]: string } = {
	LeafyGrass = "Grass",
	Mud = "Ground",
	Asphalt = "Ground",
	Pavement = "Ground",
	Rock = "Ground",
	CrackedLava = "Ground",
	Basalt = "Ground",
	Glacier = "Snow",
	Ice = "Snow",
	Salt = "Snow",
	Plastic = "Ground",
	SmoothPlastic = "Ground",
	Wood = "Ground",
	WoodPlanks = "Ground",
	Metal = "Ground",
	DiamondPlate = "Ground",
	Concrete = "Ground",
	Brick = "Ground",
	Slate = "Ground",
	Cobblestone = "Ground",
	Fabric = "Ground",
}

local RANDOM = Random.new()

local function normalizeSignedRadians(angleRadians: number): number
	local normalized = (angleRadians + HALF_TURN_RADIANS) % FULL_TURN_RADIANS
	if normalized < 0 then
		normalized += FULL_TURN_RADIANS
	end
	return normalized - HALF_TURN_RADIANS
end

PlayerServiceUtils.DEFAULT_FACING_SIGN = DEFAULT_FACING_SIGN
PlayerServiceUtils.DEFAULT_HORIZONTAL_DEADZONE = DEFAULT_HORIZONTAL_DEADZONE
PlayerServiceUtils.DEFAULT_MOVE_AXIS_DEADZONE = DEFAULT_MOVE_AXIS_DEADZONE
PlayerServiceUtils.DEFAULT_SIDEWAYS_MOVE_SCALE = DEFAULT_SIDEWAYS_MOVE_SCALE
PlayerServiceUtils.DEFAULT_ACCELERATION_EXPONENT = DEFAULT_ACCELERATION_EXPONENT
PlayerServiceUtils.DEFAULT_MOVE_SPRING = DEFAULT_MOVE_SPRING
PlayerServiceUtils.HORIZONTAL_FACING_KEYS = HORIZONTAL_FACING_KEYS
PlayerServiceUtils.DEFAULT_GROUND_RAYCAST_DISTANCE = DEFAULT_GROUND_RAYCAST_DISTANCE
PlayerServiceUtils.DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT = DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT
PlayerServiceUtils.DEFAULT_LANDING_SOUND_COOLDOWN = DEFAULT_LANDING_SOUND_COOLDOWN
PlayerServiceUtils.DEFAULT_LANDING_MIN_IMPACT_SPEED = DEFAULT_LANDING_MIN_IMPACT_SPEED
PlayerServiceUtils.DEFAULT_MOUSE_FACING_DEADZONE_PIXELS = DEFAULT_MOUSE_FACING_DEADZONE_PIXELS
PlayerServiceUtils.DEFAULT_MOUSE_FACING_FLIP_HYSTERESIS_PIXELS = DEFAULT_MOUSE_FACING_FLIP_HYSTERESIS_PIXELS
PlayerServiceUtils.DEFAULT_MOUSE_FACING_FLIP_MIN_INTERVAL = DEFAULT_MOUSE_FACING_FLIP_MIN_INTERVAL
PlayerServiceUtils.DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES = DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES
PlayerServiceUtils.DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES = DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES
PlayerServiceUtils.DEFAULT_HEAD_LOOK_MAX_SCREEN_DISTANCE_PIXELS = DEFAULT_HEAD_LOOK_MAX_SCREEN_DISTANCE_PIXELS
PlayerServiceUtils.DEFAULT_HEAD_LOOK_MAX_WORLD_DISTANCE = DEFAULT_HEAD_LOOK_MAX_WORLD_DISTANCE
PlayerServiceUtils.DEFAULT_HEAD_LOOK_DEADZONE_PIXELS = DEFAULT_HEAD_LOOK_DEADZONE_PIXELS
PlayerServiceUtils.DEFAULT_HEAD_LOOK_SPRING = DEFAULT_HEAD_LOOK_SPRING
PlayerServiceUtils.DEFAULT_DEATH_RESPAWN_HEALTH_SCALE = DEFAULT_DEATH_RESPAWN_HEALTH_SCALE
PlayerServiceUtils.DEFAULT_INVINCIBILITY_FRAMES_DURATION = DEFAULT_INVINCIBILITY_FRAMES_DURATION
PlayerServiceUtils.DEFAULT_INVINCIBILITY_FRAMES_FLICKER_INTERVAL = DEFAULT_INVINCIBILITY_FRAMES_FLICKER_INTERVAL
PlayerServiceUtils.DEFAULT_INVINCIBILITY_HIGHLIGHT_FILL_TRANSPARENCY = DEFAULT_INVINCIBILITY_HIGHLIGHT_FILL_TRANSPARENCY
PlayerServiceUtils.DEFAULT_INVINCIBILITY_HIGHLIGHT_OUTLINE_TRANSPARENCY = DEFAULT_INVINCIBILITY_HIGHLIGHT_OUTLINE_TRANSPARENCY
PlayerServiceUtils.NETWORK_METHOD_SET_WORLD_READY_FOR_MOVEMENT = NETWORK_METHOD_SET_WORLD_READY_FOR_MOVEMENT
PlayerServiceUtils.NETWORK_METHOD_APPLY_MOVEMENT_LOCK = NETWORK_METHOD_APPLY_MOVEMENT_LOCK
PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE = DEFAULT_MOVEMENT_LOCK_ATTRIBUTE
PlayerServiceUtils.DEFAULT_WORLD_UNLOCK_CHECK_INTERVAL = DEFAULT_WORLD_UNLOCK_CHECK_INTERVAL
PlayerServiceUtils.DEFAULT_WORLD_UNLOCK_RAYCAST_DISTANCE = DEFAULT_WORLD_UNLOCK_RAYCAST_DISTANCE
PlayerServiceUtils.GAME_FOLDER_NAME = GAME_FOLDER_NAME
PlayerServiceUtils.WORLD_GENERATION_FOLDER_NAME = WORLD_GENERATION_FOLDER_NAME
PlayerServiceUtils.EFFECTS_JUNK_FOLDER_NAME = EFFECTS_JUNK_FOLDER_NAME
PlayerServiceUtils.MIN_RESPAWN_MAX_HEALTH = MIN_RESPAWN_MAX_HEALTH

function PlayerServiceUtils.getOrCreateWorkspaceGameFolder(): Folder
	return WorkspaceFolders.getOrCreateGameFolder()
end

function PlayerServiceUtils.computeRespawnHealthFromDeath(maxHealthRaw: any, scaleRaw: any): number
	local maxHealth = if typeof(maxHealthRaw) == "number" and maxHealthRaw == maxHealthRaw then maxHealthRaw else 100
	local scale = if typeof(scaleRaw) == "number" and scaleRaw == scaleRaw
		then math.max(0, scaleRaw)
		else DEFAULT_DEATH_RESPAWN_HEALTH_SCALE
	return math.max(MIN_RESPAWN_MAX_HEALTH, maxHealth * scale)
end

function PlayerServiceUtils.computeRespawnMaxHealthFromDeath(maxHealthRaw: any, scaleRaw: any): number
	return PlayerServiceUtils.computeRespawnHealthFromDeath(maxHealthRaw, scaleRaw)
end

function PlayerServiceUtils.sanitizeInvincibilityFramesConfig(configRaw: any): InvincibilityFramesConfig
	local source = if typeof(configRaw) == "table" then configRaw else {}
	local duration = if typeof((source :: any).duration) == "number" and (source :: any).duration == (source :: any).duration
		then math.max(MIN_INVINCIBILITY_FRAMES_DURATION, (source :: any).duration)
		else DEFAULT_INVINCIBILITY_FRAMES_DURATION
	local flickerInterval = if typeof((source :: any).flickerInterval) == "number"
			and (source :: any).flickerInterval == (source :: any).flickerInterval
		then math.max(MIN_INVINCIBILITY_FRAMES_FLICKER_INTERVAL, (source :: any).flickerInterval)
		else DEFAULT_INVINCIBILITY_FRAMES_FLICKER_INTERVAL
	local highlightFillTransparency = if typeof((source :: any).highlightFillTransparency) == "number"
			and (source :: any).highlightFillTransparency == (source :: any).highlightFillTransparency
		then math.clamp((source :: any).highlightFillTransparency, 0, 1)
		else DEFAULT_INVINCIBILITY_HIGHLIGHT_FILL_TRANSPARENCY
	local highlightOutlineTransparency = if typeof((source :: any).highlightOutlineTransparency) == "number"
			and (source :: any).highlightOutlineTransparency == (source :: any).highlightOutlineTransparency
		then math.clamp((source :: any).highlightOutlineTransparency, 0, 1)
		else DEFAULT_INVINCIBILITY_HIGHLIGHT_OUTLINE_TRANSPARENCY

	return {
		duration = duration,
		flickerInterval = flickerInterval,
		highlightFillTransparency = highlightFillTransparency,
		highlightOutlineTransparency = highlightOutlineTransparency,
	}
end

function PlayerServiceUtils.sanitizeFacingSign(value: any, fallback: FacingSign?): FacingSign
	if value == -1 then
		return -1
	end
	if value == 1 then
		return 1
	end

	return fallback or DEFAULT_FACING_SIGN
end

function PlayerServiceUtils.resolveCharacterRig(character: Model?): CharacterRig?
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
	local rootPart = if rootPartCandidate and rootPartCandidate:IsA("BasePart") then rootPartCandidate else nil
	if not rootPart then
		return nil
	end

	return {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
	}
end

function PlayerServiceUtils.resolveCharacterRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end

	if character.PrimaryPart then
		return character.PrimaryPart
	end

	local lowerTorso = character:FindFirstChild("LowerTorso")
	if lowerTorso and lowerTorso:IsA("BasePart") then
		return lowerTorso
	end

	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
end

function PlayerServiceUtils.getOrCreateEffectsJunkFolder(character: Model): Folder
	local existing = character:FindFirstChild(EFFECTS_JUNK_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = EFFECTS_JUNK_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function getOrCreateWorkspaceEffectsJunkFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(EFFECTS_JUNK_FOLDER_NAME)
end

local function resolveBloodEffectTemplate(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets or not assets:IsA("Folder") then
		return nil
	end

	local effects = assets:FindFirstChild("Effects")
	if not effects or not effects:IsA("Folder") then
		return nil
	end

	local blood = effects:FindFirstChild("Blood")
	if blood and blood:IsA("BasePart") then
		return blood
	end

	return nil
end

local function getParticleEmitterLifetimeMax(emitter: ParticleEmitter): number
	local lifetime = emitter.Lifetime
	return math.max(0, lifetime.Min, lifetime.Max)
end

function PlayerServiceUtils.emitBloodEffect(_character: Model, _originPart: BasePart?, _emitCountRaw: any): boolean
	return false
end

function PlayerServiceUtils.resolveHeadPart(character: Model): BasePart?
	local headCandidate = character:FindFirstChild("Head")
	if headCandidate and headCandidate:IsA("BasePart") then
		return headCandidate
	end

	return nil
end

function PlayerServiceUtils.resolveNeckJoint(character: Model): Motor6D?
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == "Neck" then
			return descendant
		end
	end

	local headPart = PlayerServiceUtils.resolveHeadPart(character)
	if not headPart then
		return nil
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part1 == headPart then
			return descendant
		end
	end

	return nil
end

function PlayerServiceUtils.resolveFootParts(character: Model): (BasePart?, BasePart?)
	local leftFootCandidate = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
	local rightFootCandidate = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
	local leftFoot = if leftFootCandidate and leftFootCandidate:IsA("BasePart") then leftFootCandidate else nil
	local rightFoot = if rightFootCandidate and rightFootCandidate:IsA("BasePart") then rightFootCandidate else nil
	return leftFoot, rightFoot
end

function PlayerServiceUtils.createGroundRaycastParams(character: Model): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = false
	return raycastParams
end

function PlayerServiceUtils.createWorldUnlockRaycastParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	return params
end

function PlayerServiceUtils.isSurfaceTerrainPart(part: BasePart?): boolean
	if part == nil then
		return false
	end
	if not part.CanCollide then
		return false
	end
	if part.LocalTransparencyModifier >= 0.99 then
		return false
	end

	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_GENERATION_FOLDER_NAME)
	if worldFolder == nil then
		return false
	end

	if not part:IsDescendantOf(worldFolder) then
		return false
	end

	local terrainFolder = part:FindFirstAncestor("Terrain")
	if terrainFolder == nil then
		return false
	end

	return terrainFolder:IsDescendantOf(worldFolder)
end

local function raycastGroundFromPart(
	part: BasePart?,
	raycastParams: RaycastParams?,
	raycastDistance: number?,
	originLift: number?
): RaycastResult?
	if part == nil or raycastParams == nil then
		return nil
	end

	local lift = if originLift then math.max(0, originLift) else DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT
	local reach = math.max(0.25, if raycastDistance then raycastDistance else DEFAULT_GROUND_RAYCAST_DISTANCE)
	local distance = math.max(0.5, reach + part.Size.Y * 0.5)
	local origin = part.Position + Vector3.new(0, lift, 0)
	local direction = Vector3.new(0, -(distance + lift), 0)
	return Workspace:Raycast(origin, direction, raycastParams)
end

local function pickNearestRaycastResult(a: RaycastResult?, b: RaycastResult?): RaycastResult?
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	if a.Distance <= b.Distance then
		return a
	end
	return b
end

function PlayerServiceUtils.sampleGroundFromFeet(
	leftFoot: BasePart?,
	rightFoot: BasePart?,
	rootPart: BasePart,
	raycastParams: RaycastParams?,
	raycastDistance: number?
): RaycastResult?
	local leftHit = raycastGroundFromPart(leftFoot, raycastParams, raycastDistance, DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT)
	local rightHit = raycastGroundFromPart(rightFoot, raycastParams, raycastDistance, DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT)
	local bestHit = pickNearestRaycastResult(leftHit, rightHit)
	if bestHit ~= nil then
		return bestHit
	end

	return raycastGroundFromPart(rootPart, raycastParams, raycastDistance, DEFAULT_GROUND_RAYCAST_ORIGIN_LIFT + 0.2)
end

function PlayerServiceUtils.resolveLandingSurface(material: Enum.Material): string
	local materialName = material.Name
	local alias = LANDING_SOUND_ALIASES[materialName]
	if alias then
		return alias
	end
	return materialName
end

function PlayerServiceUtils.getLandingSoundConfig(material: Enum.Material): LandingSoundConfig?
	local surfaceName = PlayerServiceUtils.resolveLandingSurface(material)
	local perSurface = LANDING_SOUNDS_BY_SURFACE[surfaceName]
	if perSurface and #perSurface.soundAssetIds > 0 then
		return perSurface
	end

	if #DEFAULT_LANDING_SOUND.soundAssetIds > 0 then
		return DEFAULT_LANDING_SOUND
	end

	return nil
end

function PlayerServiceUtils.resolveLandingVolumeScale(impactSpeed: number): number
	local normalizedImpact = math.clamp((impactSpeed - DEFAULT_LANDING_MIN_IMPACT_SPEED) / 32, 0, 1)
	return 0.78 + normalizedImpact * 0.48
end

function PlayerServiceUtils.pickRandomLandingSoundAssetId(soundAssetIds: { string }): string?
	local count = #soundAssetIds
	if count <= 0 then
		return nil
	end
	return soundAssetIds[RANDOM:NextInteger(1, count)]
end

function PlayerServiceUtils.createLandingPlaybackOptions(
	rootPart: BasePart,
	config: LandingSoundConfig,
	impactSpeed: number
): LandingPlaybackOptions
	local playbackMin = config.playbackSpeedMin
	local playbackMax = config.playbackSpeedMax
	local playbackSpeed = if playbackMax > playbackMin then RANDOM:NextNumber(playbackMin, playbackMax) else playbackMin
	local volumeScale = PlayerServiceUtils.resolveLandingVolumeScale(impactSpeed)

	return {
		parent = rootPart,
		volume = config.volume * volumeScale,
		playbackSpeed = playbackSpeed,
		rollOffMaxDistance = math.max(config.rollOffMaxDistance, MIN_LANDING_ROLLOFF_MAX_DISTANCE),
		emitterSize = math.max(config.emitterSize, MIN_LANDING_EMITTER_SIZE),
		looped = false,
		autoDestroy = true,
	}
end

function PlayerServiceUtils.resolveLandingSoundAssetIdAndOptions(
	rootPart: BasePart,
	material: Enum.Material,
	impactSpeed: number
): (string?, LandingPlaybackOptions?)
	local config = PlayerServiceUtils.getLandingSoundConfig(material)
	if config == nil then
		return nil, nil
	end

	local soundAssetId = PlayerServiceUtils.pickRandomLandingSoundAssetId(config.soundAssetIds)
	if soundAssetId == nil then
		return nil, nil
	end

	return soundAssetId, PlayerServiceUtils.createLandingPlaybackOptions(rootPart, config, impactSpeed)
end

function PlayerServiceUtils.applyCharacterSettings(humanoid: Humanoid)
	humanoid.AutoRotate = false
end

function PlayerServiceUtils.isHumanoidAlive(humanoid: Humanoid?): boolean
	if humanoid == nil then
		return false
	end

	if humanoid.Health <= 0 then
		return false
	end

	return humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

function PlayerServiceUtils.getFacingFromMoveDirection(moveDirection: Vector3, deadzone: number?): FacingSign?
	local threshold = if deadzone then math.max(0, deadzone) else DEFAULT_HORIZONTAL_DEADZONE
	local x = moveDirection.X

	if math.abs(x) <= threshold then
		return nil
	end

	return if x > 0 then 1 else -1
end

function PlayerServiceUtils.isMoveDirectionActive(moveDirection: Vector3, deadzone: number?): boolean
	local threshold = if deadzone then math.max(0, deadzone) else DEFAULT_HORIZONTAL_DEADZONE
	return moveDirection.Magnitude > threshold
end

function PlayerServiceUtils.getFacingFromHorizontalKeyState(isKeyDown: (keyCode: Enum.KeyCode) -> boolean): FacingSign?
	local leftDown = false
	local rightDown = false

	for keyCode, facingSign in HORIZONTAL_FACING_KEYS do
		if not isKeyDown(keyCode) then
			continue
		end

		if facingSign == -1 then
			leftDown = true
		else
			rightDown = true
		end
	end

	if leftDown == rightDown then
		return nil
	end

	return if rightDown then 1 else -1
end

function PlayerServiceUtils.getFacingFromScreenX(mouseX: number, targetX: number, deadzonePixels: number?): FacingSign?
	local threshold = if deadzonePixels then math.max(0, deadzonePixels) else DEFAULT_MOUSE_FACING_DEADZONE_PIXELS
	local delta = mouseX - targetX

	if math.abs(delta) <= threshold then
		return nil
	end

	return if delta > 0 then 1 else -1
end

function PlayerServiceUtils.getFacingFlipFromScreenX(
	mouseX: number,
	targetX: number,
	currentFacingRaw: any,
	hysteresisPixels: number?
): FacingSign?
	local currentFacing = PlayerServiceUtils.sanitizeFacingSign(currentFacingRaw, DEFAULT_FACING_SIGN)
	local threshold =
		if hysteresisPixels then math.max(0, hysteresisPixels) else DEFAULT_MOUSE_FACING_FLIP_HYSTERESIS_PIXELS
	local delta = mouseX - targetX

	if currentFacing == 1 then
		if delta < -threshold then
			return -1
		end
		return nil
	end

	if delta > threshold then
		return 1
	end
	return nil
end

function PlayerServiceUtils.getScreenLookAngleRadians(mouseX: number, mouseY: number, targetX: number, targetY: number): number?
	local deltaX = mouseX - targetX
	local deltaY = targetY - mouseY
	if math.abs(deltaX) <= 1e-4 and math.abs(deltaY) <= 1e-4 then
		return nil
	end

	return math.atan2(deltaY, deltaX)
end

function PlayerServiceUtils.getRelativeLookAngleRadians(screenLookAngleRadians: number, facingSignRaw: any): number
	local facingSign = PlayerServiceUtils.sanitizeFacingSign(facingSignRaw, DEFAULT_FACING_SIGN)
	local forwardAngle = if facingSign == 1 then 0 else HALF_TURN_RADIANS
	local relativeLookAngleRadians = normalizeSignedRadians(screenLookAngleRadians - forwardAngle)
	if facingSign == -1 then
		relativeLookAngleRadians = -relativeLookAngleRadians
	end
	return relativeLookAngleRadians
end

function PlayerServiceUtils.shouldFlipFacingFromRelativeLookAngle(relativeLookAngleRadians: number): boolean
	return relativeLookAngleRadians > QUARTER_TURN_RADIANS or relativeLookAngleRadians < -QUARTER_TURN_RADIANS
end

function PlayerServiceUtils.clampLookAngleRadians(relativeLookAngleRadians: number, maxYawDegrees: number?): number
	local maxYawRadians =
		math.rad(math.max(0, if maxYawDegrees then maxYawDegrees else DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES))
	return math.clamp(relativeLookAngleRadians, -maxYawRadians, maxYawRadians)
end

function PlayerServiceUtils.getNormalizedScreenAxisFromX(
	mouseX: number,
	targetX: number,
	maxDistancePixels: number?,
	deadzonePixels: number?
): number
	local threshold = if deadzonePixels then math.max(0, deadzonePixels) else DEFAULT_HEAD_LOOK_DEADZONE_PIXELS
	local maxDistance =
		math.max(1, if maxDistancePixels then maxDistancePixels else DEFAULT_HEAD_LOOK_MAX_SCREEN_DISTANCE_PIXELS)
	local delta = mouseX - targetX

	if math.abs(delta) <= threshold then
		return 0
	end

	return math.clamp(delta / maxDistance, -1, 1)
end

function PlayerServiceUtils.getMouseWorldPointOnPlaneX(camera: Camera, mouseX: number, mouseY: number, planeX: number): Vector3?
	local mouseRay = camera:ViewportPointToRay(mouseX, mouseY)
	local rayDirection = mouseRay.Direction
	local rayOrigin = mouseRay.Origin
	local denominator = rayDirection.X
	if math.abs(denominator) <= 1e-5 then
		return nil
	end

	local t = (planeX - rayOrigin.X) / denominator
	if t <= 0 then
		return nil
	end

	return rayOrigin + rayDirection * t
end

function PlayerServiceUtils.getNormalizedWorldAxisFromZ(
	targetZ: number,
	originZ: number,
	maxDistance: number?
): number
	local range = math.max(0.001, if maxDistance then maxDistance else DEFAULT_HEAD_LOOK_MAX_WORLD_DISTANCE)
	return math.clamp((targetZ - originZ) / range, -1, 1)
end

function PlayerServiceUtils.getHorizontalInputAxis(isKeyDown: (keyCode: Enum.KeyCode) -> boolean): number
	local facing = PlayerServiceUtils.getFacingFromHorizontalKeyState(isKeyDown)
	if not facing then
		return 0
	end

	return facing
end

function PlayerServiceUtils.getFacingFromLookVector(lookVector: Vector3, fallback: FacingSign?): FacingSign
	if math.abs(lookVector.X) < 0.001 then
		return fallback or DEFAULT_FACING_SIGN
	end

	return if lookVector.X > 0 then 1 else -1
end

function PlayerServiceUtils.snapRootPartFacing(rootPart: BasePart, facingSign: FacingSign)
	local position = rootPart.Position
	local target = position + Vector3.new(0, 0, -facingSign)
	local preservedLinearVelocity = rootPart.AssemblyLinearVelocity
	local preservedAngularVelocity = rootPart.AssemblyAngularVelocity
	rootPart.CFrame = CFrame.lookAt(position, target, Vector3.yAxis)
	rootPart.AssemblyLinearVelocity = preservedLinearVelocity
	rootPart.AssemblyAngularVelocity = preservedAngularVelocity
end

function PlayerServiceUtils.ensureRootPartUpright(rootPart: BasePart, facingSign: FacingSign, toleranceDegrees: number?): boolean
	local tolerance = math.max(0, if toleranceDegrees then toleranceDegrees else DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES)
	local upDot = math.clamp(rootPart.CFrame.UpVector:Dot(Vector3.yAxis), -1, 1)
	local tiltDegrees = math.deg(math.acos(upDot))
	if tiltDegrees <= tolerance then
		return false
	end

	PlayerServiceUtils.snapRootPartFacing(rootPart, facingSign)
	return true
end

function PlayerServiceUtils.getSidewaysMoveVector(axis: number, scale: number?): Vector3
	local moveScale = if scale then scale else DEFAULT_SIDEWAYS_MOVE_SCALE

	return Vector3.new(0, 0, -math.clamp(axis, -1, 1) * moveScale)
end

function PlayerServiceUtils.applyAccelerationCurve(axis: number, exponent: number?): number
	local curveExponent = if exponent then math.max(1, exponent) else DEFAULT_ACCELERATION_EXPONENT
	local magnitude = math.clamp(math.abs(axis), 0, 1)
	local curvedMagnitude = magnitude ^ curveExponent
	return if axis < 0 then -curvedMagnitude else curvedMagnitude
end

function PlayerServiceUtils.applySidewaysConstraint(rootPart: BasePart, lockedDepthX: number?)
	local velocity = rootPart.AssemblyLinearVelocity

	rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, velocity.Z)

	if lockedDepthX == nil then
		return
	end

	local cf = rootPart.CFrame
	local position = cf.Position
	local rotation = cf - position
	rootPart.CFrame = CFrame.new(lockedDepthX, position.Y, position.Z) * rotation
end

function PlayerServiceUtils.applyNeckLookAngle(
	neckJoint: Motor6D?,
	baseC0: CFrame?,
	relativeLookAngleRadians: number,
	maxYawDegrees: number?
)
	if not neckJoint or not baseC0 then
		return
	end

	local clampedLookAngle = PlayerServiceUtils.clampLookAngleRadians(relativeLookAngleRadians, maxYawDegrees)
	neckJoint.C0 = baseC0 * CFrame.Angles(-clampedLookAngle, 0, 0)
end

function PlayerServiceUtils.applyNeckLook(
	neckJoint: Motor6D?,
	baseC0: CFrame?,
	axis: number,
	maxYawDegrees: number?,
	_: FacingSign?
)
	if not neckJoint or not baseC0 then
		return
	end

	local clampedAxis = math.clamp(axis, -1, 1)
	local lookDegrees = math.max(0, maxYawDegrees or DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES)
	local lookRadians = math.rad(clampedAxis * lookDegrees)
	PlayerServiceUtils.applyNeckLookAngle(neckJoint, baseC0, lookRadians, lookDegrees)
end

function PlayerServiceUtils.resetNeckLook(neckJoint: Motor6D?, baseC0: CFrame?)
	if not neckJoint or not baseC0 then
		return
	end

	neckJoint.C0 = baseC0
end

return PlayerServiceUtils
