--!strict
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Terrain = workspace.Terrain
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local CameraShaker = require(ReplicatedStorage.Packages.EZCameraShake)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local WeatherServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.WeatherServiceUtils)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)

type WeatherServiceState = WeatherServiceUtils.WeatherServiceState
type SkyKey = WeatherServiceUtils.SkyKey

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type CameraShakerObject = {
	Start: (self: CameraShakerObject) -> (),
	Stop: (self: CameraShakerObject) -> (),
	ShakeOnce: (
		self: CameraShakerObject,
		magnitude: number,
		roughness: number,
		fadeInTime: number?,
		fadeOutTime: number?,
		posInfluence: Vector3?,
		rotInfluence: Vector3?
	) -> any,
}

type SkyTemplate = {
	sky: Sky?,
	atmosphere: Atmosphere?,
	colorCorrection: ColorCorrectionEffect?,
	bloom: BloomEffect?,
	sunRays: SunRaysEffect?,
	depthOfField: DepthOfFieldEffect?,
	lighting: Lighting?,
	clouds: Clouds?,
}

type RainRuntime = {
	anchorPart: Part,
	emitters: { ParticleEmitter },
}

local WeatherServiceClient = {}

local RUNTIME_SKY_NAME = "WeatherServiceSky"
local RUNTIME_ATMOSPHERE_NAME = "WeatherServiceAtmosphere"
local RUNTIME_COLOR_CORRECTION_NAME = "WeatherServiceColorCorrection"
local RUNTIME_BLOOM_NAME = "WeatherServiceBloom"
local RUNTIME_SUN_RAYS_NAME = "WeatherServiceSunRays"
local RUNTIME_DEPTH_OF_FIELD_NAME = "WeatherServiceDepthOfField"
local RUNTIME_LIGHTNING_FLASH_NAME = "WeatherServiceLightningFlash"
local RUNTIME_RAIN_ANCHOR_NAME = "WeatherServiceRainAnchor"
local WEATHER_RAIN_CHANNEL_NAME = "weatherRain"
local WEATHER_CAMERA_SHAKE_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local RAIN_RATE_PER_EMITTER_AT_FULL = 130
local RAIN_FOLLOW_HEIGHT = 34
local RAIN_AUDIO_BASE_VOLUME = 0.18
local RAIN_AUDIO_MAX_VOLUME = 0.55
local CLOCK_MAX_FOLLOW_SPEED_HOURS_PER_SECOND = 8
local CORRUPTION_CLOUD_COLOR = Color3.fromRGB(255, 145, 72)
local LIGHTNING_FLASH_TINT = Color3.fromRGB(255, 255, 255)
local LIGHTNING_FLASH_BASE_BRIGHTNESS = 0.12
local LIGHTNING_FLASH_RANDOM_BRIGHTNESS = 0.22
local LIGHTNING_FLASH_BASE_CONTRAST = 0.045
local LIGHTNING_FLASH_RANDOM_CONTRAST = 0.085
local LIGHTNING_FLASH_FADE_SECONDS = 0.22
local LIGHTNING_CAMERA_SHAKE_BASE_MAGNITUDE = 2.8
local LIGHTNING_CAMERA_SHAKE_RANDOM_MAGNITUDE = 1.8
local LIGHTNING_CAMERA_SHAKE_BASE_ROUGHNESS = 8
local LIGHTNING_CAMERA_SHAKE_RANDOM_ROUGHNESS = 4
local LIGHTNING_CAMERA_SHAKE_FADE_IN = 0.02
local LIGHTNING_CAMERA_SHAKE_FADE_OUT = 0.45
local LIGHTNING_CAMERA_SHAKE_POSITION_INFLUENCE = Vector3.new(0.18, 0.3, 0.14)
local LIGHTNING_CAMERA_SHAKE_ROTATION_INFLUENCE = Vector3.new(1.4, 2.6, 1.1)
local WEATHER_AUDIO = ((AudioRegistry :: any).Misc or {}).Weather or {}
local WEATHER_RAIN_SOUND_ASSET_ID = AudioServiceUtils.normalizeSoundAssetId(WEATHER_AUDIO.Rain)
local WEATHER_THUNDER_SOUND_ASSET_IDS = AudioServiceUtils.collectSoundAssetIds(WEATHER_AUDIO.Thunder)

local cachedAudioServiceClient = nil
local cachedWindFoliageServiceClient = nil

local RAIN_ATTACHMENT_OFFSETS = {
	Vector3.new(-35, 0, -35),
	Vector3.new(0, 0, -35),
	Vector3.new(35, 0, -35),
	Vector3.new(-35, 0, 0),
	Vector3.new(0, 0, 0),
	Vector3.new(35, 0, 0),
	Vector3.new(-35, 0, 35),
	Vector3.new(0, 0, 35),
	Vector3.new(35, 0, 35),
}

local SKY_PROPERTY_NAMES = {
	"CelestialBodiesShown",
	"MoonAngularSize",
	"MoonTextureId",
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
	"StarCount",
	"SunAngularSize",
	"SunTextureId",
}

local ATMOSPHERE_PROPERTY_NAMES = {
	"Density",
	"Offset",
	"Color",
	"Decay",
	"Glare",
	"Haze",
}

local COLOR_CORRECTION_PROPERTY_NAMES = {
	"Brightness",
	"Contrast",
	"Saturation",
	"TintColor",
	"Enabled",
}

local BLOOM_PROPERTY_NAMES = {
	"Intensity",
	"Size",
	"Threshold",
	"Enabled",
}

local SUN_RAYS_PROPERTY_NAMES = {
	"Intensity",
	"Spread",
	"Enabled",
}

local DEPTH_OF_FIELD_PROPERTY_NAMES = {
	"FarIntensity",
	"FocusDistance",
	"InFocusRadius",
	"NearIntensity",
	"Enabled",
}

local LIGHTING_PROPERTY_NAMES = {
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"ColorShift_Bottom",
	"ColorShift_Top",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"ExposureCompensation",
	"FogColor",
	"FogStart",
	"FogEnd",
	"GeographicLatitude",
}

