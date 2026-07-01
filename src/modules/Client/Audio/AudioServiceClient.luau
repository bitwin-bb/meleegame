local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RobloxSoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local AudioRegistry = require("Audio")
local AudioServiceUtils = require("AudioServiceUtils")
local BossServiceClient = require("BossServiceClient")
local BinderSupportClient = require("BinderSupportClient")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local AudioServicePackets = require("NetPacketsClient").AudioService

local function sendPacket(methodName: string, ...: any)
	local packet = AudioServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AudioService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = AudioServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AudioService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "playMusic")
	bindPacket(self, "playSfx")
	bindPacket(self, "requestSync")
	bindPacket(self, "setCategoryVolume")
	bindPacket(self, "setMasterVolume")
	bindPacket(self, "setMuted")
	bindPacket(self, "stopAll")
	bindPacket(self, "stopChannel")
end

local NevermoreSupport = require("NevermoreSupport")
local SpaceShared = require("SpaceShared")
local Table = require("Table")
local WeatherServiceClient = require("WeatherServiceClient")
local WeatherServiceUtils = require("WeatherServiceUtils")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

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
local MISSING_ASSET_ERROR = "no asset found!"
local OVERWORLD_NIGHT_SOUNDTRACK_BIOME = "OverworldNight"
local CORRUPTION_SOUNDTRACK_BIOME = "Corruption"
local SNOW_SOUNDTRACK_BIOME = "Snow"
local JUNGLE_SOUNDTRACK_BIOME = "Jungle"
local UNDERGROUND_SOUNDTRACK_BIOME = "Underground"
local UNDERGROUND_SNOW_SOUNDTRACK_BIOME = "UndergroundSnow"
local UNDERGROUND_CORRUPTION_SOUNDTRACK_BIOME = "UndergroundCorruption"
local CAVERN_SOUNDTRACK_BIOME = "Cavern"
local SPACE_SOUNDTRACK_BIOME = SpaceShared.SPACE_SOUNDTRACK_BIOME
local RAIN_SOUNDTRACK_BIOME = "Rain"
local EYE_OF_CTHULHU_SOUNDTRACK_BIOME = "EyeOfCthulhu"
local QUEEN_BEE_SOUNDTRACK_BIOME = "QueenBee"
local BIOME_TYPE_NORMAL = 1
local BIOME_TYPE_CORRUPTION = 2
local BIOME_ID_FOREST = 1
local BIOME_ID_SNOW = 3
local BIOME_ID_JUNGLE = 4
local DEPTH_LAYER_UNDERGROUND = 2
local DEPTH_LAYER_CAVERN = 3
local DEPTH_LAYER_DEEP = 4
local NIGHT_CLOCK_START = 19
local NIGHT_CLOCK_END = 5.5
local MUSIC_AUDIO = (AudioRegistry :: any).Music or ({} :: any)

local SOUNDTRACK_TRACK_KEYS_BY_BIOME: { [string]: { string } } = {
	Overworld = { "OverworldDay" },
	OverworldNight = { "OverworldNight" },
	Corruption = { "Corruption" },
	Snow = { "Snow" },
	Jungle = { "Jungle" },
	Underground = { "Underground" },
	UndergroundSnow = { "UndergroundSnow" },
	UndergroundCorruption = { "UndergroundCorruption" },
	Cavern = { "Cavern" },
	Space = { "Space", "space" },
	Rain = { "Rain" },
	EyeOfCthulhu = { "EyeOfCthulhuRedux" },
	QueenBee = { "QueenBee" },
}

local BOSS_SOUNDTRACK_BIOME_BY_ID: { [string]: string } = {
	EyeOfCthulhu = EYE_OF_CTHULHU_SOUNDTRACK_BIOME,
	QueenBee = QUEEN_BEE_SOUNDTRACK_BIOME,
}

local SOUNDTRACK_BIOME_BY_BIOME_TYPE: { [number]: string } = {
	[BIOME_TYPE_NORMAL] = DEFAULT_SOUNDTRACK_BIOME,
	[BIOME_TYPE_CORRUPTION] = CORRUPTION_SOUNDTRACK_BIOME,
}

