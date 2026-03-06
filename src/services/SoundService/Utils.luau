--!strict
local TweenService = game:GetService("TweenService")

local SoundServiceUtils = {}

export type SoundCategory = "Music" | "SFX" | "Ambience" | "UI" | "Voice"

export type SoundServiceState = {
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

local CATEGORY_ORDER: { SoundCategory } = { "Music", "SFX", "Ambience", "UI", "Voice" }
local CATEGORY_SET: { [string]: boolean } = {}
for _, category in CATEGORY_ORDER do
	CATEGORY_SET[category] = true
end

local DEFAULT_CATEGORY: SoundCategory = "SFX"
local DEFAULT_MASTER_VOLUME = 1
local DEFAULT_CATEGORY_VOLUMES: { [string]: number } = {
	Music = 0.75,
	SFX = 1,
	Ambience = 0.85,
	UI = 1,
	Voice = 1,
}

SoundServiceUtils.CATEGORY_ORDER = CATEGORY_ORDER
SoundServiceUtils.DEFAULT_CATEGORY = DEFAULT_CATEGORY
SoundServiceUtils.DEFAULT_MASTER_VOLUME = DEFAULT_MASTER_VOLUME
SoundServiceUtils.DEFAULT_CATEGORY_VOLUMES = DEFAULT_CATEGORY_VOLUMES

local function clampNumber(value: any, minimum: number, maximum: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end

	return math.clamp(value, minimum, maximum)
end

function SoundServiceUtils.normalizeSoundAssetId(rawId: any): string?
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

function SoundServiceUtils.resolveSoundAssetId(soundSourceRaw: any): string?
	if typeof(soundSourceRaw) == "Instance" then
		local instance = soundSourceRaw :: Instance
		if instance:IsA("Sound") then
			return SoundServiceUtils.normalizeSoundAssetId(instance.SoundId)
		end
		return nil
	end

	return SoundServiceUtils.normalizeSoundAssetId(soundSourceRaw)
end

function SoundServiceUtils.normalizeCategoryOrNil(value: any): SoundCategory?
	if typeof(value) ~= "string" then
		return nil
	end

	if value == "Music" or value == "SFX" or value == "Ambience" or value == "UI" or value == "Voice" then
		return value
	end

	return nil
end

function SoundServiceUtils.sanitizeCategory(value: any, fallback: SoundCategory?): SoundCategory
	local normalized = SoundServiceUtils.normalizeCategoryOrNil(value)
	if normalized then
		return normalized
	end
	return (fallback or DEFAULT_CATEGORY) :: SoundCategory
end

function SoundServiceUtils.sanitizeVolume(value: any, fallback: number?): number
	return clampNumber(value, 0, 2, fallback or 1)
end

function SoundServiceUtils.cloneCategoryVolumes(source: { [string]: number }): { [string]: number }
	local cloned = {}
	for key, value in source do
		cloned[key] = value
	end
	return cloned
end

function SoundServiceUtils.createDefaultCategoryVolumes(): { [string]: number }
	return SoundServiceUtils.cloneCategoryVolumes(DEFAULT_CATEGORY_VOLUMES)
end

function SoundServiceUtils.sanitizeCategoryVolumes(
	rawVolumes: any,
	fallbackVolumes: { [string]: number }?
): { [string]: number }
	local source = if typeof(rawVolumes) == "table" then rawVolumes else {}
	local base = if fallbackVolumes then fallbackVolumes else DEFAULT_CATEGORY_VOLUMES
	local result = {}

	for _, category in CATEGORY_ORDER do
		result[category] = SoundServiceUtils.sanitizeVolume((source :: any)[category], base[category])
	end

	return result
end

function SoundServiceUtils.createDefaultState(): SoundServiceState
	return {
		masterVolume = DEFAULT_MASTER_VOLUME,
		muted = false,
		categoryVolumes = SoundServiceUtils.createDefaultCategoryVolumes(),
	}
end

function SoundServiceUtils.createState(
	masterVolumeRaw: any,
	mutedRaw: any,
	categoryVolumesRaw: any,
	fallbackState: SoundServiceState?
): SoundServiceState
	local fallback = if fallbackState then fallbackState else SoundServiceUtils.createDefaultState()
	return {
		masterVolume = SoundServiceUtils.sanitizeVolume(masterVolumeRaw, fallback.masterVolume),
		muted = if typeof(mutedRaw) == "boolean" then mutedRaw else fallback.muted,
		categoryVolumes = SoundServiceUtils.sanitizeCategoryVolumes(categoryVolumesRaw, fallback.categoryVolumes),
	}
end

function SoundServiceUtils.withMasterVolume(state: SoundServiceState, masterVolumeRaw: any): SoundServiceState
	return {
		masterVolume = SoundServiceUtils.sanitizeVolume(masterVolumeRaw, state.masterVolume),
		muted = state.muted,
		categoryVolumes = SoundServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
	}
end

function SoundServiceUtils.withMuted(state: SoundServiceState, mutedRaw: any): SoundServiceState
	return {
		masterVolume = state.masterVolume,
		muted = if typeof(mutedRaw) == "boolean" then mutedRaw else state.muted,
		categoryVolumes = SoundServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
	}
end

function SoundServiceUtils.withCategoryVolume(
	state: SoundServiceState,
	categoryRaw: any,
	volumeRaw: any
): SoundServiceState
	local category = SoundServiceUtils.normalizeCategoryOrNil(categoryRaw)
	if not category then
		return {
			masterVolume = state.masterVolume,
			muted = state.muted,
			categoryVolumes = SoundServiceUtils.cloneCategoryVolumes(state.categoryVolumes),
		}
	end

	local nextCategoryVolumes = SoundServiceUtils.cloneCategoryVolumes(state.categoryVolumes)
	nextCategoryVolumes[category] = SoundServiceUtils.sanitizeVolume(volumeRaw, nextCategoryVolumes[category])

	return {
		masterVolume = state.masterVolume,
		muted = state.muted,
		categoryVolumes = nextCategoryVolumes,
	}
end

function SoundServiceUtils.sanitizePlaybackOptions(optionsRaw: any, fallbackCategory: SoundCategory?): PlaybackOptions
	local source = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local category: SoundCategory =
		SoundServiceUtils.sanitizeCategory((source :: any).category, fallbackCategory or DEFAULT_CATEGORY)

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

function SoundServiceUtils.serializePlaybackOptions(
	optionsRaw: any,
	fallbackCategory: SoundCategory?
): { [string]: any }
	local options = SoundServiceUtils.sanitizePlaybackOptions(optionsRaw, fallbackCategory)
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

function SoundServiceUtils.ensureRuntimeFolder(soundService: SoundService): Folder
	local existing = soundService:FindFirstChild("SoundServiceRuntime")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "SoundServiceRuntime"
	folder.Parent = soundService
	return folder
end

function SoundServiceUtils.ensureCategoryGroups(soundService: SoundService): { [string]: SoundGroup }
	local groups: { [string]: SoundGroup } = {}

	for _, category in CATEGORY_ORDER do
		local groupName = "SoundService_" .. category
		local existing = soundService:FindFirstChild(groupName)
		if existing and existing:IsA("SoundGroup") then
			groups[category] = existing
		else
			local group = Instance.new("SoundGroup")
			group.Name = groupName
			group.Volume = DEFAULT_CATEGORY_VOLUMES[category]
			group.Parent = soundService
			groups[category] = group
		end
	end

	return groups
end

function SoundServiceUtils.applyStateToCategoryGroups(
	state: SoundServiceState,
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

function SoundServiceUtils.createSoundInstance(
	soundAssetIdRaw: any,
	optionsRaw: any,
	defaultParent: Instance,
	soundGroup: SoundGroup?
): Sound?
	local soundId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundId == nil then
		return nil
	end

	local options = SoundServiceUtils.sanitizePlaybackOptions(optionsRaw, DEFAULT_CATEGORY)
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

function SoundServiceUtils.fadeSoundVolume(sound: Sound, targetVolume: number, fadeTime: number): Tween?
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

function SoundServiceUtils.stopAndDestroySound(sound: Sound, fadeTimeRaw: any)
	local fadeTime = clampNumber(fadeTimeRaw, 0, 10, 0)
	if fadeTime <= 0 then
		sound:Stop()
		sound:Destroy()
		return
	end

	local tween = SoundServiceUtils.fadeSoundVolume(sound, 0, fadeTime)
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

return SoundServiceUtils