local function resolveCharacterRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function isContainerInstance(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Folder") or instance:IsA("Model"))
end

local function resolveWeatherSkyRoot(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not isContainerInstance(assets) then
		return nil
	end

	local weather = (assets :: Instance):FindFirstChild("Weather")
	if not isContainerInstance(weather) then
		return nil
	end

	local sky = (weather :: Instance):FindFirstChild("Sky")
	if isContainerInstance(sky) then
		return sky
	end
	return nil
end

local function resolveSkyFolderByKey(skyRoot: Instance?, skyKey: SkyKey): Instance?
	if skyRoot == nil then
		return nil
	end

	local direct = skyRoot:FindFirstChild(skyKey)
	if isContainerInstance(direct) then
		return direct
	end

	local token = string.lower(skyKey)
	for _, child in skyRoot:GetChildren() do
		if isContainerInstance(child) and string.lower(child.Name) == token then
			return child
		end
	end

	return nil
end

local function assignTemplateFromInstance(template: SkyTemplate, instance: Instance)
	if template.sky == nil and instance:IsA("Sky") then
		template.sky = instance
		return
	end
	if template.atmosphere == nil and instance:IsA("Atmosphere") then
		template.atmosphere = instance
		return
	end
	if template.colorCorrection == nil and instance:IsA("ColorCorrectionEffect") then
		template.colorCorrection = instance
		return
	end
	if template.bloom == nil and instance:IsA("BloomEffect") then
		template.bloom = instance
		return
	end
	if template.sunRays == nil and instance:IsA("SunRaysEffect") then
		template.sunRays = instance
		return
	end
	if template.depthOfField == nil and instance:IsA("DepthOfFieldEffect") then
		template.depthOfField = instance
		return
	end
	if template.lighting == nil and instance:IsA("Lighting") then
		template.lighting = instance
		return
	end
	if template.clouds == nil and instance:IsA("Clouds") then
		template.clouds = instance
		return
	end
end

local function collectSkyTemplate(folder: Instance): SkyTemplate?
	local template: SkyTemplate = {
		sky = nil,
		atmosphere = nil,
		colorCorrection = nil,
		bloom = nil,
		sunRays = nil,
		depthOfField = nil,
		lighting = nil,
		clouds = nil,
	}

	assignTemplateFromInstance(template, folder)
	for _, descendant in folder:GetDescendants() do
		assignTemplateFromInstance(template, descendant)
	end

	if template.sky == nil
		and template.atmosphere == nil
		and template.colorCorrection == nil
		and template.bloom == nil
		and template.sunRays == nil
		and template.depthOfField == nil
		and template.lighting == nil
		and template.clouds == nil
	then
		return nil
	end

	return template
end

local function copyPropertyIfPossible(source: Instance, target: Instance, propertyName: string)
	local okRead, value = pcall(function()
		return (source :: any)[propertyName]
	end)
	if not okRead then
		return
	end

	pcall(function()
		(target :: any)[propertyName] = value
	end)
end

local function buildTweenGoal(source: Instance, target: Instance, propertyNames: { string }): { [string]: any }
	local goal = {}
	for _, propertyName in propertyNames do
		local okRead, sourceValue = pcall(function()
			return (source :: any)[propertyName]
		end)
		if not okRead then
			continue
		end

		local okTarget = pcall(function()
			local _ = (target :: any)[propertyName]
		end)
		if not okTarget then
			continue
		end

		local sourceType = typeof(sourceValue)
		if sourceType == "number" or sourceType == "Color3" then
			goal[propertyName] = sourceValue
		else
			pcall(function()
				(target :: any)[propertyName] = sourceValue
			end)
		end
	end
	return goal
end

local function resolveCloudFallback(skyKey: SkyKey): (number, number, Color3)
	if skyKey == WeatherServiceUtils.SKY_KEY_CORRUPTION then
		return 0.64, 0.56, CORRUPTION_CLOUD_COLOR
	end
	if skyKey == WeatherServiceUtils.SKY_KEY_UNDERGROUND then
		return 0.02, 0.04, Color3.fromRGB(178, 186, 201)
	end
	if skyKey == WeatherServiceUtils.SKY_KEY_SNOW_BIOME then
		return 0.4, 0.36, Color3.fromRGB(228, 236, 245)
	end
	return 0.34, 0.32, Color3.fromRGB(235, 242, 255)
end

local function getAudioServiceClient(): any?
	if cachedAudioServiceClient ~= nil then
		return cachedAudioServiceClient
	end

	local ok, moduleOrError = pcall(function()
		return require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
	end)
	if not ok then
		return nil
	end

	cachedAudioServiceClient = moduleOrError
	return cachedAudioServiceClient
end

local function getWindFoliageServiceClient(): any?
	if cachedWindFoliageServiceClient ~= nil then
		return cachedWindFoliageServiceClient
	end

	local ok, moduleOrError = pcall(function()
		return require(script:FindFirstAncestor("game").Client.Services.WindFoliageServiceClient)
	end)
	if not ok then
		return nil
	end

	cachedWindFoliageServiceClient = moduleOrError
	return cachedWindFoliageServiceClient
end

function WeatherServiceClient.InitializeCameraShaker(self: WeatherServiceClient)
	local cameraShakerOk, cameraShakerOrError = pcall(function()
		local cameraShaker = CameraShaker.new(WEATHER_CAMERA_SHAKE_RENDER_PRIORITY, function(shakeCFrame: CFrame)
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end

			camera.CFrame = camera.CFrame * shakeCFrame
		end) :: any
		return cameraShaker :: CameraShakerObject
	end)
	if not cameraShakerOk then
		self.cameraShaker = nil
		return
	end

	self.cameraShaker = cameraShakerOrError :: CameraShakerObject
	local startOk = pcall(function()
		(self.cameraShaker :: CameraShakerObject):Start()
	end)
	if not startOk then
		self.cameraShaker = nil
	end
end

function WeatherServiceClient.PickRandomThunderSoundAssetId(self: WeatherServiceClient): string?
	local soundCount = #WEATHER_THUNDER_SOUND_ASSET_IDS
	if soundCount <= 0 then
		return nil
	end

	return WEATHER_THUNDER_SOUND_ASSET_IDS[self.random:NextInteger(1, soundCount)]
end

function WeatherServiceClient.UpdateRainAudio(self: WeatherServiceClient)
	local audioServiceClient = getAudioServiceClient()
	if audioServiceClient == nil or audioServiceClient.categoryGroups == nil then
		return
	end

	local rainPresence = math.clamp(math.max(self.currentRainIntensity, self.targetRainIntensity), 0, 1)
	if WEATHER_RAIN_SOUND_ASSET_ID == nil or rainPresence <= 0.01 then
		audioServiceClient:stopChannel(WEATHER_RAIN_CHANNEL_NAME, 0.3)
		return
	end

	local targetVolume = RAIN_AUDIO_BASE_VOLUME + (RAIN_AUDIO_MAX_VOLUME - RAIN_AUDIO_BASE_VOLUME) * rainPresence
	local activeRainSound = audioServiceClient.channelSounds[WEATHER_RAIN_CHANNEL_NAME]
	if activeRainSound ~= nil and activeRainSound.Parent ~= nil then
		activeRainSound.Volume = targetVolume
		return
	end

	audioServiceClient:playSfx(WEATHER_RAIN_SOUND_ASSET_ID, {
		channel = WEATHER_RAIN_CHANNEL_NAME,
		looped = true,
		autoDestroy = false,
		volume = targetVolume,
		fadeInTime = 0.35,
		fadeOutTime = 0.35,
	})
end

function WeatherServiceClient.UpdateWeatherWind(self: WeatherServiceClient)
	local windFoliageServiceClient = getWindFoliageServiceClient()
	if windFoliageServiceClient == nil or windFoliageServiceClient.simulation == nil then
		return
	end

	local stormAlpha = math.clamp(math.max(self.currentRainIntensity, self.targetRainIntensity), 0, 1)
	local isThunderstorm = WeatherServiceUtils.isThunderWeather(self.state.weatherType)
	windFoliageServiceClient:setWeatherWind(stormAlpha, isThunderstorm)
end

function WeatherServiceClient.WarnMissingSkyAsset(self: WeatherServiceClient, skyKey: SkyKey)
	if self.missingSkyWarnedByKey[skyKey] then
		return
	end
	self.missingSkyWarnedByKey[skyKey] = true
end

function WeatherServiceClient.PlayManagedTween(
	self: WeatherServiceClient,
	key: string,
	target: Instance,
	durationSecondsRaw: any,
	goal: { [string]: any }
)
	local existingTween = self.tweensByKey[key]
	if existingTween ~= nil then
		existingTween:Cancel()
		existingTween:Destroy()
		self.tweensByKey[key] = nil
	end

	if next(goal) == nil then
		return
	end

	local durationSeconds = WeatherServiceUtils.sanitizeNumber(durationSecondsRaw, 0, 0, 20)
	if durationSeconds <= 0 then
		for propertyName, value in goal do
			pcall(function()
				(target :: any)[propertyName] = value
			end)
		end
		return
	end

	local okTween, tweenOrError = pcall(function()
		return TweenService:Create(
			target,
			TweenInfo.new(durationSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
	end)
	if not okTween then
		for propertyName, value in goal do
			pcall(function()
				(target :: any)[propertyName] = value
			end)
		end
		return
	end

	local tween = tweenOrError :: Tween
	self.tweensByKey[key] = tween
	tween:Play()

	local completedConnection: RBXScriptConnection?
	completedConnection = tween.Completed:Connect(function()
		if completedConnection ~= nil then
			completedConnection:Disconnect()
			completedConnection = nil
		end
		if self.tweensByKey[key] == tween then
			self.tweensByKey[key] = nil
		end
		tween:Destroy()
	end)
end

function WeatherServiceClient.EnsureRuntimeSky(self: WeatherServiceClient): Sky
	if self.runtimeSky ~= nil and self.runtimeSky.Parent ~= nil then
		return self.runtimeSky
	end

	local existing = Lighting:FindFirstChild(RUNTIME_SKY_NAME)
	if existing ~= nil then
		if existing:IsA("Sky") then
			self.runtimeSky = existing
			return existing
		end
		existing:Destroy()
	end

	local sky = Instance.new("Sky")
	sky.Name = RUNTIME_SKY_NAME
	sky.Parent = Lighting
	self.runtimeSky = sky
	return sky
end

function WeatherServiceClient.EnsureRuntimeAtmosphere(self: WeatherServiceClient): Atmosphere
	if self.runtimeAtmosphere ~= nil and self.runtimeAtmosphere.Parent ~= nil then
		return self.runtimeAtmosphere
	end

	local existing = Lighting:FindFirstChild(RUNTIME_ATMOSPHERE_NAME)
	if existing ~= nil then
		if existing:IsA("Atmosphere") then
			self.runtimeAtmosphere = existing
			return existing
		end
		existing:Destroy()
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = RUNTIME_ATMOSPHERE_NAME
	atmosphere.Parent = Lighting
	self.runtimeAtmosphere = atmosphere
	return atmosphere
end

function WeatherServiceClient.EnsureRuntimeColorCorrection(self: WeatherServiceClient): ColorCorrectionEffect
	if self.runtimeColorCorrection ~= nil and self.runtimeColorCorrection.Parent ~= nil then
		return self.runtimeColorCorrection
	end

	local existing = Lighting:FindFirstChild(RUNTIME_COLOR_CORRECTION_NAME)
	if existing ~= nil then
		if existing:IsA("ColorCorrectionEffect") then
			self.runtimeColorCorrection = existing
			return existing
		end
		existing:Destroy()
	end

	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = RUNTIME_COLOR_CORRECTION_NAME
	effect.Enabled = true
	effect.Parent = Lighting
	self.runtimeColorCorrection = effect
	return effect
end

function WeatherServiceClient.EnsureRuntimeBloom(self: WeatherServiceClient): BloomEffect
	if self.runtimeBloom ~= nil and self.runtimeBloom.Parent ~= nil then
		return self.runtimeBloom
	end

	local existing = Lighting:FindFirstChild(RUNTIME_BLOOM_NAME)
	if existing ~= nil then
		if existing:IsA("BloomEffect") then
			self.runtimeBloom = existing
			return existing
		end
		existing:Destroy()
	end

	local effect = Instance.new("BloomEffect")
	effect.Name = RUNTIME_BLOOM_NAME
	effect.Enabled = true
	effect.Parent = Lighting
	self.runtimeBloom = effect
	return effect
end

function WeatherServiceClient.EnsureRuntimeSunRays(self: WeatherServiceClient): SunRaysEffect
	if self.runtimeSunRays ~= nil and self.runtimeSunRays.Parent ~= nil then
		return self.runtimeSunRays
	end

	local existing = Lighting:FindFirstChild(RUNTIME_SUN_RAYS_NAME)
	if existing ~= nil then
		if existing:IsA("SunRaysEffect") then
			self.runtimeSunRays = existing
			return existing
		end
		existing:Destroy()
	end

	local effect = Instance.new("SunRaysEffect")
	effect.Name = RUNTIME_SUN_RAYS_NAME
	effect.Enabled = true
	effect.Parent = Lighting
	self.runtimeSunRays = effect
	return effect
end

function WeatherServiceClient.EnsureRuntimeDepthOfField(self: WeatherServiceClient): DepthOfFieldEffect
	if self.runtimeDepthOfField ~= nil and self.runtimeDepthOfField.Parent ~= nil then
		return self.runtimeDepthOfField
	end

	local existing = Lighting:FindFirstChild(RUNTIME_DEPTH_OF_FIELD_NAME)
	if existing ~= nil then
		if existing:IsA("DepthOfFieldEffect") then
			self.runtimeDepthOfField = existing
			return existing
		end
		existing:Destroy()
	end

	local effect = Instance.new("DepthOfFieldEffect")
	effect.Name = RUNTIME_DEPTH_OF_FIELD_NAME
	effect.Enabled = true
	effect.Parent = Lighting
	self.runtimeDepthOfField = effect
	return effect
end

function WeatherServiceClient.EnsureLightningFlashEffect(self: WeatherServiceClient): ColorCorrectionEffect
	if self.lightningFlashEffect ~= nil and self.lightningFlashEffect.Parent ~= nil then
		return self.lightningFlashEffect
	end

	local existing = Lighting:FindFirstChild(RUNTIME_LIGHTNING_FLASH_NAME)
	if existing ~= nil then
		if existing:IsA("ColorCorrectionEffect") then
			self.lightningFlashEffect = existing
			return existing
		end
		existing:Destroy()
	end

	local flashEffect = Instance.new("ColorCorrectionEffect")
	flashEffect.Name = RUNTIME_LIGHTNING_FLASH_NAME
	flashEffect.Enabled = true
	flashEffect.Brightness = 0
	flashEffect.Contrast = 0
	flashEffect.Saturation = 0
	flashEffect.TintColor = LIGHTNING_FLASH_TINT
	flashEffect.Parent = Lighting
	self.lightningFlashEffect = flashEffect
	return flashEffect
end

function WeatherServiceClient.ApplyTemplateTween(
	self: WeatherServiceClient,
	tweenKey: string,
	runtimeInstance: Instance,
	templateInstance: Instance,
	propertyNames: { string },
	transitionSeconds: number
)
	local goal = buildTweenGoal(templateInstance, runtimeInstance, propertyNames)
	self:playManagedTween(tweenKey, runtimeInstance, transitionSeconds, goal)
end

function WeatherServiceClient.ApplySkyTemplate(self: WeatherServiceClient, template: SkyTemplate, transitionSeconds: number)
	if template.sky ~= nil then
		local runtimeSky = self:ensureRuntimeSky()
		for _, propertyName in SKY_PROPERTY_NAMES do
			copyPropertyIfPossible(template.sky, runtimeSky, propertyName)
		end
	elseif self.runtimeSky ~= nil then
		self.runtimeSky:Destroy()
		self.runtimeSky = nil
	end

	if template.atmosphere ~= nil then
		local runtimeAtmosphere = self:ensureRuntimeAtmosphere()
		self:applyTemplateTween(
			"atmosphere",
			runtimeAtmosphere,
			template.atmosphere,
			ATMOSPHERE_PROPERTY_NAMES,
			transitionSeconds
		)
	elseif self.runtimeAtmosphere ~= nil then
		self:playManagedTween("atmosphere", self.runtimeAtmosphere, transitionSeconds, {
			Density = 0,
			Haze = 0,
			Glare = 0,
		})
	end

	if template.colorCorrection ~= nil then
		local runtimeColorCorrection = self:ensureRuntimeColorCorrection()
		self:applyTemplateTween(
			"colorCorrection",
			runtimeColorCorrection,
			template.colorCorrection,
			COLOR_CORRECTION_PROPERTY_NAMES,
			transitionSeconds
		)
	elseif self.runtimeColorCorrection ~= nil then
		self:playManagedTween("colorCorrection", self.runtimeColorCorrection, transitionSeconds, {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
		})
	end

	if template.bloom ~= nil then
		local runtimeBloom = self:ensureRuntimeBloom()
		self:applyTemplateTween("bloom", runtimeBloom, template.bloom, BLOOM_PROPERTY_NAMES, transitionSeconds)
	elseif self.runtimeBloom ~= nil then
		self:playManagedTween("bloom", self.runtimeBloom, transitionSeconds, {
			Intensity = 0,
			Size = 0,
		})
	end

	if template.sunRays ~= nil then
		local runtimeSunRays = self:ensureRuntimeSunRays()
		self:applyTemplateTween("sunRays", runtimeSunRays, template.sunRays, SUN_RAYS_PROPERTY_NAMES, transitionSeconds)
	elseif self.runtimeSunRays ~= nil then
		self:playManagedTween("sunRays", self.runtimeSunRays, transitionSeconds, {
			Intensity = 0,
		})
	end

	if template.depthOfField ~= nil then
		local runtimeDepthOfField = self:ensureRuntimeDepthOfField()
		self:applyTemplateTween(
			"depthOfField",
			runtimeDepthOfField,
			template.depthOfField,
			DEPTH_OF_FIELD_PROPERTY_NAMES,
			transitionSeconds
		)
	elseif self.runtimeDepthOfField ~= nil then
		self:playManagedTween("depthOfField", self.runtimeDepthOfField, transitionSeconds, {
			FarIntensity = 0,
			NearIntensity = 0,
		})
	end

	if template.lighting ~= nil then
		local lightingGoal = buildTweenGoal(template.lighting, Lighting, LIGHTING_PROPERTY_NAMES)
		self:playManagedTween("lighting", Lighting, transitionSeconds, lightingGoal)
	end
end

function WeatherServiceClient.EnsureTerrainClouds(self: WeatherServiceClient): Clouds
	if self.terrainClouds ~= nil and self.terrainClouds.Parent ~= nil then
		return self.terrainClouds
	end

	local existingClouds = Terrain:FindFirstChildOfClass("Clouds")
	if existingClouds ~= nil then
		self.terrainClouds = existingClouds
		return existingClouds
	end

	local clouds = Instance.new("Clouds")
	clouds.Name = "WeatherServiceClouds"
	clouds.Cover = 0.34
	clouds.Density = 0.32
	clouds.Color = Color3.fromRGB(235, 242, 255)
	clouds.Parent = Terrain
	self.terrainClouds = clouds
	return clouds
end

function WeatherServiceClient.ApplyCloudTargetFromTemplate(
	self: WeatherServiceClient,
	templateClouds: Clouds?,
	skyKey: SkyKey,
	transitionSecondsRaw: any
)
	local nextCover: number
	local nextDensity: number
	local nextColor: Color3
	if templateClouds ~= nil then
		nextCover = WeatherServiceUtils.sanitizeNumber(templateClouds.Cover, self.cloudTargetCover, 0, 1)
		nextDensity = WeatherServiceUtils.sanitizeNumber(templateClouds.Density, self.cloudTargetDensity, 0, 1)
		nextColor = templateClouds.Color
	else
		nextCover, nextDensity, nextColor = resolveCloudFallback(skyKey)
	end

	if skyKey == WeatherServiceUtils.SKY_KEY_CORRUPTION then
		nextColor = CORRUPTION_CLOUD_COLOR
	end

	self.cloudTargetCover = nextCover
	self.cloudTargetDensity = nextDensity
	self.cloudTargetColor = nextColor
	self.cloudTransitionSeconds = WeatherServiceUtils.sanitizeNumber(
		transitionSecondsRaw,
		self.state.cloudTransitionSeconds,
		0.01,
		20
	)
end

function WeatherServiceClient.ResolveSkyKeyForLocalPlayer(self: WeatherServiceClient): SkyKey
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return WeatherServiceUtils.SKY_KEY_OVERWORLD
	end

	local worldState = WorldGenerationServiceClient:getState()
	if worldState.ready ~= true then
		return WeatherServiceUtils.SKY_KEY_OVERWORLD
	end

	local character = self.localPlayer.Character
	if character == nil then
		return WeatherServiceUtils.SKY_KEY_OVERWORLD
	end

	local rootPart = resolveCharacterRootPart(character)
	if rootPart == nil then
		return WeatherServiceUtils.SKY_KEY_OVERWORLD
	end
	local worldPosition = rootPart.Position

	local depthLayer = nil
	local okDepthLayer, depthLayerOrError = pcall(function()
		return (WorldGenerationServiceClient :: any):getDepthLayerAtWorldPosition(worldPosition)
	end)
	if okDepthLayer then
		depthLayer = depthLayerOrError
	end

	local okBiomeType, biomeTypeOrError = pcall(function()
		return WorldGenerationServiceClient:getBiomeTypeAtWorldPosition(worldPosition)
	end)
	local biomeType = if okBiomeType then biomeTypeOrError else nil
	local okBiomeId, biomeIdOrError = pcall(function()
		return WorldGenerationServiceClient:getBiomeIdAtWorldPosition(worldPosition)
	end)
	local biomeId = if okBiomeId then biomeIdOrError else nil

	return WeatherServiceUtils.resolveSkyKeyFromWorldSample(biomeId, biomeType, depthLayer)
end

function WeatherServiceClient.TransitionToSky(self: WeatherServiceClient, skyKeyRaw: any, transitionSecondsRaw: any?)
	local skyKey = WeatherServiceUtils.sanitizeSkyKey(skyKeyRaw, WeatherServiceUtils.SKY_KEY_OVERWORLD)
	local transitionSeconds = WeatherServiceUtils.sanitizeNumber(
		transitionSecondsRaw,
		self.state.skyTransitionSeconds,
		0,
		20
	)

	local skyRoot = resolveWeatherSkyRoot()
	local skyFolder = resolveSkyFolderByKey(skyRoot, skyKey)
	if skyFolder == nil then
		self:warnMissingSkyAsset(skyKey)
		local fallbackCover, fallbackDensity, fallbackColor = resolveCloudFallback(skyKey)
		self.cloudTargetCover = fallbackCover
		self.cloudTargetDensity = fallbackDensity
		self.cloudTargetColor = fallbackColor
		self.cloudTransitionSeconds = math.max(0.01, transitionSeconds)
		self.activeSkyKey = skyKey
		return
	end

	local template = collectSkyTemplate(skyFolder)
	if template == nil then
		self:warnMissingSkyAsset(skyKey)
		self.activeSkyKey = skyKey
		return
	end

	self:applySkyTemplate(template, transitionSeconds)
	self:applyCloudTargetFromTemplate(template.clouds, skyKey, transitionSeconds)
	self.activeSkyKey = skyKey
end

function WeatherServiceClient.CreateRainEmitter(self: WeatherServiceClient, attachment: Attachment): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RainEmitter"
	emitter.Enabled = true
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.55, 0.82)
	emitter.Speed = NumberRange.new(114, 138)
	emitter.Acceleration = Vector3.new(0, -190, 0)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.LightInfluence = 0
	emitter.Drag = 0
	emitter.Rotation = NumberRange.new(0, 0)
	emitter.RotSpeed = NumberRange.new(0, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07),
		NumberSequenceKeypoint.new(1, 0.03),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.92),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(203, 220, 255), Color3.fromRGB(172, 193, 244))
	emitter.Parent = attachment
	return emitter
end

function WeatherServiceClient.EnsureRainRuntime(self: WeatherServiceClient): RainRuntime
	if self.rainRuntime ~= nil and self.rainRuntime.anchorPart.Parent ~= nil then
		return self.rainRuntime
	end

	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()
	local existing = gameFolder:FindFirstChild(RUNTIME_RAIN_ANCHOR_NAME)
	if existing == nil then
		existing = Workspace:FindFirstChild(RUNTIME_RAIN_ANCHOR_NAME)
	end
	if existing ~= nil then
		existing:Destroy()
	end

	local anchorPart = Instance.new("Part")
	anchorPart.Name = RUNTIME_RAIN_ANCHOR_NAME
	anchorPart.Anchored = true
	anchorPart.Locked = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.CastShadow = false
	anchorPart.Material = Enum.Material.SmoothPlastic
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(1, 1, 1)
	anchorPart.Parent = gameFolder

	local emitters: { ParticleEmitter } = {}
	for _, offset in RAIN_ATTACHMENT_OFFSETS do
		local attachment = Instance.new("Attachment")
		attachment.Position = offset
		attachment.Parent = anchorPart
		table.insert(emitters, self:createRainEmitter(attachment))
	end

	self.rainRuntime = {
		anchorPart = anchorPart,
		emitters = emitters,
	}
	return self.rainRuntime
end

function WeatherServiceClient.ResolveRainFollowPosition(self: WeatherServiceClient): Vector3
	local character = self.localPlayer.Character
	local rootPart = resolveCharacterRootPart(character)
	if rootPart ~= nil then
		return rootPart.Position
	end

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return camera.CFrame.Position
	end
	return Vector3.zero
end

function WeatherServiceClient.UpdateRainRuntime(self: WeatherServiceClient)
	local runtime = self:ensureRainRuntime()
	local followPosition = self:resolveRainFollowPosition()
	runtime.anchorPart.CFrame = CFrame.new(followPosition + Vector3.new(0, RAIN_FOLLOW_HEIGHT, 0))

	local emitterRate = RAIN_RATE_PER_EMITTER_AT_FULL * self.currentRainIntensity
	for _, emitter in runtime.emitters do
		emitter.Rate = emitterRate
	end
end

function WeatherServiceClient.UpdateRainIntensity(self: WeatherServiceClient, dt: number)
	local transitionSeconds = math.max(0.01, self.state.rainTransitionSeconds)
	local alpha = math.clamp(dt / transitionSeconds, 0, 1)
	self.currentRainIntensity += (self.targetRainIntensity - self.currentRainIntensity) * alpha
	if math.abs(self.targetRainIntensity - self.currentRainIntensity) <= 0.0001 then
		self.currentRainIntensity = self.targetRainIntensity
	end
	self:updateRainRuntime()
end

function WeatherServiceClient.ResolveTargetClockTime(self: WeatherServiceClient): number
	local targetClockTime = self.state.clockTime
	if self.state.dayNightCycleEnabled and self.state.clockSpeed ~= 0 then
		local nowServerTime = Workspace:GetServerTimeNow()
		local elapsed = math.max(0, nowServerTime - self.state.snapshotServerTime)
		targetClockTime = WeatherServiceUtils.advanceClockTime(targetClockTime, elapsed, self.state.clockSpeed)
	end
	return targetClockTime
end

function WeatherServiceClient.UpdateClockTime(self: WeatherServiceClient, dt: number)
	local targetClockTime = self:resolveTargetClockTime()
	local currentClockTime = Lighting.ClockTime
	local delta = WeatherServiceUtils.shortestClockDeltaHours(currentClockTime, targetClockTime)
	local maxStep = math.max(0.001, dt * CLOCK_MAX_FOLLOW_SPEED_HOURS_PER_SECOND)
	if math.abs(delta) <= maxStep then
		Lighting.ClockTime = targetClockTime
		return
	end
	Lighting.ClockTime = WeatherServiceUtils.advanceClockTime(currentClockTime, 1, math.sign(delta) * maxStep)
end

function WeatherServiceClient.UpdateClouds(self: WeatherServiceClient, dt: number)
	local clouds = self:ensureTerrainClouds()
	local transitionSeconds = math.max(0.01, self.cloudTransitionSeconds)
	local alpha = math.clamp(dt / transitionSeconds, 0, 1)

	local rainPresence = math.clamp(math.max(self.currentRainIntensity, self.targetRainIntensity), 0, 1)
	local weatherCoverBoost = rainPresence * 0.26
	local weatherDensityBoost = rainPresence * 0.3
	local targetCover = math.clamp(self.cloudTargetCover + weatherCoverBoost, 0, 1)
	local targetDensity = math.clamp(self.cloudTargetDensity + weatherDensityBoost, 0, 1)
	if rainPresence > 0.01 then
		targetCover = math.max(targetCover, 0.68 + rainPresence * 0.18)
		targetDensity = math.max(targetDensity, 0.64 + rainPresence * 0.2)
	end

	clouds.Cover += (targetCover - clouds.Cover) * alpha
	clouds.Density += (targetDensity - clouds.Density) * alpha
	clouds.Color = clouds.Color:Lerp(self.cloudTargetColor, alpha)
end

function WeatherServiceClient.TriggerLightningFlash(self: WeatherServiceClient)
	local flashEffect = self:ensureLightningFlashEffect()
	flashEffect.Enabled = true
	local intensity = math.clamp(self.currentRainIntensity, 0, 1)
	flashEffect.Brightness =
		LIGHTNING_FLASH_BASE_BRIGHTNESS + self.random:NextNumber(0, LIGHTNING_FLASH_RANDOM_BRIGHTNESS) * intensity
	flashEffect.Contrast =
		LIGHTNING_FLASH_BASE_CONTRAST + self.random:NextNumber(0, LIGHTNING_FLASH_RANDOM_CONTRAST) * intensity
	flashEffect.TintColor = LIGHTNING_FLASH_TINT

	self:playManagedTween("lightningFlash", flashEffect, LIGHTNING_FLASH_FADE_SECONDS, {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
	})

	local cameraShaker = self.cameraShaker
	if cameraShaker ~= nil then
		pcall(function()
			cameraShaker:ShakeOnce(
				LIGHTNING_CAMERA_SHAKE_BASE_MAGNITUDE + self.random:NextNumber(0, LIGHTNING_CAMERA_SHAKE_RANDOM_MAGNITUDE) * intensity,
				LIGHTNING_CAMERA_SHAKE_BASE_ROUGHNESS + self.random:NextNumber(0, LIGHTNING_CAMERA_SHAKE_RANDOM_ROUGHNESS),
				LIGHTNING_CAMERA_SHAKE_FADE_IN,
				LIGHTNING_CAMERA_SHAKE_FADE_OUT,
				LIGHTNING_CAMERA_SHAKE_POSITION_INFLUENCE,
				LIGHTNING_CAMERA_SHAKE_ROTATION_INFLUENCE
			)
		end)
	end

	local thunderSoundAssetId = self:pickRandomThunderSoundAssetId()
	local audioServiceClient = getAudioServiceClient()
	if thunderSoundAssetId ~= nil and audioServiceClient ~= nil and audioServiceClient.categoryGroups ~= nil then
		audioServiceClient:playSfx(thunderSoundAssetId, {
			volume = 0.65 + intensity * 0.35,
			playbackSpeed = self.random:NextNumber(0.94, 1.05),
			rollOffMaxDistance = 1000,
			emitterSize = 80,
			fadeInTime = 0.05,
			fadeOutTime = 0.2,
		})
	end
end

function WeatherServiceClient.UpdateThunderFlash(self: WeatherServiceClient, dt: number)
	if not WeatherServiceUtils.isThunderWeather(self.state.weatherType) or self.currentRainIntensity < 0.35 then
		self.thunderFlashTimer = self.random:NextNumber(7.5, 14)
		return
	end

	self.thunderFlashTimer -= dt
	if self.thunderFlashTimer > 0 then
		return
	end

	self:triggerLightningFlash()
	local intensityFactor = math.clamp(self.currentRainIntensity, 0.2, 1)
	local minGap = 6.6 - intensityFactor * 1.2
	local maxGap = 13.8 - intensityFactor * 2.1
	self.thunderFlashTimer = self.random:NextNumber(math.max(4.8, minGap), math.max(7.2, maxGap))
end

function WeatherServiceClient.UpdateBiomeSky(self: WeatherServiceClient, dt: number)
	self.biomeSampleAccumulator += dt
	local sampleInterval = math.max(0.05, self.state.biomeSampleIntervalSeconds)
	if self.biomeSampleAccumulator < sampleInterval then
		return
	end
	self.biomeSampleAccumulator = 0

	local nextSkyKey = self:resolveSkyKeyForLocalPlayer()
	if nextSkyKey == self.activeSkyKey then
		return
	end

	self:transitionToSky(nextSkyKey, self.state.skyTransitionSeconds)
end

function WeatherServiceClient.OnHeartbeat(self: WeatherServiceClient, dtRaw: any)
	local dt = WeatherServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	self:updateClockTime(dt)
	self:updateBiomeSky(dt)
	self:updateRainIntensity(dt)
	self:updateRainAudio()
	self:updateWeatherWind()
	self:updateClouds(dt)
	self:updateThunderFlash(dt)
end

function WeatherServiceClient.ApplyState(self: WeatherServiceClient, stateRaw: any)
	local wasReady = self.hasReceivedServerState
	self.state = WeatherServiceUtils.sanitizeState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.targetRainIntensity = self.state.rainIntensity

	if not wasReady then
		self.currentRainIntensity = self.targetRainIntensity
	end
end

function WeatherServiceClient.RequestSync(self: WeatherServiceClient)
	self.networker:fire(WeatherServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function WeatherServiceClient.CleanupVisualRuntime(self: WeatherServiceClient)
	for key, tween in self.tweensByKey do
		tween:Cancel()
		tween:Destroy()
		self.tweensByKey[key] = nil
	end

	if self.rainRuntime ~= nil then
		if self.rainRuntime.anchorPart ~= nil and self.rainRuntime.anchorPart.Parent ~= nil then
			self.rainRuntime.anchorPart:Destroy()
		end
		self.rainRuntime = nil
	end
	local audioServiceClient = getAudioServiceClient()
	if audioServiceClient ~= nil and audioServiceClient.categoryGroups ~= nil then
		audioServiceClient:stopChannel(WEATHER_RAIN_CHANNEL_NAME, 0)
	end
	local windFoliageServiceClient = getWindFoliageServiceClient()
	if windFoliageServiceClient ~= nil and windFoliageServiceClient.simulation ~= nil then
		windFoliageServiceClient:setWeatherWind(0, false)
	end
	for _, instanceName in {
		RUNTIME_SKY_NAME,
		RUNTIME_ATMOSPHERE_NAME,
		RUNTIME_COLOR_CORRECTION_NAME,
		RUNTIME_BLOOM_NAME,
		RUNTIME_SUN_RAYS_NAME,
		RUNTIME_DEPTH_OF_FIELD_NAME,
		RUNTIME_LIGHTNING_FLASH_NAME,
	} do
		local existing = Lighting:FindFirstChild(instanceName)
		if existing ~= nil then
			existing:Destroy()
		end
	end
end

function WeatherServiceClient.Init(self: WeatherServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("WeatherService", self)
	self.janitor = Janitor.new()
	self.random = Random.new()

	self.state = WeatherServiceUtils.createStateFromConfig(nil)
	self.hasReceivedServerState = false
	self.activeSkyKey = nil :: SkyKey?
	self.missingSkyWarnedByKey = {} :: { [string]: boolean }
	self.biomeSampleAccumulator = self.state.biomeSampleIntervalSeconds
	self.thunderFlashTimer = self.random:NextNumber(2.2, 6.4)
	self.tweensByKey = {} :: { [string]: Tween }

	self.runtimeSky = nil :: Sky?
	self.runtimeAtmosphere = nil :: Atmosphere?
	self.runtimeColorCorrection = nil :: ColorCorrectionEffect?
	self.runtimeBloom = nil :: BloomEffect?
	self.runtimeSunRays = nil :: SunRaysEffect?
	self.runtimeDepthOfField = nil :: DepthOfFieldEffect?
	self.lightningFlashEffect = nil :: ColorCorrectionEffect?
	self.terrainClouds = nil :: Clouds?
	self.rainRuntime = nil :: RainRuntime?
	self.cameraShaker = nil :: CameraShakerObject?

	self.currentRainIntensity = self.state.rainIntensity
	self.targetRainIntensity = self.state.rainIntensity
	local fallbackCover, fallbackDensity, fallbackColor = resolveCloudFallback(WeatherServiceUtils.SKY_KEY_OVERWORLD)
	self.cloudTargetCover = fallbackCover
	self.cloudTargetDensity = fallbackDensity
	self.cloudTargetColor = fallbackColor
	self.cloudTransitionSeconds = self.state.cloudTransitionSeconds
	self:initializeCameraShaker()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self:cleanupVisualRuntime()
	end)
	self.janitor:GiveChore(function()
		local activeCameraShaker = self.cameraShaker
		self.cameraShaker = nil
		if activeCameraShaker ~= nil then
			pcall(function()
				activeCameraShaker:Stop()
			end)
		end
	end)
	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function()
		self.biomeSampleAccumulator = self.state.biomeSampleIntervalSeconds
	end))
	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(dt: number)
		self:onHeartbeat(dt)
	end))

	self:transitionToSky(WeatherServiceUtils.SKY_KEY_OVERWORLD, 0)
	self:requestSync()
