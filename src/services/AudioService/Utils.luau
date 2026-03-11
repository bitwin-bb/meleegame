--!strict
local TweenService = game:GetService("TweenService")

local AudioServiceUtils = {}

export type SoundCategory = "Music" | "SFX" | "UI" | "Voice"

export type AudioServiceState = {
	masterVolume: number,
	muted: boolean,
	categoryVolumes: { [string]: number },
}

export type PlaybackOptions = {
	category: SoundCategory,
	channel: string?,
	looped: boolean?,
	volume: number?,
	playbackSpeed: number?,
	timePosition: number?,
	fadeInTime: number?,
	fadeOutTime: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
	autoDestroy: boolean?,
	replaceChannel: boolean?,
	parent: Instance?,
}

local CATEGORY_ORDER: { SoundCategory } = { "Music", "SFX", "UI", "Voice" }
local CATEGORY_SET: { [string]: boolean } = {}
for _, category in CATEGORY_ORDER do
	CATEGORY_SET[category] = true
end

local DEFAULT_CATEGORY: SoundCategory = "SFX"
local DEFAULT_MASTER_VOLUME = 1
local DEFAULT_CATEGORY_VOLUMES: { [string]: number } = {
	Music = 0.75,
	SFX = 1,
	UI = 1,
	Voice = 1,
}

AudioServiceUtils.CATEGORY_ORDER = CATEGORY_ORDER
AudioServiceUtils.DEFAULT_CATEGORY = DEFAULT_CATEGORY
AudioServiceUtils.DEFAULT_MASTER_VOLUME = DEFAULT_MASTER_VOLUME
AudioServiceUtils.DEFAULT_CATEGORY_VOLUMES = DEFAULT_CATEGORY_VOLUMES

local function clampNumber(value: any, minimum: number, maximum: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end

	return math.clamp(value, minimum, maximum)
end

function AudioServiceUtils.normalizeSoundAssetId(rawId: any): string?
	if typeof(rawId) == "number" then
		if rawId <= 0 then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(rawId))
	end

	if typeof(rawId) ~= "string" then
		return nil
	end

	local value = string.gsub(rawId, "%s", "")
	if value == "" then
		return nil
	end

	if string.sub(value, 1, 13) == "rbxassetid://" then
		local numericId = string.match(value, "%d+")
		if numericId == nil then
			return nil
		end
		return "rbxassetid://" .. numericId
	end

	local numericOnly = string.match(value, "^%d+$")
	if numericOnly then
		return "rbxassetid://" .. numericOnly
	end

	local trailingNumeric = string.match(value, "(%d+)$")
	if trailingNumeric then
		return "rbxassetid://" .. trailingNumeric
	end

	return nil
end

function AudioServiceUtils.resolveSoundAssetId(soundSourceRaw: any): string?
	if typeof(soundSourceRaw) == "Instance" then
		local instance = soundSourceRaw :: Instance
		if instance:IsA("Sound") then
			return AudioServiceUtils.normalizeSoundAssetId(instance.SoundId)
		end
		return nil
	end

	if typeof(soundSourceRaw) == "table" then
		local source = soundSourceRaw :: { [string]: any }
		if typeof(source.sound) == "Instance" and source.sound:IsA("Sound") then
			return AudioServiceUtils.normalizeSoundAssetId((source.sound :: Sound).SoundId)
		end

		local directId = source.sound or source.id or source.soundId or source.assetId or source.source
		if directId ~= nil then
			return AudioServiceUtils.normalizeSoundAssetId(directId)
		end
	end

	return AudioServiceUtils.normalizeSoundAssetId(soundSourceRaw)
end

local function collectSoundAssetIdsFromSource(
	sourceRaw: any,
	out: { string },
	seen: { [string]: boolean }
)
	if sourceRaw == nil then
		return
	end

	if typeof(sourceRaw) == "table" then
		local source = sourceRaw :: { [any]: any }
		local directId = AudioServiceUtils.resolveSoundAssetId(source)
		if directId ~= nil and seen[directId] ~= true then
			seen[directId] = true
			table.insert(out, directId)
		end

		for _, nested in source do
			collectSoundAssetIdsFromSource(nested, out, seen)
		end
		return
	end

	local soundAssetId = AudioServiceUtils.resolveSoundAssetId(sourceRaw)
	if soundAssetId == nil or seen[soundAssetId] == true then
		return
	end

	seen[soundAssetId] = true
	table.insert(out, soundAssetId)
end

