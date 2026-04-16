--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local Audio = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local Animations = require(script:FindFirstAncestor("game").Shared.Modules.Items.Animations)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)

local AnimationServiceUtils = {}

export type AnimationClipName = string

export type AnimationClipConfig = {
	id: string,
	looped: boolean,
	priority: Enum.AnimationPriority,
	speed: number,
	weight: number,
	fadeTime: number,
}

export type FootstepSoundConfig = {
	soundAssetIds: { string },
	volume: number,
	playbackSpeedMin: number,
	playbackSpeedMax: number,
	rollOffMaxDistance: number,
	emitterSize: number,
}

export type FootstepPlaybackOptions = {
	parent: BasePart,
	volume: number,
	playbackSpeed: number,
	rollOffMaxDistance: number,
	emitterSize: number,
	looped: boolean,
	autoDestroy: boolean,
}

export type JumpSoundConfig = FootstepSoundConfig
export type JumpPlaybackOptions = FootstepPlaybackOptions

export type AnimationProfile = {
	name: string,
	walkSpeedThreshold: number,
	footstepCooldown: number,
	jumpCooldown: number,
	animations: { [AnimationClipName]: AnimationClipConfig },
	footstepMarkers: { string },
	footstepKeyframes: { string },
	jumpMarkers: { string },
	jumpKeyframes: { string },
	footstepSounds: { [string]: FootstepSoundConfig },
	fallbackFootstepSound: FootstepSoundConfig?,
	jumpSound: JumpSoundConfig?,
}

export type AnimationServiceState = {
	profileName: string,
	footstepsEnabled: boolean,
}

export type CharacterRig = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
}

local DEFAULT_PROFILE_NAME = "Default"
local DEFAULT_WALK_SPEED_THRESHOLD = 0.15
local DEFAULT_FOOTSTEP_COOLDOWN = 0.08
local DEFAULT_JUMP_COOLDOWN = 0.12
local MIN_FOOTSTEP_ROLLOFF_MAX_DISTANCE = 128
local MIN_FOOTSTEP_EMITTER_SIZE = 8
local MIN_JUMP_ROLLOFF_MAX_DISTANCE = 48
local MIN_JUMP_EMITTER_SIZE = 6

local RBX_ASSET_PREFIX = "rbxassetid://"

local DEFAULT_FOOTSTEP_MARKERS = { "Footstep", "LeftFootstep", "RightFootstep", "Step" }
local DEFAULT_FOOTSTEP_KEYFRAMES = {
	"Footstep",
	"LeftFootstep",
	"RightFootstep",
	"Step",
	"LeftFootDown",
	"RightFootDown",
}
local DEFAULT_JUMP_MARKERS = { "Jump", "JumpStart", "Takeoff" }
local DEFAULT_JUMP_KEYFRAMES = { "Jump", "JumpStart", "Takeoff" }
local PLAYER_AUDIO = (Audio :: any).Player or {}
local PLAYER_WALK_AUDIO = PLAYER_AUDIO.Walk or {}
local PLAYER_JUMP_AUDIO = PLAYER_AUDIO.Jump or {}
local PLAYER_ANIMATION_REGISTRY = (((Animations :: any).Player or {}).Profiles or {})[DEFAULT_PROFILE_NAME] or {}
local PLAYER_ANIMATION_IDS = PLAYER_ANIMATION_REGISTRY :: { [string]: any }