local SOUNDTRACK_LOOPED_BY_BIOME: { [string]: boolean } = {
	Overworld = false,
	OverworldNight = true,
	Corruption = true,
	Snow = true,
	Jungle = true,
	Underground = true,
	UndergroundSnow = true,
	UndergroundCorruption = true,
	Cavern = true,
	Space = true,
	Rain = true,
	EyeOfCthulhu = true,
	QueenBee = true,
}

local function isRainActive(): boolean
	local weatherState = (WeatherServiceClient :: any).state
	if typeof(weatherState) ~= "table" then
		return false
	end

	local weatherType = WeatherServiceUtils.CoerceWeatherType((weatherState :: any).weatherType, "Clear")
	if weatherType ~= WeatherServiceUtils.WEATHER_TYPE_CLEAR then
		return true
	end

	local rainIntensity = WeatherServiceUtils.CoerceNumber((weatherState :: any).rainIntensity, 0, 0, 1)
	return rainIntensity > 0.01
end

local function isNightTime(clockTime: number): boolean
	return clockTime >= NIGHT_CLOCK_START or clockTime <= NIGHT_CLOCK_END
end

local function GetCharacterRootPart(character: Model?): BasePart?
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

function AudioServiceClient.RefreshSoundtrackAssetIds(self: AudioServiceClient)
	local assetIdsByBiome: { [string]: { string } } = {}

	for soundtrackBiome, trackKeys in SOUNDTRACK_TRACK_KEYS_BY_BIOME do
		local trackAssetIds: { string } = {}
		for _, trackKey in trackKeys do
			local soundAssetId = AudioServiceUtils.NormalizeSoundAssetId((MUSIC_AUDIO :: any)[trackKey])
			if soundAssetId ~= nil then
				table.insert(trackAssetIds, soundAssetId)
			end
		end
		assetIdsByBiome[soundtrackBiome] = trackAssetIds
	end

	self.soundtrackAssetIdsByBiome = assetIdsByBiome
	self.soundtrackShuffleBagByBiome = {}
end