end

function WeatherServiceClient.Destroy(self: WeatherServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

WeatherServiceClient.warnMissingSkyAsset = WeatherServiceClient.WarnMissingSkyAsset
WeatherServiceClient.playManagedTween = WeatherServiceClient.PlayManagedTween
WeatherServiceClient.initializeCameraShaker = WeatherServiceClient.InitializeCameraShaker
WeatherServiceClient.pickRandomThunderSoundAssetId = WeatherServiceClient.PickRandomThunderSoundAssetId
WeatherServiceClient.updateRainAudio = WeatherServiceClient.UpdateRainAudio
WeatherServiceClient.updateWeatherWind = WeatherServiceClient.UpdateWeatherWind
WeatherServiceClient.ensureRuntimeSky = WeatherServiceClient.EnsureRuntimeSky
WeatherServiceClient.ensureRuntimeAtmosphere = WeatherServiceClient.EnsureRuntimeAtmosphere
WeatherServiceClient.ensureRuntimeColorCorrection = WeatherServiceClient.EnsureRuntimeColorCorrection
WeatherServiceClient.ensureRuntimeBloom = WeatherServiceClient.EnsureRuntimeBloom
WeatherServiceClient.ensureRuntimeSunRays = WeatherServiceClient.EnsureRuntimeSunRays
WeatherServiceClient.ensureRuntimeDepthOfField = WeatherServiceClient.EnsureRuntimeDepthOfField
WeatherServiceClient.ensureLightningFlashEffect = WeatherServiceClient.EnsureLightningFlashEffect
WeatherServiceClient.applyTemplateTween = WeatherServiceClient.ApplyTemplateTween
WeatherServiceClient.applySkyTemplate = WeatherServiceClient.ApplySkyTemplate
WeatherServiceClient.ensureTerrainClouds = WeatherServiceClient.EnsureTerrainClouds
WeatherServiceClient.applyCloudTargetFromTemplate = WeatherServiceClient.ApplyCloudTargetFromTemplate
WeatherServiceClient.resolveSkyKeyForLocalPlayer = WeatherServiceClient.ResolveSkyKeyForLocalPlayer
WeatherServiceClient.transitionToSky = WeatherServiceClient.TransitionToSky
WeatherServiceClient.createRainEmitter = WeatherServiceClient.CreateRainEmitter
WeatherServiceClient.ensureRainRuntime = WeatherServiceClient.EnsureRainRuntime
WeatherServiceClient.resolveRainFollowPosition = WeatherServiceClient.ResolveRainFollowPosition
WeatherServiceClient.updateRainRuntime = WeatherServiceClient.UpdateRainRuntime
WeatherServiceClient.updateRainIntensity = WeatherServiceClient.UpdateRainIntensity
WeatherServiceClient.resolveTargetClockTime = WeatherServiceClient.ResolveTargetClockTime
WeatherServiceClient.updateClockTime = WeatherServiceClient.UpdateClockTime
WeatherServiceClient.updateClouds = WeatherServiceClient.UpdateClouds
WeatherServiceClient.triggerLightningFlash = WeatherServiceClient.TriggerLightningFlash
WeatherServiceClient.updateThunderFlash = WeatherServiceClient.UpdateThunderFlash
WeatherServiceClient.updateBiomeSky = WeatherServiceClient.UpdateBiomeSky
WeatherServiceClient.onHeartbeat = WeatherServiceClient.OnHeartbeat
WeatherServiceClient.applyState = WeatherServiceClient.ApplyState
WeatherServiceClient.requestSync = WeatherServiceClient.RequestSync
WeatherServiceClient.cleanupVisualRuntime = WeatherServiceClient.CleanupVisualRuntime
WeatherServiceClient.init = WeatherServiceClient.Init
WeatherServiceClient.destroy = WeatherServiceClient.Destroy

type WeatherServiceClient = typeof(WeatherServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	random: Random,
	state: WeatherServiceState,
	hasReceivedServerState: boolean,
	activeSkyKey: SkyKey?,
	missingSkyWarnedByKey: { [string]: boolean },
	biomeSampleAccumulator: number,
	thunderFlashTimer: number,
	tweensByKey: { [string]: Tween },
	runtimeSky: Sky?,
	runtimeAtmosphere: Atmosphere?,
	runtimeColorCorrection: ColorCorrectionEffect?,
	runtimeBloom: BloomEffect?,
	runtimeSunRays: SunRaysEffect?,
	runtimeDepthOfField: DepthOfFieldEffect?,
	lightningFlashEffect: ColorCorrectionEffect?,
	terrainClouds: Clouds?,
	rainRuntime: RainRuntime?,
	cameraShaker: CameraShakerObject?,
	currentRainIntensity: number,
	targetRainIntensity: number,
	cloudTargetCover: number,
	cloudTargetDensity: number,
	cloudTargetColor: Color3,
	cloudTransitionSeconds: number,
}

return WeatherServiceClient :: WeatherServiceClient