local function normalizeAssetId(rawId: any): string?
	if typeof(rawId) == "number" then
		if rawId <= 0 then
			return nil
		end
		return RBX_ASSET_PREFIX .. tostring(math.floor(rawId))
	end

	if typeof(rawId) ~= "string" then
		return nil
	end

	local assetId = string.gsub(rawId, "%s", "")
	if assetId == "" then
		return nil
	end

	if string.sub(assetId, 1, #RBX_ASSET_PREFIX) == RBX_ASSET_PREFIX then
		local numericId = string.match(assetId, "%d+")
		if numericId == nil then
			return nil
		end
		if numericId == "0" then
			return nil
		end
		return RBX_ASSET_PREFIX .. numericId
	end

	local numericOnly = string.match(assetId, "^%d+$")
	if numericOnly == nil or numericOnly == "0" then
		return nil
	end

	return RBX_ASSET_PREFIX .. numericOnly
end

local function buildDefaultAnimationClip(
	clipName: string,
	fallback: AnimationClipConfig
): AnimationClipConfig
	local animationId = normalizeAssetId(PLAYER_ANIMATION_IDS[clipName])

	return {
		id = if animationId ~= nil then animationId else fallback.id,
		looped = fallback.looped,
		priority = fallback.priority,
		speed = fallback.speed,
		weight = fallback.weight,
		fadeTime = fallback.fadeTime,
	}
end

local function createAudioBackedSoundConfig(audioEntries: any, config: FootstepSoundConfig): FootstepSoundConfig
	return {
		soundAssetIds = AudioServiceUtils.collectSoundAssetIds(audioEntries),
		volume = config.volume,
		playbackSpeedMin = config.playbackSpeedMin,
		playbackSpeedMax = config.playbackSpeedMax,
		rollOffMaxDistance = config.rollOffMaxDistance,
		emitterSize = config.emitterSize,
	}
end

local DEFAULT_FOOTSTEP_SOUND: FootstepSoundConfig = {
	soundAssetIds = {},
	volume = 1,
	playbackSpeedMin = 0.94,
	playbackSpeedMax = 1.06,
	rollOffMaxDistance = 1000,
	emitterSize = 4,
}
DEFAULT_FOOTSTEP_SOUND = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Default, DEFAULT_FOOTSTEP_SOUND)

local DEFAULT_JUMP_SOUND: JumpSoundConfig = {
	soundAssetIds = {},
	volume = 1,
	playbackSpeedMin = 0.94,
	playbackSpeedMax = 1.04,
	rollOffMaxDistance = 1000,
	emitterSize = 6,
}
DEFAULT_JUMP_SOUND = createAudioBackedSoundConfig(PLAYER_JUMP_AUDIO, DEFAULT_JUMP_SOUND)

local DEFAULT_FOOTSTEP_SOUNDS: { [string]: FootstepSoundConfig } = {
	Grass = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Grass, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.06,
		rollOffMaxDistance = 1000,
		emitterSize = 4,
	}),
	Ground = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Ground, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.05,
		rollOffMaxDistance = 1000,
		emitterSize = 4,
	}),
	Sand = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Sand, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.94,
		playbackSpeedMax = 1.03,
		rollOffMaxDistance = 1000,
		emitterSize = 4,
	}),
	Snow = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Snow, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.9,
		playbackSpeedMax = 1,
		rollOffMaxDistance = 1000,
		emitterSize = 4,
	}),
	Wood = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Wood, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.08,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
	WoodPlanks = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.WoodPlanks, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.08,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
	Metal = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Metal, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.05,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
	DiamondPlate = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.DiamondPlate, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.05,
		rollOffMaxDistance = 1000,
		emitterSize = 6,
	}),
	Concrete = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Concrete, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.94,
		playbackSpeedMax = 1.06,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
	Brick = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Brick, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.06,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
	Slate = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Slate, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.05,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
	Cobblestone = createAudioBackedSoundConfig(PLAYER_WALK_AUDIO.Cobblestone, {
		soundAssetIds = {},
		volume = 1,
		playbackSpeedMin = 0.95,
		playbackSpeedMax = 1.05,
		rollOffMaxDistance = 1000,
		emitterSize = 5,
	}),
}