function AudioServiceClient.GetBiomeTypeAtWorldPosition(_self: AudioServiceClient, worldPosition: Vector3): number
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return BIOME_TYPE_NORMAL
	end

	local worldState = WorldGenerationServiceClient:GetState()
	if worldState.ready ~= true then
		return BIOME_TYPE_NORMAL
	end

	local ok, biomeTypeOrError = pcall(function()
		return WorldGenerationServiceClient:GetBiomeTypeAtWorldPosition(worldPosition)
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

function AudioServiceClient.GetBiomeIdAtWorldPosition(_self: AudioServiceClient, worldPosition: Vector3): number
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return BIOME_ID_FOREST
	end

	local worldState = WorldGenerationServiceClient:GetState()
	if worldState.ready ~= true then
		return BIOME_ID_FOREST
	end

	local ok, biomeIdOrError = pcall(function()
		return WorldGenerationServiceClient:GetBiomeIdAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeIdOrError) ~= "number" then
		return BIOME_ID_FOREST
	end

	local biomeId = math.floor(biomeIdOrError)
	if biomeId == BIOME_ID_SNOW then
		return BIOME_ID_SNOW
	end
	if biomeId == BIOME_ID_JUNGLE then
		return BIOME_ID_JUNGLE
	end
	return BIOME_ID_FOREST
end

function AudioServiceClient.GetSurfaceBiomeIdAtWorldPosition(
	self: AudioServiceClient,
	worldPosition: Vector3
): number
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return BIOME_ID_FOREST
	end

	local worldState = WorldGenerationServiceClient:GetState()
	if worldState.ready ~= true then
		return BIOME_ID_FOREST
	end

	local ok, biomeIdOrError = pcall(function()
		return (WorldGenerationServiceClient :: any):GetSurfaceBiomeIdAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(biomeIdOrError) ~= "number" then
		return self:GetBiomeIdAtWorldPosition(worldPosition)
	end

	local biomeId = math.floor(biomeIdOrError)
	if biomeId == BIOME_ID_SNOW then
		return BIOME_ID_SNOW
	end
	if biomeId == BIOME_ID_JUNGLE then
		return BIOME_ID_JUNGLE
	end
	return BIOME_ID_FOREST
end

function AudioServiceClient.GetDepthLayerAtWorldPosition(_self: AudioServiceClient, worldPosition: Vector3): number?
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return nil
	end

	local worldState = WorldGenerationServiceClient:GetState()
	if worldState.ready ~= true then
		return nil
	end

	local ok, depthLayerOrError = pcall(function()
		return (WorldGenerationServiceClient :: any):GetDepthLayerAtWorldPosition(worldPosition)
	end)
	if not ok or typeof(depthLayerOrError) ~= "number" then
		return nil
	end
	return math.floor(depthLayerOrError)
end

function AudioServiceClient.HasSoundtrackTracks(self: AudioServiceClient, soundtrackBiome: string): boolean
	local tracks = self.soundtrackAssetIdsByBiome[soundtrackBiome]
	return tracks ~= nil and #tracks > 0
end

function AudioServiceClient.AttachBossStateListenerIfNeeded(self: AudioServiceClient)
	if self.bossStateChangedConnection ~= nil then
		return
	end

	local bossStateChanged = (BossServiceClient :: any).stateChanged
	if typeof(bossStateChanged) ~= "table" or typeof((bossStateChanged :: any).Connect) ~= "function" then
		return
	end

	local connection = bossStateChanged:Connect(function()
		self.soundtrackSampleAccumulator = SOUNDTRACK_BIOME_SAMPLE_INTERVAL
		self:UpdateBiomeSoundtrack(SOUNDTRACK_BIOME_SAMPLE_INTERVAL)
	end)
	self.bossStateChangedConnection = connection
	self.janitor:GiveChore(connection)

	self.soundtrackSampleAccumulator = SOUNDTRACK_BIOME_SAMPLE_INTERVAL
end

function AudioServiceClient.GetBossSoundtrackBiome(_self: AudioServiceClient): string?
	local bossState = (BossServiceClient :: any).state
	if typeof(bossState) ~= "table" then
		return nil
	end

	local orderedIds = (bossState :: any).orderedIds
	local byId = (bossState :: any).byId
	if typeof(orderedIds) ~= "table" or typeof(byId) ~= "table" then
		return nil
	end

	for _, runtimeId in orderedIds do
		local snapshot = byId[runtimeId]
		if typeof(snapshot) ~= "table" then
			continue
		end
		local bossSoundtrackBiome = BOSS_SOUNDTRACK_BIOME_BY_ID[(snapshot :: any).bossId]
		if bossSoundtrackBiome == nil or (snapshot :: any).isAlive ~= true then
			continue
		end

		local state = (snapshot :: any).state
		if state ~= "Dormant" and state ~= "Death" and state ~= "Despawn" then
			return bossSoundtrackBiome
		end
	end

	return nil
end

function AudioServiceClient.GetSoundtrackBiomeForLocalPlayer(self: AudioServiceClient): string?
	local bossSoundtrackBiome = self:GetBossSoundtrackBiome()
	if bossSoundtrackBiome ~= nil then
		return bossSoundtrackBiome
	end

	local character = self.localPlayer.Character
	if character == nil then
		return nil
	end

	local rootPart = GetCharacterRootPart(character)
	if rootPart == nil then
		return nil
	end
	local worldPosition = rootPart.Position
	if typeof((WorldGenerationServiceClient :: any).state) == "table" then
		local okWorldState, worldState = pcall(function()
			return WorldGenerationServiceClient:GetState()
		end)
		if
			okWorldState
			and SpaceShared.IsInSpaceAtWorldPosition(
				worldPosition,
				worldState,
				(WorldGenerationServiceClient :: any).worldOrigin
			)
			and self:HasSoundtrackTracks(SPACE_SOUNDTRACK_BIOME)
		then
			return SPACE_SOUNDTRACK_BIOME
		end
	end

	local biomeType = self:GetBiomeTypeAtWorldPosition(worldPosition)
	local biomeId = self:GetBiomeIdAtWorldPosition(worldPosition)
	local surfaceBiomeId = self:GetSurfaceBiomeIdAtWorldPosition(worldPosition)
	local depthLayer = self:GetDepthLayerAtWorldPosition(worldPosition)
	if depthLayer == DEPTH_LAYER_CAVERN or depthLayer == DEPTH_LAYER_DEEP then
		if biomeType == BIOME_TYPE_CORRUPTION then
			return UNDERGROUND_CORRUPTION_SOUNDTRACK_BIOME
		end
		if surfaceBiomeId == BIOME_ID_SNOW then
			return UNDERGROUND_SNOW_SOUNDTRACK_BIOME
		end
		return CAVERN_SOUNDTRACK_BIOME
	end
	if depthLayer == DEPTH_LAYER_UNDERGROUND then
		if biomeType == BIOME_TYPE_CORRUPTION then
			return UNDERGROUND_CORRUPTION_SOUNDTRACK_BIOME
		end
		if surfaceBiomeId == BIOME_ID_SNOW then
			return UNDERGROUND_SNOW_SOUNDTRACK_BIOME
		end
		return UNDERGROUND_SOUNDTRACK_BIOME
	end

	if isRainActive() then
		return RAIN_SOUNDTRACK_BIOME
	end

	if biomeType == BIOME_TYPE_CORRUPTION then
		return CORRUPTION_SOUNDTRACK_BIOME
	end

	if biomeId == BIOME_ID_SNOW then
		return SNOW_SOUNDTRACK_BIOME
	end
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

function AudioServiceClient.GetNextTrackForSoundtrackBiome(self: AudioServiceClient, soundtrackBiome: string): string?
	local assetIds = self.soundtrackAssetIdsByBiome[soundtrackBiome]
	if assetIds == nil or #assetIds <= 0 then
		error(MISSING_ASSET_ERROR, 0)
	end

	local shuffleBag = self.soundtrackShuffleBagByBiome[soundtrackBiome]
	if shuffleBag == nil or #shuffleBag <= 0 then
		shuffleBag = Table.copy(assetIds)
		shuffleStringsInPlace(self.random, shuffleBag)
		self.soundtrackShuffleBagByBiome[soundtrackBiome] = shuffleBag
	end

	if #shuffleBag <= 0 then
		return nil
	end
	return table.remove(shuffleBag, 1)
end

function AudioServiceClient.ClearActiveSoundtrackConnections(self: AudioServiceClient)
	if self.soundtrackTrackEndedConnection ~= nil then
		self.soundtrackTrackEndedConnection:Disconnect()
		self.soundtrackTrackEndedConnection = nil
	end
	if self.soundtrackTrackDestroyingConnection ~= nil then
		self.soundtrackTrackDestroyingConnection:Disconnect()
		self.soundtrackTrackDestroyingConnection = nil
	end
end

function AudioServiceClient.PlayNextSoundtrackTrack(self: AudioServiceClient, playbackToken: number)
	if playbackToken ~= self.soundtrackPlaybackToken then
		return
	end

	local soundtrackBiome = self.soundtrackCurrentBiome
	if soundtrackBiome == nil or soundtrackBiome == "" then
		return
	end

	local nextTrackAssetId = self:GetNextTrackForSoundtrackBiome(soundtrackBiome)
	if nextTrackAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	local shouldLoop = SOUNDTRACK_LOOPED_BY_BIOME[soundtrackBiome] == true

	local playingSound = self:PlaySound(nextTrackAssetId, {
		category = "Music",
		channel = SOUNDTRACK_CHANNEL_NAME,
		looped = shouldLoop,
		autoDestroy = not shouldLoop,
		fadeInTime = SOUNDTRACK_FADE_SECONDS,
		fadeOutTime = SOUNDTRACK_FADE_SECONDS,
	}, "Music")
	if playingSound == nil then
		task.delay(SOUNDTRACK_TRACK_GAP_SECONDS, function()
			self:PlayNextSoundtrackTrack(playbackToken)
		end)
		return
	end

	self.soundtrackActiveTrack = playingSound
	self:ClearActiveSoundtrackConnections()
	if shouldLoop then
		return
	end

	local handled = false
	local function queueNextTrack()
		if handled then
			return
		end
		handled = true
		self:ClearActiveSoundtrackConnections()
		if self.soundtrackActiveTrack == playingSound then
			self.soundtrackActiveTrack = nil
		end
		if playbackToken ~= self.soundtrackPlaybackToken then
			return
		end
		task.delay(SOUNDTRACK_TRACK_GAP_SECONDS, function()
			self:PlayNextSoundtrackTrack(playbackToken)
		end)
	end

	self.soundtrackTrackEndedConnection = playingSound.Ended:Connect(function()
		queueNextTrack()
	end)
	self.soundtrackTrackDestroyingConnection = playingSound.Destroying:Connect(function()
		queueNextTrack()
	end)
end

function AudioServiceClient.SetSoundtrackBiome(self: AudioServiceClient, soundtrackBiomeRaw: any)
	local soundtrackBiome = if typeof(soundtrackBiomeRaw) == "string" and soundtrackBiomeRaw ~= ""
		then soundtrackBiomeRaw
		else DEFAULT_SOUNDTRACK_BIOME

	local tracks = self.soundtrackAssetIdsByBiome[soundtrackBiome]
	if tracks == nil or #tracks <= 0 then
		error(MISSING_ASSET_ERROR, 0)
	end

	local activeTrack = self.soundtrackActiveTrack
	local isTrackAlive = activeTrack ~= nil and activeTrack.Parent ~= nil
	if self.soundtrackCurrentBiome == soundtrackBiome and isTrackAlive then
		return
	end

	self.soundtrackCurrentBiome = soundtrackBiome
	self.soundtrackPlaybackToken += 1
	self:PlayNextSoundtrackTrack(self.soundtrackPlaybackToken)
end

function AudioServiceClient.UpdateBiomeSoundtrack(self: AudioServiceClient, deltaTime: number)
	self:AttachBossStateListenerIfNeeded()
	self.soundtrackSampleAccumulator += deltaTime
	if self.soundtrackSampleAccumulator < SOUNDTRACK_BIOME_SAMPLE_INTERVAL then
		return
	end
	self.soundtrackSampleAccumulator = 0

	local soundtrackBiome = self:GetSoundtrackBiomeForLocalPlayer()
	if soundtrackBiome == nil then
		return
	end
	self:SetSoundtrackBiome(soundtrackBiome)
end

function AudioServiceClient.Init(self: AudioServiceClient)
	if self.janitor ~= nil then
		return
	end
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.characterSoundJanitor = Janitor.new()
	self.state = AudioServiceUtils.CreateDefaultState()
	self.runtimeFolder = AudioServiceUtils.EnsureRuntimeFolder(RobloxSoundService)
	self.categoryGroups = AudioServiceUtils.EnsureCategoryGroups(RobloxSoundService)
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
	self.bossStateChangedConnection = nil

	self.binders = NevermoreSupport.GetService(BinderSupportClient)
	AudioServiceUtils.ApplyStateToCategoryGroups(self.state, self.categoryGroups)
	disableDefaultCharacterSoundSystem(self.localPlayer, self.localPlayer.Character)
	self:RefreshSoundtrackAssetIds()

	self.janitor:GiveChore(self.characterSoundJanitor)
	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:OnCharacterAdded(character)
		self.soundtrackSampleAccumulator = SOUNDTRACK_BIOME_SAMPLE_INTERVAL
	end))
	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:UpdateBiomeSoundtrack(deltaTime)
	end))

	self.janitor:GiveChore(function()
		self:ClearActiveSoundtrackConnections()
		self:StopAll(0)
	end)

	if self.localPlayer.Character then
		self:OnCharacterAdded(self.localPlayer.Character)
	end

	sendPacket("requestSync")