function AudioServiceUtils.collectSoundAssetIds(sourceRaw: any): { string }
	local soundAssetIds = {}
	local seen = {}
	collectSoundAssetIdsFromSource(sourceRaw, soundAssetIds, seen)
	return soundAssetIds
end

function AudioServiceUtils.normalizeCategoryOrNil(value: any): SoundCategory?
	if typeof(value) ~= "string" then
		return nil
	end

	if value == "Music" or value == "SFX" or value == "UI" or value == "Voice" then
		return value
	end

	return nil
end

function AudioServiceUtils.sanitizeCategory(value: any, fallback: SoundCategory?): SoundCategory
	local normalized = AudioServiceUtils.normalizeCategoryOrNil(value)
	if normalized then
		return normalized
	end
	return (fallback or DEFAULT_CATEGORY) :: SoundCategory
end

function AudioServiceUtils.sanitizeVolume(value: any, fallback: number?): number
	return clampNumber(value, 0, 2, fallback or 1)
end

function AudioServiceUtils.cloneCategoryVolumes(source: { [string]: number }): { [string]: number }
	local cloned = {}
	for key, value in source do
		cloned[key] = value
	end
	return cloned
end

function AudioServiceUtils.createDefaultCategoryVolumes(): { [string]: number }
	return AudioServiceUtils.cloneCategoryVolumes(DEFAULT_CATEGORY_VOLUMES)
end

function AudioServiceUtils.sanitizeCategoryVolumes(
	rawVolumes: any,
	fallbackVolumes: { [string]: number }?
): { [string]: number }
	local source = if typeof(rawVolumes) == "table" then rawVolumes else {}
	local base = if fallbackVolumes then fallbackVolumes else DEFAULT_CATEGORY_VOLUMES
	local result = {}

	for _, category in CATEGORY_ORDER do
		result[category] = AudioServiceUtils.sanitizeVolume((source :: any)[category], base[category])
	end

	return result
end

function AudioServiceUtils.createDefaultState(): AudioServiceState
	return {
		masterVolume = DEFAULT_MASTER_VOLUME,
		muted = false,
		categoryVolumes = AudioServiceUtils.createDefaultCategoryVolumes(),
	}
end

function AudioServiceUtils.createState(
	masterVolumeRaw: any,
	mutedRaw: any,
	categoryVolumesRaw: any,
	fallbackState: AudioServiceState?
): AudioServiceState
	local fallback = if fallbackState then fallbackState else AudioServiceUtils.createDefaultState()
	return {
		masterVolume = AudioServiceUtils.sanitizeVolume(masterVolumeRaw, fallback.masterVolume),
		muted = if typeof(mutedRaw) == "boolean" then mutedRaw else fallback.muted,
		categoryVolumes = AudioServiceUtils.sanitizeCategoryVolumes(categoryVolumesRaw, fallback.categoryVolumes),
	}
end

function AudioServiceUtils.withMasterVolume(state: AudioServiceState, masterVolumeRaw: any): AudioServiceState
	return {
		masterVolume = AudioServiceUtils.sanitizeVolume(masterVolumeRaw, state.masterVolume),
		muted = state.muted,
		categoryVolumes = AudioServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
	}
end

function AudioServiceUtils.withMuted(state: AudioServiceState, mutedRaw: any): AudioServiceState
	return {
		masterVolume = state.masterVolume,
		muted = if typeof(mutedRaw) == "boolean" then mutedRaw else state.muted,
		categoryVolumes = AudioServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
	}
end

function AudioServiceUtils.withCategoryVolume(
	state: AudioServiceState,
	categoryRaw: any,
	volumeRaw: any
): AudioServiceState
	local category = AudioServiceUtils.normalizeCategoryOrNil(categoryRaw)
	if not category then
		return {
			masterVolume = state.masterVolume,
			muted = state.muted,
			categoryVolumes = AudioServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
		}
	end

	local nextCategoryVolumes = AudioServiceUtils.cloneCategoryVolumes(state.categoryVolumes)
	nextCategoryVolumes[category] = AudioServiceUtils.sanitizeVolume(volumeRaw, nextCategoryVolumes[category])

	return {
		masterVolume = state.masterVolume,
		muted = state.muted,
		categoryVolumes = nextCategoryVolumes,
	}
end

