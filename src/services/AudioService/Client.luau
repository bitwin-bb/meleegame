--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local AudioRegistry = require(ReplicatedStorage.Shared.Modules.Items.Audio)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)
local WorldGenerationServiceClient =
	require(ReplicatedStorage.Shared.Services.WorldGenerationService.WorldGenerationServiceClient)

type SoundCategory = AudioServiceUtils.SoundCategory
type AudioServiceState = AudioServiceUtils.AudioServiceState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local AudioServiceClient = {}

local DEFAULT_CHARACTER_SOUND_NAMES: { [string]: boolean } = {
	Climbing = true,
	FreeFalling = true,
	GettingUp = true,
	Jumping = true,
	Landing = true,
	Running = true,
	Splash = true,
	Swimming = true,
}

local SOUNDTRACK_CHANNEL_NAME = "biomeSoundtrack"
local SOUNDTRACK_FADE_SECONDS = 1.1
local SOUNDTRACK_TRACK_GAP_SECONDS = 0
local SOUNDTRACK_BIOME_SAMPLE_INTERVAL = 0.35
local DEFAULT_SOUNDTRACK_BIOME = "Overworld"
local OVERWORLD_NIGHT_SOUNDTRACK_BIOME = "OverworldNight"
local CORRUPTION_SOUNDTRACK_BIOME = "Corruption"
local JUNGLE_SOUNDTRACK_BIOME = "Jungle"
local UNDERGROUND_SOUNDTRACK_BIOME = "Underground"
local CAVERN_SOUNDTRACK_BIOME = "Cavern"
local BIOME_TYPE_NORMAL = 1
local BIOME_TYPE_CORRUPTION = 2
local BIOME_ID_FOREST = 1
local BIOME_ID_JUNGLE = 4
local DEPTH_LAYER_UNDERGROUND = 2
local DEPTH_LAYER_CAVERN = 3
local DEPTH_LAYER_DEEP = 4
local NIGHT_CLOCK_START = 19
local NIGHT_CLOCK_END = 5.5
local MUSIC_AUDIO = (AudioRegistry :: any).Music or {}

local SOUNDTRACK_TRACK_KEYS_BY_BIOME: { [string]: { string } } = {
	Overworld = { "OverworldDay" },
	OverworldNight = { "OverworldNight" },
	Corruption = { "Corruption" },
	Jungle = { "Jungle" },
	Underground = { "Underground" },
	Cavern = { "Cavern" },
}

local SOUNDTRACK_BIOME_BY_BIOME_TYPE: { [number]: string } = {
	[BIOME_TYPE_NORMAL] = DEFAULT_SOUNDTRACK_BIOME,
	[BIOME_TYPE_CORRUPTION] = CORRUPTION_SOUNDTRACK_BIOME,
}

local SOUNDTRACK_LOOPED_BY_BIOME: { [string]: boolean } = {
	Overworld = false,
	OverworldNight = true,
	Corruption = true,
	Jungle = true,
	Underground = true,
	Cavern = true,
}

local function isNightTime(clockTime: number): boolean
	return clockTime >= NIGHT_CLOCK_START or clockTime <= NIGHT_CLOCK_END
end

local function resolveCharacterRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end
	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end
	return character:FindFirstChildWhichIsA("BasePart")
end

local function shuffleStringsInPlace(randomObject: Random, values: { string })
	for index = #values, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		values[index], values[swapIndex] = values[swapIndex], values[index]
	end
end

local function disableSoundScriptIfNeeded(scriptInstance: Instance)
	if scriptInstance.Name ~= "RbxCharacterSounds" then
		return
	end
	if scriptInstance:IsA("LocalScript") or scriptInstance:IsA("Script") then
		(scriptInstance :: any).Enabled = false
	end
end

local function removeDefaultCharacterSoundIfNeeded(instance: Instance)
	if not instance:IsA("Sound") then
		return
	end
	if DEFAULT_CHARACTER_SOUND_NAMES[instance.Name] ~= true then
		return
	end
	instance:Destroy()