local DEFAULT_PROFILE: AnimationProfile = {
	name = DEFAULT_PROFILE_NAME,
	walkSpeedThreshold = DEFAULT_WALK_SPEED_THRESHOLD,
	footstepCooldown = DEFAULT_FOOTSTEP_COOLDOWN,
	jumpCooldown = DEFAULT_JUMP_COOLDOWN,
	animations = {
		Idle = buildDefaultAnimationClip("Idle", {
			id = "",
			looped = true,
			priority = Enum.AnimationPriority.Idle,
			speed = 1,
			weight = 1,
			fadeTime = 0.2,
		}),
		Walk = buildDefaultAnimationClip("Walk", {
			id = "",
			looped = true,
			priority = Enum.AnimationPriority.Movement,
			speed = 1,
			weight = 1,
			fadeTime = 0.1,
		}),
		Jump = buildDefaultAnimationClip("Jump", {
			id = "",
			looped = true,
			priority = Enum.AnimationPriority.Action,
			speed = 1,
			weight = 1,
			fadeTime = 0.1,
		}),
		Fall = buildDefaultAnimationClip("Fall", {
			id = "",
			looped = true,
			priority = Enum.AnimationPriority.Action,
			speed = 1,
			weight = 1,
			fadeTime = 0.1,
		}),
	},
	footstepMarkers = DEFAULT_FOOTSTEP_MARKERS,
	footstepKeyframes = DEFAULT_FOOTSTEP_KEYFRAMES,
	jumpMarkers = DEFAULT_JUMP_MARKERS,
	jumpKeyframes = DEFAULT_JUMP_KEYFRAMES,
	footstepSounds = DEFAULT_FOOTSTEP_SOUNDS,
	fallbackFootstepSound = DEFAULT_FOOTSTEP_SOUND,
	jumpSound = DEFAULT_JUMP_SOUND,
}

local DEFAULT_PROFILE_REGISTRY: { [string]: AnimationProfile } = {
	[DEFAULT_PROFILE_NAME] = DEFAULT_PROFILE,
}

local RANDOM = Random.new()

AnimationServiceUtils.DEFAULT_PROFILE_NAME = DEFAULT_PROFILE_NAME
AnimationServiceUtils.DEFAULT_PROFILE_REGISTRY = DEFAULT_PROFILE_REGISTRY