function AudioServiceUtils.sanitizePlaybackOptions(optionsRaw: any, fallbackCategory: SoundCategory?): PlaybackOptions
	local source = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local category: SoundCategory =
		AudioServiceUtils.sanitizeCategory((source :: any).category, fallbackCategory or DEFAULT_CATEGORY)

	local channelRaw = (source :: any).channel
	local channel = if typeof(channelRaw) == "string" and channelRaw ~= "" then channelRaw else nil

	local options: PlaybackOptions = {
		category = category,
		channel = channel,
		looped = if typeof((source :: any).looped) == "boolean" then (source :: any).looped else nil,
		volume = if typeof((source :: any).volume) == "number"
			then clampNumber((source :: any).volume, 0, 10, 1)
			else nil,
		playbackSpeed = if typeof((source :: any).playbackSpeed) == "number"
			then clampNumber((source :: any).playbackSpeed, 0.05, 4, 1)
			else nil,
		timePosition = if typeof((source :: any).timePosition) == "number"
			then math.max(0, clampNumber((source :: any).timePosition, 0, 60 * 60, 0))
			else nil,
		fadeInTime = if typeof((source :: any).fadeInTime) == "number"
			then clampNumber((source :: any).fadeInTime, 0, 10, 0)
			else nil,
		fadeOutTime = if typeof((source :: any).fadeOutTime) == "number"
			then clampNumber((source :: any).fadeOutTime, 0, 10, 0.12)
			else nil,
		rollOffMaxDistance = if typeof((source :: any).rollOffMaxDistance) == "number"
			then clampNumber((source :: any).rollOffMaxDistance, 8, 512, 64)
			else nil,
		emitterSize = if typeof((source :: any).emitterSize) == "number"
			then clampNumber((source :: any).emitterSize, 0, 64, 4)
			else nil,
		autoDestroy = if typeof((source :: any).autoDestroy) == "boolean" then (source :: any).autoDestroy else nil,
		replaceChannel = if typeof((source :: any).replaceChannel) == "boolean"
			then (source :: any).replaceChannel
			else nil,
		parent = if typeof((source :: any).parent) == "Instance" then (source :: any).parent else nil,
	}

	return options
end

function AudioServiceUtils.resolvePlaybackRequest(
	soundSourceRaw: any,
	optionsRaw: any,
	fallbackCategory: SoundCategory?
): (string?, PlaybackOptions)
	local soundAssetId = AudioServiceUtils.resolveSoundAssetId(soundSourceRaw)
	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, fallbackCategory)
	if typeof(soundSourceRaw) ~= "table" then
		return soundAssetId, options
	end

	local source = soundSourceRaw :: { [string]: any }
	local providedOptions = if typeof(optionsRaw) == "table" then optionsRaw :: { [string]: any } else nil
	local sourceOptions = AudioServiceUtils.sanitizePlaybackOptions(soundSourceRaw, fallbackCategory)

	if providedOptions == nil or providedOptions.category == nil then
		if source.category ~= nil then
			options.category = sourceOptions.category
		end
	end
	if options.channel == nil and source.channel ~= nil then
		options.channel = sourceOptions.channel
	end
	if options.looped == nil and source.looped ~= nil then
		options.looped = sourceOptions.looped
	end
	if options.volume == nil and source.volume ~= nil then
		options.volume = sourceOptions.volume
	end
	if options.playbackSpeed == nil and source.playbackSpeed ~= nil then
		options.playbackSpeed = sourceOptions.playbackSpeed
	end
	if options.timePosition == nil and source.timePosition ~= nil then
		options.timePosition = sourceOptions.timePosition
	end
	if options.fadeInTime == nil and source.fadeInTime ~= nil then
		options.fadeInTime = sourceOptions.fadeInTime
	end
	if options.fadeOutTime == nil and source.fadeOutTime ~= nil then
		options.fadeOutTime = sourceOptions.fadeOutTime
	end
	if options.rollOffMaxDistance == nil and source.rollOffMaxDistance ~= nil then
		options.rollOffMaxDistance = sourceOptions.rollOffMaxDistance
	end
	if options.emitterSize == nil and source.emitterSize ~= nil then
		options.emitterSize = sourceOptions.emitterSize
	end
	if options.autoDestroy == nil and source.autoDestroy ~= nil then
		options.autoDestroy = sourceOptions.autoDestroy
	end
	if options.replaceChannel == nil and source.replaceChannel ~= nil then
		options.replaceChannel = sourceOptions.replaceChannel
	end
	if options.parent == nil and source.parent ~= nil then
		options.parent = sourceOptions.parent
	end

	return soundAssetId, options
end