end

local function disableDefaultCharacterSoundSystem(player: Player, character: Model?)
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if playerScripts then
		local existingScript = playerScripts:FindFirstChild("RbxCharacterSounds")
		if existingScript then
			disableSoundScriptIfNeeded(existingScript)
		end
	end

	if character then
		for _, descendant in character:GetDescendants() do
			disableSoundScriptIfNeeded(descendant)
			removeDefaultCharacterSoundIfNeeded(descendant)
		end
	end
end

function AudioServiceClient.refreshSoundtrackAssetIds(self: AudioServiceClient)
	local assetIdsByBiome: { [string]: { string } } = {}

	for soundtrackBiome, trackKeys in SOUNDTRACK_TRACK_KEYS_BY_BIOME do
		local trackAssetIds: { string } = {}
		for _, trackKey in trackKeys do
			local soundAssetId = AudioServiceUtils.normalizeSoundAssetId((MUSIC_AUDIO :: any)[trackKey])
			if soundAssetId ~= nil then
				table.insert(trackAssetIds, soundAssetId)
			end
		end
		assetIdsByBiome[soundtrackBiome] = trackAssetIds
	end

	self.soundtrackAssetIdsByBiome = assetIdsByBiome
	self.soundtrackShuffleBagByBiome = {}
end

function AudioServiceClient.resolveBiomeTypeAtWorldPosition(
	self: AudioServiceClient,
	worldPosition: Vector3
): number
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return BIOME_TYPE_NORMAL
	end

	local worldState = WorldGenerationServiceClient:getState()
	if worldState.ready ~= true then
		return BIOME_TYPE_NORMAL
	end

	local ok, biomeTypeOrError = pcall(function()
		return WorldGenerationServiceClient:getBiomeTypeAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeTypeOrError) ~= "number" then
		return BIOME_TYPE_NORMAL
	end

	local biomeType = math.floor(biomeTypeOrError)
	if biomeType == BIOME_TYPE_CORRUPTION then
		return BIOME_TYPE_CORRUPTION
	end
	return BIOME_TYPE_NORMAL
end

function AudioServiceClient.resolveBiomeIdAtWorldPosition(
	self: AudioServiceClient,
	worldPosition: Vector3
): number
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return BIOME_ID_FOREST
	end

	local worldState = WorldGenerationServiceClient:getState()
	if worldState.ready ~= true then
		return BIOME_ID_FOREST
	end

	local ok, biomeIdOrError = pcall(function()
		return WorldGenerationServiceClient:getBiomeIdAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeIdOrError) ~= "number" then
		return BIOME_ID_FOREST
	end

	local biomeId = math.floor(biomeIdOrError)
	if biomeId == BIOME_ID_JUNGLE then
		return BIOME_ID_JUNGLE
	end
	return BIOME_ID_FOREST
end