local function cloneStringArray(values: { string }): { string }
	local out = Sift.Array.create(#values)
	for index, value in values do
		out[index] = value
	end
	return out
end

local function cloneSoundAssetIdArray(values: { string }): { string }
	return cloneStringArray(values)
end

local function clampNumber(value: any, minimum: number, maximum: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function normalizePositiveNumber(value: any, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end
	if value <= 0 then
		return fallback
	end
	return value
end

local function normalizeStringArray(source: any, fallback: { string }): { string }
	if typeof(source) ~= "table" then
		return cloneStringArray(fallback)
	end
	local out = cloneStringArray(source)
	if #out > 0 then
		return out
	end
	return cloneStringArray(fallback)
end

local function copyAnimationClipConfig(clip: AnimationClipConfig): AnimationClipConfig
	return {
		id = clip.id,
		looped = clip.looped,
		priority = clip.priority,
		speed = clip.speed,
		weight = clip.weight,
		fadeTime = clip.fadeTime,
	}
end

local function copyAnimations(
	animations: { [AnimationClipName]: AnimationClipConfig }
): { [AnimationClipName]: AnimationClipConfig }
	local out: { [AnimationClipName]: AnimationClipConfig } = {}
	for clipName, clip in animations do
		out[clipName] = copyAnimationClipConfig(clip)
	end
	return out
end

local function copyFootstepSoundConfig(config: FootstepSoundConfig): FootstepSoundConfig
	return {
		soundAssetIds = cloneSoundAssetIdArray(config.soundAssetIds),
		volume = config.volume,
		playbackSpeedMin = config.playbackSpeedMin,
		playbackSpeedMax = config.playbackSpeedMax,
		rollOffMaxDistance = config.rollOffMaxDistance,
		emitterSize = config.emitterSize,
	}
end

local function copyFootstepSoundMap(soundMap: { [string]: FootstepSoundConfig }): { [string]: FootstepSoundConfig }
	local out: { [string]: FootstepSoundConfig } = {}
	for materialName, config in soundMap do
		out[materialName] = copyFootstepSoundConfig(config)
	end
	return out
end

local function copyAnimationProfile(profile: AnimationProfile): AnimationProfile
	return {
		name = profile.name,
		walkSpeedThreshold = profile.walkSpeedThreshold,
		footstepCooldown = profile.footstepCooldown,
		jumpCooldown = profile.jumpCooldown,
		animations = copyAnimations(profile.animations),
		footstepMarkers = cloneStringArray(profile.footstepMarkers),
		footstepKeyframes = cloneStringArray(profile.footstepKeyframes),
		jumpMarkers = cloneStringArray(profile.jumpMarkers),
		jumpKeyframes = cloneStringArray(profile.jumpKeyframes),
		footstepSounds = copyFootstepSoundMap(profile.footstepSounds),
		fallbackFootstepSound = if profile.fallbackFootstepSound
			then copyFootstepSoundConfig(profile.fallbackFootstepSound)
			else nil,
		jumpSound = if profile.jumpSound then copyFootstepSoundConfig(profile.jumpSound) else nil,
	}
end

local function hasFootstepSounds(config: FootstepSoundConfig?): boolean
	if not config then
		return false
	end
	return #config.soundAssetIds > 0
end

local function resolveRawSoundAssetIds(source: any): any
	if source == nil then
		return nil
	end
	if typeof((source :: any).soundAssetIds) == "table" then
		return (source :: any).soundAssetIds
	end
	if typeof((source :: any).soundTemplates) == "table" then
		return (source :: any).soundTemplates
	end
	return nil
end

local function sanitizeSoundAssetIds(rawSoundAssetIds: any, fallback: FootstepSoundConfig?): { string }
	local soundAssetIds: { string } = {}

	if rawSoundAssetIds then
		for _, rawSoundAssetId in rawSoundAssetIds do
			local soundAssetId = AnimationServiceUtils.NormalizeAssetId(rawSoundAssetId)
			if soundAssetId then
				table.insert(soundAssetIds, soundAssetId)
			end
		end
	end

	if #soundAssetIds == 0 and fallback then
		return cloneSoundAssetIdArray(fallback.soundAssetIds)
	end
	return soundAssetIds
end

function AnimationServiceUtils.NormalizeAssetId(rawId: any): string?
	if typeof(rawId) == "number" then
		if rawId <= 0 then
			return nil
		end
		return RBX_ASSET_PREFIX .. tostring(math.floor(rawId))
	end

	if typeof(rawId) ~= "string" then
		return nil
	end

	local assetId = string.gsub(rawId, "%s", "")
	if assetId == "" then
		return nil
	end

	if string.sub(assetId, 1, #RBX_ASSET_PREFIX) == RBX_ASSET_PREFIX then
		local numericId = string.match(assetId, "%d+")
		if numericId == nil then
			return nil
		end
		return RBX_ASSET_PREFIX .. numericId
	end

	local numericOnly = string.match(assetId, "^%d+$")
	if numericOnly then
		return RBX_ASSET_PREFIX .. numericOnly
	end

	local trailingNumeric = string.match(assetId, "(%d+)$")
	if trailingNumeric then
		return RBX_ASSET_PREFIX .. trailingNumeric
	end

	return nil
end

function AnimationServiceUtils.ArrayToSet(items: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, item in items do
		set[item] = true
	end
	return set
end

function AnimationServiceUtils.SanitizeAnimationClipConfig(
	clipConfig: any,
	fallback: AnimationClipConfig?
): AnimationClipConfig?
	local source = if typeof(clipConfig) == "table" then clipConfig else nil
	local defaultValue = fallback
	if source == nil and defaultValue == nil then
		return nil
	end

	local fallbackId = if defaultValue then defaultValue.id else nil
	local animationId = AnimationServiceUtils.NormalizeAssetId(if source then (source :: any).id else nil)
	if animationId == nil then
		animationId = fallbackId
	end
	if animationId == nil then
		return nil
	end

	return {
		id = animationId,
		looped = if source and typeof((source :: any).looped) == "boolean"
			then (source :: any).looped
			else if defaultValue then defaultValue.looped else true,
		priority = if source and typeof((source :: any).priority) == "EnumItem"
			then (source :: any).priority
			else if defaultValue then defaultValue.priority else Enum.AnimationPriority.Movement,
		speed = normalizePositiveNumber(
			if source then (source :: any).speed else nil,
			if defaultValue then defaultValue.speed else 1
		),
		weight = clampNumber(
			if source then (source :: any).weight else nil,
			0.01,
			10,
			if defaultValue then defaultValue.weight else 1
		),
		fadeTime = clampNumber(
			if source then (source :: any).fadeTime else nil,
			0,
			2,
			if defaultValue then defaultValue.fadeTime else 0.1
		),
	}
end

function AnimationServiceUtils.SanitizeFootstepSoundConfig(
	config: any,
	fallback: FootstepSoundConfig?
): FootstepSoundConfig?
	local source = if typeof(config) == "table" then config else nil
	local defaultValue = fallback
	if source == nil and defaultValue == nil then
		return nil
	end

	local soundAssetIds = sanitizeSoundAssetIds(resolveRawSoundAssetIds(source), defaultValue)

	local playbackMin = clampNumber(
		if source then (source :: any).playbackSpeedMin else nil,
		0.25,
		4,
		if defaultValue then defaultValue.playbackSpeedMin else 1
	)
	local playbackMax = clampNumber(
		if source then (source :: any).playbackSpeedMax else nil,
		playbackMin,
		4,
		if defaultValue then defaultValue.playbackSpeedMax else 1
	)

	return {
		soundAssetIds = soundAssetIds,
		volume = clampNumber(
			if source then (source :: any).volume else nil,
			0,
			10,
			if defaultValue then defaultValue.volume else 0.45
		),
		playbackSpeedMin = playbackMin,
		playbackSpeedMax = playbackMax,
		rollOffMaxDistance = clampNumber(
			if source then (source :: any).rollOffMaxDistance else nil,
			4,
			200,
			if defaultValue then defaultValue.rollOffMaxDistance else 40
		),
		emitterSize = clampNumber(
			if source then (source :: any).emitterSize else nil,
			0,
			32,
			if defaultValue then defaultValue.emitterSize else 4
		),
	}
end

function AnimationServiceUtils.SanitizeProfile(profile: any, fallback: AnimationProfile?): AnimationProfile
	local source = if typeof(profile) == "table" then profile else {}
	local defaultProfile = if fallback then fallback else DEFAULT_PROFILE

	local profileName = if typeof((source :: any).name) == "string" and (source :: any).name ~= ""
		then (source :: any).name
		else defaultProfile.name

	local animationsSource = if typeof((source :: any).animations) == "table" then (source :: any).animations else {}
	local sanitizedAnimations: { [AnimationClipName]: AnimationClipConfig } = {}

	for clipName, defaultClip in defaultProfile.animations do
		local sanitized =
			AnimationServiceUtils.SanitizeAnimationClipConfig((animationsSource :: any)[clipName], defaultClip)
		if sanitized then
			sanitizedAnimations[clipName] = sanitized
		end
	end

	for clipName, rawClip in animationsSource do
		if sanitizedAnimations[clipName] then
			continue
		end

		local sanitized = AnimationServiceUtils.SanitizeAnimationClipConfig(rawClip, nil)
		if sanitized then
			sanitizedAnimations[clipName] = sanitized
		end
	end

	local markers = normalizeStringArray((source :: any).footstepMarkers, defaultProfile.footstepMarkers)
	local keyframes = normalizeStringArray((source :: any).footstepKeyframes, defaultProfile.footstepKeyframes)
	local jumpMarkers = normalizeStringArray((source :: any).jumpMarkers, defaultProfile.jumpMarkers)
	local jumpKeyframes = normalizeStringArray((source :: any).jumpKeyframes, defaultProfile.jumpKeyframes)

	local footstepSounds: { [string]: FootstepSoundConfig } = copyFootstepSoundMap(defaultProfile.footstepSounds)
	if typeof((source :: any).footstepSounds) == "table" then
		for materialName, rawSoundConfig in (source :: any).footstepSounds do
			if typeof(materialName) ~= "string" then
				continue
			end
			local base = footstepSounds[materialName]
			local sanitized = AnimationServiceUtils.SanitizeFootstepSoundConfig(rawSoundConfig, base)
			if sanitized then
				footstepSounds[materialName] = sanitized
			end
		end
	end

	local fallbackFootstepSound = AnimationServiceUtils.SanitizeFootstepSoundConfig(
		(source :: any).fallbackFootstepSound,
		defaultProfile.fallbackFootstepSound
	)
	local jumpSound = AnimationServiceUtils.SanitizeFootstepSoundConfig(
		(source :: any).jumpSound,
		defaultProfile.jumpSound
	)

	return {
		name = profileName,
		walkSpeedThreshold = clampNumber(
			(source :: any).walkSpeedThreshold,
			0.01,
			50,
			defaultProfile.walkSpeedThreshold
		),
		footstepCooldown = clampNumber((source :: any).footstepCooldown, 0, 1, defaultProfile.footstepCooldown),
		jumpCooldown = clampNumber((source :: any).jumpCooldown, 0, 1, defaultProfile.jumpCooldown),
		animations = sanitizedAnimations,
		footstepMarkers = markers,
		footstepKeyframes = keyframes,
		jumpMarkers = jumpMarkers,
		jumpKeyframes = jumpKeyframes,
		footstepSounds = footstepSounds,
		fallbackFootstepSound = fallbackFootstepSound,
		jumpSound = jumpSound,
	}
end

function AnimationServiceUtils.CreateDefaultProfileRegistry(): { [string]: AnimationProfile }
	local out: { [string]: AnimationProfile } = {}
	for profileName, profile in DEFAULT_PROFILE_REGISTRY do
		out[profileName] = copyAnimationProfile(profile)
	end
	return out
end

function AnimationServiceUtils.CreateProfileRegistry(
	incomingProfiles: { [string]: AnimationProfile }?
): { [string]: AnimationProfile }
	local registry = AnimationServiceUtils.CreateDefaultProfileRegistry()
	if not incomingProfiles then
		return registry
	end

	for profileName, incomingProfile in incomingProfiles do
		if typeof(profileName) ~= "string" or profileName == "" then
			continue
		end
		local defaultProfileForFallback = registry[profileName] or registry[DEFAULT_PROFILE_NAME]
		registry[profileName] = AnimationServiceUtils.SanitizeProfile(incomingProfile, defaultProfileForFallback)
	end

	return registry
end

function AnimationServiceUtils.NormalizeProfileName(
	rawProfileName: any,
	registry: { [string]: AnimationProfile },
	fallbackProfileName: string?
): string
	if typeof(rawProfileName) == "string" and rawProfileName ~= "" and registry[rawProfileName] ~= nil then
		return rawProfileName
	end

	local fallbackName = fallbackProfileName or DEFAULT_PROFILE_NAME
	if registry[fallbackName] ~= nil then
		return fallbackName
	end

	return DEFAULT_PROFILE_NAME
end

function AnimationServiceUtils.CreateDefaultState(): AnimationServiceState
	return {
		profileName = DEFAULT_PROFILE_NAME,
		footstepsEnabled = true,
	}
end

function AnimationServiceUtils.CreateState(
	profileNameRaw: any,
	footstepsEnabledRaw: any,
	registry: { [string]: AnimationProfile },
	fallbackState: AnimationServiceState?
): AnimationServiceState
	local baseState = if fallbackState then fallbackState else AnimationServiceUtils.CreateDefaultState()
	return {
		profileName = AnimationServiceUtils.NormalizeProfileName(profileNameRaw, registry, baseState.profileName),
		footstepsEnabled = if typeof(footstepsEnabledRaw) == "boolean"
			then footstepsEnabledRaw
			else baseState.footstepsEnabled,
	}
end

function AnimationServiceUtils.ResolveCharacterRig(character: Model?): CharacterRig?
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

function AnimationServiceUtils.ResolveAnimator(humanoid: Humanoid): Animator
	local existingAnimator = humanoid:FindFirstChildOfClass("Animator")
	if existingAnimator then
		return existingAnimator
	end

	local animator = Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = humanoid
	return animator
end

function AnimationServiceUtils.CreateAnimationTrack(animator: Animator, clip: AnimationClipConfig): AnimationTrack?
	local animationId = AnimationServiceUtils.NormalizeAssetId(clip.id)
	if not animationId then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.Name = "AnimationServiceClip"
	animation.AnimationId = animationId

	local success, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not success then
		return nil
	end

	local track = trackOrError :: AnimationTrack
	track.Looped = clip.looped
	track.Priority = clip.priority
	return track
end

function AnimationServiceUtils.DisableDefaultAnimateScript(character: Model)
	local animateScript = character:FindFirstChild("Animate")
	if not animateScript then
		return
	end
	if animateScript:IsA("LocalScript") or animateScript:IsA("Script") then
		(animateScript :: any).Enabled = false
	end
end

function AnimationServiceUtils.GetProfile(
	profileName: string,
	registry: { [string]: AnimationProfile }
): AnimationProfile?
	return registry[profileName]
end

function AnimationServiceUtils.GetFootstepSoundConfig(
	profile: AnimationProfile,
	material: Enum.Material
): FootstepSoundConfig?
	local materialName = material.Name
	local perSurface = profile.footstepSounds[materialName]
	if hasFootstepSounds(perSurface) then
		return perSurface
	end

	local fallback = profile.fallbackFootstepSound
	if hasFootstepSounds(fallback) then
		return fallback
	end

	return nil
end

function AnimationServiceUtils.PickRandomSoundAssetId(soundAssetIds: { string }): string?
	local count = #soundAssetIds
	if count <= 0 then
		return nil
	end
	return soundAssetIds[RANDOM:NextInteger(1, count)]
end

local function createPlaybackOptions(
	rootPart: BasePart,
	soundConfig: FootstepSoundConfig,
	minRollOffMaxDistance: number,
	minEmitterSize: number
): FootstepPlaybackOptions
	local playbackMin = soundConfig.playbackSpeedMin
	local playbackMax = soundConfig.playbackSpeedMax
	local playbackSpeed = if playbackMax > playbackMin then RANDOM:NextNumber(playbackMin, playbackMax) else playbackMin

	return {
		parent = rootPart,
		volume = soundConfig.volume,
		playbackSpeed = playbackSpeed,
		rollOffMaxDistance = math.max(soundConfig.rollOffMaxDistance, minRollOffMaxDistance),
		emitterSize = math.max(soundConfig.emitterSize, minEmitterSize),
		looped = false,
		autoDestroy = true,
	}
end

function AnimationServiceUtils.CreateFootstepPlaybackOptions(
	rootPart: BasePart,
	soundConfig: FootstepSoundConfig
): FootstepPlaybackOptions
	return createPlaybackOptions(
		rootPart,
		soundConfig,
		MIN_FOOTSTEP_ROLLOFF_MAX_DISTANCE,
		MIN_FOOTSTEP_EMITTER_SIZE
	)
end

function AnimationServiceUtils.CreateJumpPlaybackOptions(
	rootPart: BasePart,
	soundConfig: JumpSoundConfig
): JumpPlaybackOptions
	return createPlaybackOptions(
		rootPart,
		soundConfig,
		MIN_JUMP_ROLLOFF_MAX_DISTANCE,
		MIN_JUMP_EMITTER_SIZE
	)
end

function AnimationServiceUtils.ResolveFootstepSoundAssetIdAndOptions(
	rootPart: BasePart,
	material: Enum.Material,
	profile: AnimationProfile
): (string?, FootstepPlaybackOptions?)
	local soundConfig = AnimationServiceUtils.GetFootstepSoundConfig(profile, material)
	if not soundConfig then
		return nil, nil
	end

	local soundAssetId = AnimationServiceUtils.PickRandomSoundAssetId(soundConfig.soundAssetIds)
	if not soundAssetId then
		return nil, nil
	end

	local options = AnimationServiceUtils.CreateFootstepPlaybackOptions(rootPart, soundConfig)
	return soundAssetId, options
end

function AnimationServiceUtils.ResolveJumpSoundAssetIdAndOptions(
	rootPart: BasePart,
	profile: AnimationProfile
): (string?, JumpPlaybackOptions?)
	local soundConfig = profile.jumpSound
	if not hasFootstepSounds(soundConfig) then
		return nil, nil
	end

	local soundAssetId = AnimationServiceUtils.PickRandomSoundAssetId(soundConfig.soundAssetIds)
	if not soundAssetId then
		return nil, nil
	end

	local options = AnimationServiceUtils.CreateJumpPlaybackOptions(rootPart, soundConfig)
	return soundAssetId, options
end

AnimationServiceUtils.resolveFootstepSoundTemplateAndOptions =
	AnimationServiceUtils.ResolveFootstepSoundAssetIdAndOptions
AnimationServiceUtils.resolveJumpSoundTemplateAndOptions = AnimationServiceUtils.ResolveJumpSoundAssetIdAndOptions

AnimationServiceUtils.normalizeAssetId = AnimationServiceUtils.NormalizeAssetId
AnimationServiceUtils.arrayToSet = AnimationServiceUtils.ArrayToSet
AnimationServiceUtils.sanitizeAnimationClipConfig = AnimationServiceUtils.SanitizeAnimationClipConfig
AnimationServiceUtils.sanitizeFootstepSoundConfig = AnimationServiceUtils.SanitizeFootstepSoundConfig
AnimationServiceUtils.sanitizeProfile = AnimationServiceUtils.SanitizeProfile
AnimationServiceUtils.createDefaultProfileRegistry = AnimationServiceUtils.CreateDefaultProfileRegistry
AnimationServiceUtils.createProfileRegistry = AnimationServiceUtils.CreateProfileRegistry
AnimationServiceUtils.normalizeProfileName = AnimationServiceUtils.NormalizeProfileName
AnimationServiceUtils.createDefaultState = AnimationServiceUtils.CreateDefaultState
AnimationServiceUtils.createState = AnimationServiceUtils.CreateState
AnimationServiceUtils.resolveCharacterRig = AnimationServiceUtils.ResolveCharacterRig
AnimationServiceUtils.resolveAnimator = AnimationServiceUtils.ResolveAnimator
AnimationServiceUtils.createAnimationTrack = AnimationServiceUtils.CreateAnimationTrack
AnimationServiceUtils.disableDefaultAnimateScript = AnimationServiceUtils.DisableDefaultAnimateScript
AnimationServiceUtils.getProfile = AnimationServiceUtils.GetProfile
AnimationServiceUtils.getFootstepSoundConfig = AnimationServiceUtils.GetFootstepSoundConfig
AnimationServiceUtils.pickRandomSoundAssetId = AnimationServiceUtils.PickRandomSoundAssetId
AnimationServiceUtils.createFootstepPlaybackOptions = AnimationServiceUtils.CreateFootstepPlaybackOptions
AnimationServiceUtils.createJumpPlaybackOptions = AnimationServiceUtils.CreateJumpPlaybackOptions
AnimationServiceUtils.resolveFootstepSoundAssetIdAndOptions = AnimationServiceUtils.ResolveFootstepSoundAssetIdAndOptions
AnimationServiceUtils.resolveJumpSoundAssetIdAndOptions = AnimationServiceUtils.ResolveJumpSoundAssetIdAndOptions

return AnimationServiceUtils