end

function AudioServiceClient.OnCharacterAdded(self: AudioServiceClient, character: Model)
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

function AudioServiceClient.ApplyState(
	self: AudioServiceClient,
	masterVolumeRaw: any,
	mutedRaw: any,
	categoryVolumesRaw: any
)
	self.state = AudioServiceUtils.CreateState(masterVolumeRaw, mutedRaw, categoryVolumesRaw, self.state)
	AudioServiceUtils.ApplyStateToCategoryGroups(self.state, self.categoryGroups)
end

function AudioServiceClient.SetMasterVolume(self: AudioServiceClient, masterVolumeRaw: any, replicateToServer: boolean?)
	self.state = AudioServiceUtils.WithMasterVolume(self.state, masterVolumeRaw)
	AudioServiceUtils.ApplyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		sendPacket("setMasterVolume", self.state.masterVolume)
	end
end

function AudioServiceClient.SetMuted(self: AudioServiceClient, mutedRaw: any, replicateToServer: boolean?)
	self.state = AudioServiceUtils.WithMuted(self.state, mutedRaw)
	AudioServiceUtils.ApplyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		sendPacket("setMuted", self.state.muted)
	end
end

function AudioServiceClient.SetCategoryVolume(
	self: AudioServiceClient,
	categoryRaw: any,
	volumeRaw: any,
	replicateToServer: boolean?
)
	self.state = AudioServiceUtils.WithCategoryVolume(self.state, categoryRaw, volumeRaw)
	AudioServiceUtils.ApplyStateToCategoryGroups(self.state, self.categoryGroups)
	if replicateToServer ~= false then
		local category = AudioServiceUtils.NormalizeCategoryOrNil(categoryRaw)
		if category then
			sendPacket("setCategoryVolume", category, volumeRaw)
		end
	end