function AudioServiceClient.resolveDepthLayerAtWorldPosition(
	self: AudioServiceClient,
	worldPosition: Vector3
): number?
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return nil
	end

	local worldState = WorldGenerationServiceClient:getState()
	if worldState.ready ~= true then
		return nil
	end

	local ok, depthLayerOrError = pcall(function()
		return (WorldGenerationServiceClient :: any):getDepthLayerAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(depthLayerOrError) ~= "number" then
		return nil
	end
	return math.floor(depthLayerOrError)
end

function AudioServiceClient.resolveSoundtrackBiomeForLocalPlayer(self: AudioServiceClient): string?
	local character = self.localPlayer.Character
	if character == nil then
		return nil
	end

	local rootPart = resolveCharacterRootPart(character)
	if rootPart == nil then
		return nil
	end
	local worldPosition = rootPart.Position

	local depthLayer = self:resolveDepthLayerAtWorldPosition(worldPosition)
	if depthLayer == DEPTH_LAYER_CAVERN or depthLayer == DEPTH_LAYER_DEEP then
		return CAVERN_SOUNDTRACK_BIOME
	end
	if depthLayer == DEPTH_LAYER_UNDERGROUND then
		return UNDERGROUND_SOUNDTRACK_BIOME
	end

	local biomeType = self:resolveBiomeTypeAtWorldPosition(worldPosition)
	if biomeType == BIOME_TYPE_CORRUPTION then
		return CORRUPTION_SOUNDTRACK_BIOME
	end

	local biomeId = self:resolveBiomeIdAtWorldPosition(worldPosition)
	if biomeId == BIOME_ID_JUNGLE then
		return JUNGLE_SOUNDTRACK_BIOME
	end

	local soundtrackBiome = SOUNDTRACK_BIOME_BY_BIOME_TYPE[BIOME_TYPE_NORMAL]
	if soundtrackBiome ~= nil then
		if soundtrackBiome == DEFAULT_SOUNDTRACK_BIOME and isNightTime(Lighting.ClockTime) then
			return OVERWORLD_NIGHT_SOUNDTRACK_BIOME
		end
		return soundtrackBiome
	end
	return DEFAULT_SOUNDTRACK_BIOME
end

function AudioServiceClient.getNextTrackForSoundtrackBiome(
	self: AudioServiceClient,
	soundtrackBiome: string
): string?
	local assetIds = self.soundtrackAssetIdsByBiome[soundtrackBiome]
	if assetIds == nil or #assetIds <= 0 then
		return nil
	end

	local shuffleBag = self.soundtrackShuffleBagByBiome[soundtrackBiome]
	if shuffleBag == nil or #shuffleBag <= 0 then
		shuffleBag = table.clone(assetIds)
		shuffleStringsInPlace(self.random, shuffleBag)
		self.soundtrackShuffleBagByBiome[soundtrackBiome] = shuffleBag
	end

	if #shuffleBag <= 0 then
		return nil
	end
	return table.remove(shuffleBag, 1)
end

function AudioServiceClient.clearActiveSoundtrackConnections(self: AudioServiceClient)
	if self.soundtrackTrackEndedConnection ~= nil then
		self.soundtrackTrackEndedConnection:Disconnect()
		self.soundtrackTrackEndedConnection = nil
	end
	if self.soundtrackTrackDestroyingConnection ~= nil then
		self.soundtrackTrackDestroyingConnection:Disconnect()
		self.soundtrackTrackDestroyingConnection = nil
	end
end

function AudioServiceClient.playNextSoundtrackTrack(self: AudioServiceClient, playbackToken: number)
	if playbackToken ~= self.soundtrackPlaybackToken then
		return
	end

	local soundtrackBiome = self.soundtrackCurrentBiome
	if soundtrackBiome == nil or soundtrackBiome == "" then
		return
	end

	local nextTrackAssetId = self:getNextTrackForSoundtrackBiome(soundtrackBiome)
	if nextTrackAssetId == nil then
		self:stopChannel(SOUNDTRACK_CHANNEL_NAME, SOUNDTRACK_FADE_SECONDS)
		self.soundtrackActiveTrack = nil
		return
	end
	local shouldLoop = SOUNDTRACK_LOOPED_BY_BIOME[soundtrackBiome] == true

	local playingSound = self:playSound(nextTrackAssetId, {
		category = "Music",
		channel = SOUNDTRACK_CHANNEL_NAME,
		looped = shouldLoop,
		autoDestroy = not shouldLoop,
		fadeInTime = SOUNDTRACK_FADE_SECONDS,
		fadeOutTime = SOUNDTRACK_FADE_SECONDS,
	}, "Music")
	if playingSound == nil then
		task.delay(SOUNDTRACK_TRACK_GAP_SECONDS, function()
			self:playNextSoundtrackTrack(playbackToken)
		end)
		return
	end

	self.soundtrackActiveTrack = playingSound
	self:clearActiveSoundtrackConnections()
	if shouldLoop then
		return
	end

	local handled = false
	local function queueNextTrack()
		if handled then
			return
		end
		handled = true
		self:clearActiveSoundtrackConnections()
		if self.soundtrackActiveTrack == playingSound then
			self.soundtrackActiveTrack = nil
		end
		if playbackToken ~= self.soundtrackPlaybackToken then
			return
		end
		task.delay(SOUNDTRACK_TRACK_GAP_SECONDS, function()
			self:playNextSoundtrackTrack(playbackToken)
		end)
	end

	self.soundtrackTrackEndedConnection = playingSound.Ended:Connect(function()
		queueNextTrack()
	end)
	self.soundtrackTrackDestroyingConnection = playingSound.Destroying:Connect(function()
		queueNextTrack()
	end)
end

function AudioServiceClient.setSoundtrackBiome(self: AudioServiceClient, soundtrackBiomeRaw: any)
	local soundtrackBiome = if typeof(soundtrackBiomeRaw) == "string" and soundtrackBiomeRaw ~= ""
		then soundtrackBiomeRaw
		else DEFAULT_SOUNDTRACK_BIOME

	local tracks = self.soundtrackAssetIdsByBiome[soundtrackBiome]
	if tracks == nil or #tracks <= 0 then
		soundtrackBiome = DEFAULT_SOUNDTRACK_BIOME
	end

	local activeTrack = self.soundtrackActiveTrack
	local isTrackAlive = activeTrack ~= nil and activeTrack.Parent ~= nil
	if self.soundtrackCurrentBiome == soundtrackBiome and isTrackAlive then
		return
	end

	self.soundtrackCurrentBiome = soundtrackBiome
	self.soundtrackPlaybackToken += 1
	self:playNextSoundtrackTrack(self.soundtrackPlaybackToken)
end

function AudioServiceClient.updateBiomeSoundtrack(self: AudioServiceClient, deltaTime: number)
	self.soundtrackSampleAccumulator += deltaTime
	if self.soundtrackSampleAccumulator < SOUNDTRACK_BIOME_SAMPLE_INTERVAL then
		return
	end
	self.soundtrackSampleAccumulator = 0

	local soundtrackBiome = self:resolveSoundtrackBiomeForLocalPlayer()
	if soundtrackBiome == nil then
		return
	end
	self:setSoundtrackBiome(soundtrackBiome)
end

function AudioServiceClient.init(self: AudioServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("AudioService", self)
	self.janitor = Janitor.new()
	self.characterSoundJanitor = Janitor.new()
	self.state = AudioServiceUtils.createDefaultState()
	self.runtimeFolder = AudioServiceUtils.ensureRuntimeFolder(RobloxSoundService)
	self.categoryGroups = AudioServiceUtils.ensureCategoryGroups(RobloxSoundService)
	self.channelSounds = {}
	self.random = Random.new()
	self.soundtrackAssetIdsByBiome = {}
	self.soundtrackShuffleBagByBiome = {}
	self.soundtrackCurrentBiome = nil
	self.soundtrackActiveTrack = nil
	self.soundtrackPlaybackToken = 0
	self.soundtrackTrackEndedConnection = nil
	self.soundtrackTrackDestroyingConnection = nil
	self.soundtrackSampleAccumulator = SOUNDTRACK_BIOME_SAMPLE_INTERVAL

	AudioServiceUtils.applyStateToCategoryGroups(self.state, self.categoryGroups)
	disableDefaultCharacterSoundSystem(self.localPlayer, self.localPlayer.Character)
	self:refreshSoundtrackAssetIds()

	self.janitor:GiveChore(self.characterSoundJanitor)
	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:onCharacterAdded(character)
		self.soundtrackSampleAccumulator = SOUNDTRACK_BIOME_SAMPLE_INTERVAL
	end))
	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:updateBiomeSoundtrack(deltaTime)
	end))

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self:clearActiveSoundtrackConnections()
		self:stopAll(0)
	end)

	if self.localPlayer.Character then
		self:onCharacterAdded(self.localPlayer.Character)
	end

	self.networker:fire("requestSync")