function AudioServiceUtils.serializePlaybackOptions(
	optionsRaw: any,
	fallbackCategory: SoundCategory?
): { [string]: any }
	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, fallbackCategory)
	local serialized: { [string]: any } = {
		category = options.category,
	}
	if options.channel ~= nil then
		serialized.channel = options.channel
	end
	if options.looped ~= nil then
		serialized.looped = options.looped
	end
	if options.volume ~= nil then
		serialized.volume = options.volume
	end
	if options.playbackSpeed ~= nil then
		serialized.playbackSpeed = options.playbackSpeed
	end
	if options.timePosition ~= nil then
		serialized.timePosition = options.timePosition
	end
	if options.fadeInTime ~= nil then
		serialized.fadeInTime = options.fadeInTime
	end
	if options.fadeOutTime ~= nil then
		serialized.fadeOutTime = options.fadeOutTime
	end
	if options.rollOffMaxDistance ~= nil then
		serialized.rollOffMaxDistance = options.rollOffMaxDistance
	end
	if options.emitterSize ~= nil then
		serialized.emitterSize = options.emitterSize
	end
	if options.autoDestroy ~= nil then
		serialized.autoDestroy = options.autoDestroy
	end
	if options.replaceChannel ~= nil then
		serialized.replaceChannel = options.replaceChannel
	end
	if options.parent ~= nil and options.parent.Parent ~= nil then
		serialized.parent = options.parent
	end

	return serialized
end

function AudioServiceUtils.ensureRuntimeFolder(audioEngineService: SoundService): Folder
	local existing = audioEngineService:FindFirstChild("SoundServiceRuntime")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "SoundServiceRuntime"
	folder.Parent = audioEngineService
	return folder
end

function AudioServiceUtils.ensureCategoryGroups(audioEngineService: SoundService): { [string]: SoundGroup }
	local groups: { [string]: SoundGroup } = {}

	for _, category in CATEGORY_ORDER do
		local groupName = "SoundService_" .. category
		local existing = audioEngineService:FindFirstChild(groupName)
		if existing and existing:IsA("SoundGroup") then
			groups[category] = existing
		else
			local group = Instance.new("SoundGroup")
			group.Name = groupName
			group.Volume = DEFAULT_CATEGORY_VOLUMES[category]
			group.Parent = audioEngineService
			groups[category] = group
		end
	end

	return groups
end

function AudioServiceUtils.applyStateToCategoryGroups(
	state: AudioServiceState,
	categoryGroups: { [string]: SoundGroup }
)
	local baseVolume = if state.muted then 0 else state.masterVolume
	for _, category in CATEGORY_ORDER do
		local group = categoryGroups[category]
		if not group then
			continue
		end

		local categoryVolume = state.categoryVolumes[category] or DEFAULT_CATEGORY_VOLUMES[category]
		group.Volume = math.clamp(baseVolume * categoryVolume, 0, 2)
	end
end

function AudioServiceUtils.createSoundInstance(
	soundAssetIdRaw: any,
	optionsRaw: any,
	defaultParent: Instance,
	soundGroup: SoundGroup?
): Sound?
	local soundId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundId == nil then
		return nil
	end

	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, DEFAULT_CATEGORY)
	local parent = if options.parent and options.parent.Parent ~= nil then options.parent else defaultParent

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Name = if options.channel
		then `Sound_{options.channel}`
		else "Sound"
	if options.looped ~= nil then
		sound.Looped = options.looped
	end
	if options.volume ~= nil then
		sound.Volume = options.volume
	end
	if options.playbackSpeed ~= nil then
		sound.PlaybackSpeed = options.playbackSpeed
	end
	if options.timePosition ~= nil then
		sound.TimePosition = options.timePosition
	end
	if options.rollOffMaxDistance ~= nil then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = options.rollOffMaxDistance
	end
	if options.emitterSize ~= nil then
		(sound :: any).EmitterSize = options.emitterSize
	end
	if soundGroup then
		sound.SoundGroup = soundGroup
	end
	sound.Parent = parent

	return sound
end

function AudioServiceUtils.fadeSoundVolume(sound: Sound, targetVolume: number, fadeTime: number): Tween?
	local duration = math.max(0, fadeTime)
	local target = math.max(0, targetVolume)
	if duration <= 0 then
		sound.Volume = target
		return nil
	end

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = target }
	)
	tween:Play()
	return tween
end

function AudioServiceUtils.stopAndDestroySound(sound: Sound, fadeTimeRaw: any)
	local fadeTime = clampNumber(fadeTimeRaw, 0, 10, 0)
	if fadeTime <= 0 then
		sound:Stop()
		sound:Destroy()
		return
	end

	local tween = AudioServiceUtils.fadeSoundVolume(sound, 0, fadeTime)
	if not tween then
		sound:Stop()
		sound:Destroy()
		return
	end

	local connection: RBXScriptConnection?
	connection = tween.Completed:Connect(function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end)
end

return AudioServiceUtils