end

function AudioServiceClient.ToggleMute(self: AudioServiceClient, replicateToServer: boolean?)
	self:SetMuted(not self.state.muted, replicateToServer)
end

function AudioServiceClient.RequestSync(_self: AudioServiceClient)
	sendPacket("requestSync")
end

function AudioServiceClient.PlaySound(
	self: AudioServiceClient,
	soundAssetIdRaw: any,
	optionsRaw: any,
	fallbackCategory: SoundCategory?
): Sound?
	local soundAssetId, options =
		AudioServiceUtils.GetPlaybackRequest(soundAssetIdRaw, optionsRaw, fallbackCategory)
	if soundAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	if self.runtimeFolder == nil then
		self.runtimeFolder = AudioServiceUtils.EnsureRuntimeFolder(RobloxSoundService)
	end
	if self.categoryGroups == nil then
		self.categoryGroups = AudioServiceUtils.EnsureCategoryGroups(RobloxSoundService)
		local state = self.state or AudioServiceUtils.CreateDefaultState()
		self.state = state
		AudioServiceUtils.ApplyStateToCategoryGroups(state, self.categoryGroups)
	end
	if self.channelSounds == nil then
		self.channelSounds = {}
	end

	local categoryGroups = self.categoryGroups :: { [string]: SoundGroup? }
	local categoryGroup = categoryGroups[options.category]

	local shouldReplaceChannel = if options.replaceChannel == nil then true else options.replaceChannel
	if options.channel and shouldReplaceChannel then
		self:StopChannel(options.channel, options.fadeOutTime)
	end

	local sound = AudioServiceUtils.CreateSoundInstance(soundAssetId, options, self.runtimeFolder, categoryGroup)
	if not sound then
		return nil
	end

	local channelName = options.channel
	if channelName then
		local channelSounds = self.channelSounds :: { [string]: Sound? }
		channelSounds[channelName] = sound

		local channelConnection: RBXScriptConnection?
		channelConnection = sound.Destroying:Connect(function()
			if channelSounds[channelName] == sound then
				channelSounds[channelName] = nil
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
		AudioServiceUtils.FadeSoundVolume(sound, targetVolume, fadeInTime)
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

function AudioServiceClient.PlaySfx(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	return self:PlaySound(soundAssetIdRaw, optionsRaw, "SFX")
end

function AudioServiceClient.PlayUi(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	return self:PlaySound(soundAssetIdRaw, optionsRaw, "UI")
end

function AudioServiceClient.PlayMusic(self: AudioServiceClient, soundAssetIdRaw: any, optionsRaw: any): Sound?
	local options = AudioServiceUtils.CoercePlaybackOptions(optionsRaw, "Music")
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
	return self:PlaySound(soundAssetIdRaw, options, "Music")
end

function AudioServiceClient.StopChannel(self: AudioServiceClient, channelNameRaw: any, fadeTimeRaw: any)
	if typeof(channelNameRaw) ~= "string" or channelNameRaw == "" then
		return
	end

	local channelSounds = self.channelSounds :: { [string]: Sound? }
	local sound = channelSounds[channelNameRaw]
	if not sound then
		return
	end

	channelSounds[channelNameRaw] = nil
	AudioServiceUtils.StopAndDestroySound(sound, fadeTimeRaw)
end

function AudioServiceClient.StopAll(self: AudioServiceClient, fadeTimeRaw: any)
	local channels: { string } = {}
	for channelName in pairs(self.channelSounds :: { [string]: Sound? }) do
		table.insert(channels, channelName)
	end

	for _, channelName in channels do
		self:StopChannel(channelName, fadeTimeRaw)
	end
end

function AudioServiceClient.Destroy(self: AudioServiceClient)
	if self.janitor then
		self.janitor:Destroy()
		self.janitor = nil
	end
end


type AudioServiceClient = typeof(AudioServiceClient) & {
	RefreshSoundtrackAssetIds: (self: AudioServiceClient) -> (),
	GetBiomeTypeAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number,
	GetBiomeIdAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number,
	GetSurfaceBiomeIdAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number,
	GetDepthLayerAtWorldPosition: (self: AudioServiceClient, worldPosition: Vector3) -> number?,
	HasSoundtrackTracks: (self: AudioServiceClient, soundtrackBiome: string) -> boolean,
	AttachBossStateListenerIfNeeded: (self: AudioServiceClient) -> (),
	GetBossSoundtrackBiome: (self: AudioServiceClient) -> string?,
	GetSoundtrackBiomeForLocalPlayer: (self: AudioServiceClient) -> string?,
	GetNextTrackForSoundtrackBiome: (self: AudioServiceClient, soundtrackBiome: string) -> string?,
	ClearActiveSoundtrackConnections: (self: AudioServiceClient) -> (),
	PlayNextSoundtrackTrack: (self: AudioServiceClient, playbackToken: number) -> (),
	SetSoundtrackBiome: (self: AudioServiceClient, soundtrackBiomeRaw: any) -> (),
	UpdateBiomeSoundtrack: (self: AudioServiceClient, deltaTime: number) -> (),
	localPlayer: Player,
	janitor: any,
	characterSoundJanitor: JanitorClass,
	state: AudioServiceState,
	runtimeFolder: Folder,
	categoryGroups: { [string]: SoundGroup? },
	channelSounds: { [string]: Sound? },
	random: Random,
	soundtrackAssetIdsByBiome: { [string]: { string } },
	soundtrackShuffleBagByBiome: { [string]: { string } },
	soundtrackCurrentBiome: string?,
	soundtrackActiveTrack: Sound?,
	soundtrackPlaybackToken: number,
	soundtrackTrackEndedConnection: RBXScriptConnection?,
	soundtrackTrackDestroyingConnection: RBXScriptConnection?,
	soundtrackSampleAccumulator: number,
	bossStateChangedConnection: RBXScriptConnection?,
}

return AudioServiceClient :: AudioServiceClient