end

function AudioServiceClient.onCharacterAdded(self: AudioServiceClient, character: Model)
	self.characterSoundJanitor:Clean()
	disableDefaultCharacterSoundSystem(self.localPlayer, character)

	local playerScripts = self.localPlayer:FindFirstChild("PlayerScripts")
	if playerScripts then
		self.characterSoundJanitor:GiveChore(playerScripts.ChildAdded:Connect(function(child: Instance)
			disableSoundScriptIfNeeded(child)
		end))
	end

	self.characterSoundJanitor:GiveChore(character.DescendantAdded:Connect(function(instance: Instance)
		disableSoundScriptIfNeeded(instance)
		removeDefaultCharacterSoundIfNeeded(instance)
	end))
end

function AudioServiceClient.applyState(
	self: AudioServiceClient,
	masterVolumeRaw: any,
	mutedRaw: any,
	categoryVolumesRaw: any
)
	self.state = AudioServiceUtils.createState(masterVolumeRaw, mutedRaw, categoryVolumesRaw, self.state)
	AudioServiceUtils.applyStateToCategoryGroups(self.state, self.categoryGroups)
end

function AudioServiceClient.setMasterVolume(self: AudioServiceClient, masterVolumeRaw: any, replicateToServer: boolean?)
	self.state = AudioServiceUtils.withMasterVolume(self.state, masterVolumeRaw)
	AudioServiceUtils.applyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		self.networker:fire("setMasterVolume", self.state.masterVolume)
	end
end

function AudioServiceClient.setMuted(self: AudioServiceClient, mutedRaw: any, replicateToServer: boolean?)
	self.state = AudioServiceUtils.withMuted(self.state, mutedRaw)
	AudioServiceUtils.applyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		self.networker:fire("setMuted", self.state.muted)
	end
end

function AudioServiceClient.setCategoryVolume(
	self: AudioServiceClient,
	categoryRaw: any,
	volumeRaw: any,
	replicateToServer: boolean?
)
	self.state = AudioServiceUtils.withCategoryVolume(self.state, categoryRaw, volumeRaw)
	AudioServiceUtils.applyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		local category = AudioServiceUtils.normalizeCategoryOrNil(categoryRaw)
		if category then
			self.networker:fire("setCategoryVolume", category, volumeRaw)
		end
	end
end

function AudioServiceClient.toggleMute(self: AudioServiceClient, replicateToServer: boolean?)
	self:setMuted(not self.state.muted, replicateToServer)
end

function AudioServiceClient.requestSync(self: AudioServiceClient)
	self.networker:fire("requestSync")
end

function AudioServiceClient.playSound(
	self: AudioServiceClient,
	soundAssetIdRaw: any,
	optionsRaw: any,
	fallbackCategory: SoundCategory?
): Sound?
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return nil
	end

	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, fallbackCategory)
	local categoryGroup = self.categoryGroups[options.category]

	local shouldReplaceChannel = if options.replaceChannel == nil then true else options.replaceChannel
	if options.channel and shouldReplaceChannel then
		self:stopChannel(options.channel, options.fadeOutTime)
	end

	local sound = AudioServiceUtils.createSoundInstance(soundAssetId, options, self.runtimeFolder, categoryGroup)
	if not sound then
		return nil
	end

	local channelName = options.channel
	if channelName then
		self.channelSounds[channelName] = sound

		local channelConnection: RBXScriptConnection?
		channelConnection = sound.Destroying:Connect(function()
			if self.channelSounds[channelName] == sound then
				self.channelSounds[channelName] = nil
			end
			if channelConnection then
				channelConnection:Disconnect()
				channelConnection = nil
			end
		end)
	end

	local fadeInTime = options.fadeInTime
	if fadeInTime and fadeInTime > 0 then
		local targetVolume: number = if options.volume ~= nil then options.volume else sound.Volume
		sound.Volume = 0
		AudioServiceUtils.fadeSoundVolume(sound, targetVolume, fadeInTime)
	end

	local shouldAutoDestroy = if options.autoDestroy == nil then not sound.Looped else options.autoDestroy
	if shouldAutoDestroy and not sound.Looped then
		local endedConnection: RBXScriptConnection?
		endedConnection = sound.Ended:Connect(function()
			if endedConnection then
				endedConnection:Disconnect()
				endedConnection = nil
			end
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end

	sound:Play()
	return sound
end

function AudioServiceClient.playSfx(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	return self:playSound(soundAssetIdRaw, optionsRaw, "SFX")
end

function AudioServiceClient.playUi(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	return self:playSound(soundAssetIdRaw, optionsRaw, "UI")
end

function AudioServiceClient.playAmbience(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, "Ambience")
	if options.channel == nil then
		options.channel = "ambience"
	end
	options.looped = true
	return self:playSound(soundAssetIdRaw, options, "Ambience")
end

function AudioServiceClient.playMusic(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	local options = AudioServiceUtils.sanitizePlaybackOptions(optionsRaw, "Music")
	if options.channel == nil then
		options.channel = "music"
	end
	options.looped = true
	if options.fadeOutTime == nil or options.fadeOutTime <= 0 then
		options.fadeOutTime = 0.2
	end
	if options.fadeInTime == nil or options.fadeInTime <= 0 then
		options.fadeInTime = 0.2
	end
	return self:playSound(soundAssetIdRaw, options, "Music")
end

function AudioServiceClient.stopChannel(self: AudioServiceClient, channelNameRaw: any, fadeTimeRaw: any)
	if typeof(channelNameRaw) ~= "string" or channelNameRaw == "" then
		return
	end

	local sound = self.channelSounds[channelNameRaw]
	if not sound then
		return
	end

	self.channelSounds[channelNameRaw] = nil
	AudioServiceUtils.stopAndDestroySound(sound, fadeTimeRaw)
end

function AudioServiceClient.stopAll(self: AudioServiceClient, fadeTimeRaw: any)
	local channels: { string } = {}
	for channelName in self.channelSounds do
		table.insert(channels, channelName)
	end

	for _, channelName in channels do
		self:stopChannel(channelName, fadeTimeRaw)
	end
end

function AudioServiceClient.destroy(self: AudioServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

type AudioServiceClient = typeof(AudioServiceClient) & {
	refreshSoundtrackAssetIds: (self: AudioServiceClient) -> (),
	resolveBiomeTypeAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number,
	resolveBiomeIdAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number,
	resolveDepthLayerAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number?,
	resolveSoundtrackBiomeForLocalPlayer: (self: AudioServiceClient) -> string?,
	getNextTrackForSoundtrackBiome: (self: AudioServiceClient, soundtrackBiome: string) -> string?,
	clearActiveSoundtrackConnections: (self: AudioServiceClient) -> (),
	playNextSoundtrackTrack: (self: AudioServiceClient, playbackToken: number) -> (),
	setSoundtrackBiome: (self: AudioServiceClient, soundtrackBiomeRaw: any) -> (),
	updateBiomeSoundtrack: (self: AudioServiceClient, deltaTime: number) -> (),
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	characterSoundJanitor: JanitorClass,
	state: AudioServiceState,
	runtimeFolder: Folder,
	categoryGroups: { [string]: SoundGroup },
	channelSounds: { [string]: Sound },
	random: Random,
	soundtrackAssetIdsByBiome: { [string]: { string } },
	soundtrackShuffleBagByBiome: { [string]: { string } },
	soundtrackCurrentBiome: string?,
	soundtrackActiveTrack: Sound?,
	soundtrackPlaybackToken: number,
	soundtrackTrackEndedConnection: RBXScriptConnection?,
	soundtrackTrackDestroyingConnection: RBXScriptConnection?,
	soundtrackSampleAccumulator: number,
}

return AudioServiceClient :: AudioServiceClient

