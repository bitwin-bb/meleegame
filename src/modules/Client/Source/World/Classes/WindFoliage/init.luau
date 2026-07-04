local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AttributeCache = require("AttributeCache")
local DeterministicRNG = require("DeterministicRng")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local ObjectPool = require("ObjectPool")
local TagBinder = require("TagBinder")
local TagQuery = require("TagQuery")
local TickSchedulerModule = require("TickScheduler")
local Vec = require("Vec")

local BufferPool = require(script:WaitForChild("BufferPool"))
local DisturbanceSourceModule = require(script:WaitForChild("DisturbanceSource"))
local FoliageInstance = require(script:WaitForChild("FoliageInstance"))
local FoliageUpdateManager = require(script:WaitForChild("FoliageUpdateManager"))
local LODController = require(script:WaitForChild("LodController"))
local TreeRuntimeRegistry = require(script:WaitForChild("TreeRuntimeRegistry"))
local WindField = require(script:WaitForChild("WindField"))

type WindSample = WindField.WindSample
type DisturbanceSource = DisturbanceSourceModule.DisturbanceSource
type FoliageObject = FoliageInstance.FoliageInstance

type JanitorClass = any

type TickScheduler = TickSchedulerModule.TickScheduler
type CancellationToken = TickSchedulerModule.CancellationToken
type LODState = FoliageInstance.LODState & { updateInterval: number }

type FoliageRecord = {
	instance: Instance,
	foliage: FoliageObject,
	id: number,
	bucketIndex: number,
	bucketSlot: number,
	lastSampleTime: number,
	cachedLodState: LODState?,
	cachedWindSample: WindSample?,
	destroyConnection: RBXScriptConnection?,
	attributeDisconnect: (() -> ())?,
}

type TrackedDisturberRecord = {
	instance: Instance,
	source: DisturbanceSource,
	sourceIndex: number,
	lastPosition: Vector3,
	overrideConfig: { [string]: any }?,
	kind: string,
	destroyConnection: RBXScriptConnection?,
}

type PlayerTrackRecord = {
	janitor: JanitorClass,
	character: Model?,
}

type Config = { [string]: any }

local WindFoliage = {}
WindFoliage.__index = WindFoliage

local ZERO = Vector3.zero
local DEFAULT_FOLIAGE_TAG = TagBinder.Tags.Foliage
local DEFAULT_DISTURBER_TAG = TagBinder.Tags.Disturber
local WORLD_ANIMATOR_RUNTIME_FOLDER_NAME = "WorldAnimatorRuntime"
local TREE_GRAPH_ATTRIBUTE = "WindFoliageTreeGraph"
local RUNTIME_ATTRIBUTE_LOD = "WindRuntimeLOD"
local RUNTIME_ATTRIBUTE_WRITES = "WindRuntimeWrites"

local ATTRIBUTES: { [string]: string } = {
	foliageEnabled = "WindFoliageEnabled",
	preset = "WindFoliagePreset",
	representation = "WindFoliageRepresentation",
	motionStyle = "WindFoliageMotionStyle",
	bendStiffness = "WindFoliageBendStiffness",
	damping = "WindFoliageDamping",
	maxBendAngle = "WindFoliageMaxBendAngle",
	heightMultiplier = "WindFoliageHeightMultiplier",
	swayAmplitude = "WindFoliageSwayAmplitude",
	gustSensitivity = "WindFoliageGustSensitivity",
	recoverySpeed = "WindFoliageRecoverySpeed",
	disturbanceSensitivity = "WindFoliageDisturbanceSensitivity",
	detailAmplitude = "WindFoliageDetailAmplitude",
	translationWeight = "WindFoliageTranslationWeight",
	yawWeight = "WindFoliageYawWeight",
	tipBias = "WindFoliageTipBias",
	pivotMode = "WindFoliagePivotMode",
	pivotAttachment = "WindFoliagePivotAttachment",
	pivotOffset = "WindFoliagePivotOffset",
	boneNames = "WindFoliageBoneNames",
	tweenSmoothingEnabled = "WindFoliageTweenSmoothingEnabled",
	tweenSmoothingDuration = "WindFoliageTweenSmoothingDuration",
	tweenSmoothingMaxDuration = "WindFoliageTweenSmoothingMaxDuration",

	disturbanceEnabled = "WindFoliageDisturbanceEnabled",
	disturbanceRadius = "WindFoliageDisturbanceRadius",
	disturbanceStrength = "WindFoliageDisturbanceStrength",
	disturbanceLifetime = "WindFoliageDisturbanceLifetime",
	disturbanceFalloff = "WindFoliageDisturbanceFalloff",
	disturbancePropagationDistance = "WindFoliageDisturbancePropagationDistance",
	disturbancePropagationWeight = "WindFoliageDisturbancePropagationWeight",
	disturbanceVelocityInfluence = "WindFoliageDisturbanceVelocityInfluence",
}

local REFRESH_ATTRIBUTE_SET = {
	[TREE_GRAPH_ATTRIBUTE] = true,
}

for _, attributeName in ATTRIBUTES do
	REFRESH_ATTRIBUTE_SET[attributeName] = true
end

local function setAttributeIfChanged(instance: Instance, attributeName: string, value: any)
	if instance:GetAttribute(attributeName) == value then
		return
	end
	instance:SetAttribute(attributeName, value)
end

local DEFAULT_PRESETS = {
	GrassLight = {
		motionStyle = "GrassTip",
		bendStiffness = 17,
		damping = 8.5,
		maxBendAngle = 18,
		heightMultiplier = 1.15,
		swayAmplitude = 0.9,
		gustSensitivity = 1.05,
		recoverySpeed = 6.8,
		disturbanceSensitivity = 1.3,
		detailAmplitude = 0.24,
		translationWeight = 0.12,
		yawWeight = 0.05,
		tipBias = 2.2,
		pivotMode = "Bottom",
	},
	GrassTall = {
		motionStyle = "GrassTip",
		bendStiffness = 12,
		damping = 7,
		maxBendAngle = 27,
		heightMultiplier = 1.5,
		swayAmplitude = 1.05,
		gustSensitivity = 1.3,
		recoverySpeed = 5.4,
		disturbanceSensitivity = 1.55,
		detailAmplitude = 0.3,
		translationWeight = 0.18,
		yawWeight = 0.07,
		tipBias = 2.5,
		pivotMode = "Bottom",
	},
	BushDense = {
		motionStyle = "BushBlend",
		bendStiffness = 11,
		damping = 7.8,
		maxBendAngle = 14,
		heightMultiplier = 0.95,
		swayAmplitude = 0.78,
		gustSensitivity = 0.92,
		recoverySpeed = 4.2,
		disturbanceSensitivity = 1.1,
		detailAmplitude = 0.18,
		translationWeight = 0.22,
		yawWeight = 0.17,
		tipBias = 1.3,
		pivotMode = "Center",
	},
	BranchSmall = {
		motionStyle = "Branch",
		bendStiffness = 7.2,
		damping = 5.6,
		maxBendAngle = 17,
		heightMultiplier = 0.9,
		swayAmplitude = 0.92,
		gustSensitivity = 1.26,
		recoverySpeed = 3.6,
		disturbanceSensitivity = 1.35,
		detailAmplitude = 0.2,
		translationWeight = 0.08,
		yawWeight = 0.14,
		tipBias = 1.9,
		pivotMode = "Attachment",
	},
	BranchHeavy = {
		motionStyle = "Branch",
		bendStiffness = 4.8,
		damping = 4.2,
		maxBendAngle = 12,
		heightMultiplier = 0.78,
		swayAmplitude = 0.72,
		gustSensitivity = 1.08,
		recoverySpeed = 2.7,
		disturbanceSensitivity = 0.95,
		detailAmplitude = 0.14,
		translationWeight = 0.05,
		yawWeight = 0.11,
		tipBias = 1.8,
		pivotMode = "Attachment",
	},
}

local DEFAULT_CONFIG: Config = {
	enabled = true,
	bucketCount = 4,
	gridCellSize = 18,
	octreeMaxDepth = 4,
	trackedRefreshInterval = 0.08,
	disturbancePulseInterval = 0.05,
	poolShrinkInterval = 2.5,
	maxPoolShrinkPerSweep = 12,
	autoTrackPlayers = true,
	foliageTag = DEFAULT_FOLIAGE_TAG,
	disturberTag = DEFAULT_DISTURBER_TAG,
	observeTaggedInstances = true,
	fallbackPreset = "GrassLight",
	lod = {
		nearDistance = 54,
		midDistance = 118,
		farDistance = 190,
		cullDistance = 280,
		nearUpdateInterval = 0.05,
		midUpdateInterval = 0.12,
		farUpdateInterval = 0.32,
	},
	playerDisturber = {
		radius = 12,
		strength = 4.2,
		lifetime = 0.38,
		falloffCurve = 1.1,
		propagationDistance = 7.5,
		propagationWeight = 0.7,
		velocityInfluence = 1.35,
	},
	disturberDefaults = {
		radius = 10,
		strength = 2.6,
		lifetime = 0.3,
		falloffCurve = 1.25,
		propagationDistance = 5.5,
		propagationWeight = 0.52,
		velocityInfluence = 0.75,
	},
	windField = {
		seed = "AquariaWindField",
		baseDirection = Vector3.new(1, 0, 0.25),
		strengthMultiplier = 20,
		baseStrength = 0.82,
		gustStrength = 1.25,
		detailStrength = 0.32,
		gustSpatialScale = 140,
		gustTimeScale = 0.22,
		detailSpatialScale = 22,
		detailTimeScale = 1.85,
		directionJitterDegrees = 24,
		gustOctaves = 4,
		detailOctaves = 3,
	},
	runtime = {
		nearDistance = 54,
		midDistance = 118,
		farDistance = 190,
		cullDistance = 280,
		viewDotCull = -0.35,
		enableVisibilityCull = true,
		nearUpdateInterval = 1 / 60,
		midUpdateInterval = 0.1,
		farUpdateInterval = 0.26,
		frozenUpdateInterval = 0.75,
		maxActiveTrees = 64,
		maxInteractiveTrees = 24,
		maxEntryInspectionsPerStep = 256,
		maxTransformWritesPerStep = 6000,
		tweenSmoothingEnabled = false,
		tweenSmoothingDuration = 0,
		tweenSmoothingMaxDuration = 0,
		enableSecondaryFlutter = true,
		enableCanopyOnlyFar = false,
		branchCapPerTree = 96,
		leafClusterCapPerTree = 80,
		primaryDriverResponseRate = 9,
		secondaryDriverResponseRate = 12,
		interactionDriverDecayRate = 4.8,
		flutterDriverResponseRate = 14,
		maxInteractionBend = 3.5,
		debug = {
			enabled = false,
		},
	},
	presets = DEFAULT_PRESETS,
}

local function clampNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local function CoerceString(valueRaw: any, fallback: string): string
	return if typeof(valueRaw) == "string" and valueRaw ~= "" then valueRaw else fallback
end

local function mergeTables(baseRaw: any, overrideRaw: any): { [string]: any }
	local merged = {}
	if typeof(baseRaw) == "table" then
		for key, value in baseRaw do
			if typeof(value) == "table" then
				merged[key] = mergeTables(value, nil)
			else
				merged[key] = value
			end
		end
	end
	if typeof(overrideRaw) == "table" then
		for key, value in overrideRaw do
			if typeof(value) == "table" and typeof(merged[key]) == "table" then
				merged[key] = mergeTables(merged[key], value)
			else
				merged[key] = value
			end
		end
	end
	return merged
end

local function splitCommaSeparatedNames(valueRaw: any): { string }
	local out = {}
	if typeof(valueRaw) ~= "string" then
		return out
	end
	for token in string.gmatch(valueRaw, "[^,]+") do
		local trimmed = string.match(token, "^%s*(.-)%s*$") or ""
		if trimmed ~= "" then
			out[#out + 1] = trimmed
		end
	end
	return out
end

local function GetRootPartFromModel(model: Model): BasePart?
	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function GetWorldPosition(instance: Instance): Vector3?
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	if instance:IsA("Bone") then
		local ok, worldCFrame = pcall(function()
			return instance.WorldCFrame
		end)
		if ok and typeof(worldCFrame) == "CFrame" then
			return worldCFrame.Position
		end
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		local rootPart = GetRootPartFromModel(instance)
		if rootPart ~= nil then
			return rootPart.Position
		end
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok and typeof(pivot) == "CFrame" then
			return pivot.Position
		end
	end
	return nil
end

local function GetWorldVelocity(
	instance: Instance,
	currentPosition: Vector3,
	previousPosition: Vector3,
	dt: number
): Vector3
	if instance:IsA("BasePart") then
		return instance.AssemblyLinearVelocity
	end
	if instance:IsA("Model") then
		local rootPart = GetRootPartFromModel(instance)
		if rootPart ~= nil then
			return rootPart.AssemblyLinearVelocity
		end
	end
	if dt <= 0 then
		return ZERO
	end
	return (currentPosition - previousPosition) / dt
end

local function canBeFoliageRoot(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Model") or instance:IsA("Bone")
end

local function canBeDisturber(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Model") or instance:IsA("Attachment") or instance:IsA("Bone")
end

local function isInWorkspace(instance: Instance): boolean
	return instance == Workspace or instance:IsDescendantOf(Workspace)
end

local function isInWorldAnimatorRuntime(instance: Instance): boolean
	local current = instance.Parent
	while current ~= nil do
		if current.Name == WORLD_ANIMATOR_RUNTIME_FOLDER_NAME then
			return true
		end
		current = current.Parent
	end
	return false
end

local function getServerAlignedTime(): number
	local ok, value = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and typeof(value) == "number" and value == value then
		return value
	end
	return os.clock()
end

function WindFoliage.New(configRaw: Config?): any
	local config = mergeTables(DEFAULT_CONFIG, configRaw)
	local bucketCount = math.max(1, math.floor(clampNumber(config.bucketCount, DEFAULT_CONFIG.bucketCount, 1, 32)))
	local tickScheduler = (config :: any).tickScheduler
	if tickScheduler == nil then
		error("WindFoliage.New requires a tickScheduler")
	end

	local lodConfig = mergeTables(DEFAULT_CONFIG.lod, config.lod)
	local self = setmetatable({
		config = config,
		tickScheduler = tickScheduler :: TickScheduler,
		janitor = Janitor.new(),
		attributeCache = AttributeCache.New(),
		tagQuery = TagQuery.New(CollectionService),
		windField = WindField.New(config.windField),
		bufferPool = BufferPool.New({
			maxAvailable = 32,
		}),
		runtimeRegistry = nil,
		lodController = nil,
		updateManager = nil,
		disturbancePool = ObjectPool.new(function()
			return DisturbanceSourceModule.CreateTemplate()
		end, {
			expandBy = 16,
			minAvailable = 4,
			maxAvailable = 512,
			reset = DisturbanceSourceModule.reset,
		}),
		trackedDisturbers = {} :: { [Instance]: TrackedDisturberRecord },
		activeDisturbances = {} :: { DisturbanceSource },
		playerTracks = {} :: { [Player]: PlayerTrackRecord },
		nextFoliageId = 0,
		nextDisturbanceId = 0,
		bucketCount = bucketCount,
		time = 0,
		timeOffset = getServerAlignedTime(),
		trackedRefreshAccumulator = 0,
		disturbanceAccumulator = 0,
		poolShrinkAccumulator = 0,
		schedulerToken = nil :: CancellationToken?,
		schedulerGroup = ("windFoliage_%s"):format(tostring(math.floor(os.clock() * 1000))),
		initialized = false,
		destroyed = false,
	}, WindFoliage)

	self.runtimeRegistry = TreeRuntimeRegistry.New({
		gridCellSize = clampNumber(config.gridCellSize, DEFAULT_CONFIG.gridCellSize, 1, 2048),
		octreeMaxDepth = clampNumber(config.octreeMaxDepth, DEFAULT_CONFIG.octreeMaxDepth, 1, 12),
	})
	self.lodController = LODController.New({
		lod = lodConfig,
		runtime = config.runtime,
	})
	self.updateManager =
		FoliageUpdateManager.New(config, self.runtimeRegistry, self.windField, self.lodController, self.bufferPool)

	return self
end

function WindFoliage.GetPreset(self: any, presetNameRaw: any): { [string]: any }
	local presets = if typeof(self.config.presets) == "table" then self.config.presets else DEFAULT_PRESETS
	local fallbackPresetName = CoerceString(self.config.fallbackPreset, "GrassLight")
	local presetName = CoerceString(presetNameRaw, fallbackPresetName)
	local preset = presets[presetName]
	if typeof(preset) ~= "table" then
		preset = presets[fallbackPresetName]
	end
	if typeof(preset) ~= "table" then
		preset = DEFAULT_PRESETS.GrassLight
	end
	return mergeTables(preset, nil)
end

function WindFoliage.GetFoliageConfig(self: any, instance: Instance, id: number): { [string]: any }
	self.attributeCache:Bind(instance)

	local presetName = self.attributeCache:Get(instance, ATTRIBUTES.preset, self.config.fallbackPreset)
	local preset = self:GetPreset(presetName)
	local seed = DeterministicRNG.SeedFrom(instance:GetFullName())
	local bucketIndex = (seed % self.bucketCount) + 1
	local runtime = if typeof(self.config.runtime) == "table" then self.config.runtime else {}

	preset.tweenSmoothingEnabled = runtime.tweenSmoothingEnabled ~= false
	if typeof(runtime.tweenSmoothingDuration) == "number" then
		preset.tweenSmoothingDuration = runtime.tweenSmoothingDuration
	end
	if typeof(runtime.tweenSmoothingMaxDuration) == "number" then
		preset.tweenSmoothingMaxDuration = runtime.tweenSmoothingMaxDuration
	end

	local function overrideNumber(fieldName: string, attributeName: string)
		local value = self.attributeCache:Get(instance, attributeName, nil)
		if typeof(value) == "number" then
			preset[fieldName] = value
		end
	end

	local function overrideString(fieldName: string, attributeName: string)
		local value = self.attributeCache:Get(instance, attributeName, nil)
		if typeof(value) == "string" and value ~= "" then
			preset[fieldName] = value
		end
	end

	overrideString("representation", ATTRIBUTES.representation)
	overrideString("motionStyle", ATTRIBUTES.motionStyle)
	overrideString("pivotMode", ATTRIBUTES.pivotMode)
	overrideString("pivotAttachmentName", ATTRIBUTES.pivotAttachment)
	overrideNumber("bendStiffness", ATTRIBUTES.bendStiffness)
	overrideNumber("damping", ATTRIBUTES.damping)
	overrideNumber("maxBendAngle", ATTRIBUTES.maxBendAngle)
	overrideNumber("heightMultiplier", ATTRIBUTES.heightMultiplier)
	overrideNumber("swayAmplitude", ATTRIBUTES.swayAmplitude)
	overrideNumber("gustSensitivity", ATTRIBUTES.gustSensitivity)
	overrideNumber("recoverySpeed", ATTRIBUTES.recoverySpeed)
	overrideNumber("disturbanceSensitivity", ATTRIBUTES.disturbanceSensitivity)
	overrideNumber("detailAmplitude", ATTRIBUTES.detailAmplitude)
	overrideNumber("translationWeight", ATTRIBUTES.translationWeight)
	overrideNumber("yawWeight", ATTRIBUTES.yawWeight)
	overrideNumber("tipBias", ATTRIBUTES.tipBias)
	overrideNumber("tweenSmoothingDuration", ATTRIBUTES.tweenSmoothingDuration)
	overrideNumber("tweenSmoothingMaxDuration", ATTRIBUTES.tweenSmoothingMaxDuration)

	local tweenSmoothingEnabled = self.attributeCache:Get(instance, ATTRIBUTES.tweenSmoothingEnabled, nil)
	if typeof(tweenSmoothingEnabled) == "boolean" then
		preset.tweenSmoothingEnabled = tweenSmoothingEnabled
	end

	local pivotOffset = self.attributeCache:Get(instance, ATTRIBUTES.pivotOffset, nil)
	if typeof(pivotOffset) == "Vector3" then
		preset.pivotOffset = pivotOffset
	end

	local boneNames = self.attributeCache:Get(instance, ATTRIBUTES.boneNames, nil)
	if typeof(boneNames) == "string" and boneNames ~= "" then
		preset.boneNames = splitCommaSeparatedNames(boneNames)
	end

	preset.id = id
	preset.seed = seed
	preset.bucketIndex = bucketIndex
	preset.presetName = CoerceString(presetName, self.config.fallbackPreset)

	return preset
end

function WindFoliage.ShouldRegisterFoliage(self: any, instance: Instance): boolean
	if not canBeFoliageRoot(instance) then
		return false
	end
	if not isInWorkspace(instance) then
		return false
	end
	if isInWorldAnimatorRuntime(instance) then
		return false
	end

	local foliageTag = CoerceString(self.config.foliageTag, DEFAULT_FOLIAGE_TAG)
	local hasTag = self.tagQuery:HasTag(instance, foliageTag)
	local enabled = instance:GetAttribute(ATTRIBUTES.foliageEnabled)
	if typeof(enabled) == "boolean" then
		if not enabled then
			return false
		end
		return true
	end

	if hasTag then
		return true
	end

	local presetName = instance:GetAttribute(ATTRIBUTES.preset)
	return typeof(presetName) == "string" and presetName ~= ""
end

function WindFoliage.ShouldTrackDisturber(self: any, instance: Instance): boolean
	if not canBeDisturber(instance) then
		return false
	end
	if not isInWorkspace(instance) then
		return false
	end
	if isInWorldAnimatorRuntime(instance) then
		return false
	end

	local enabled = instance:GetAttribute(ATTRIBUTES.disturbanceEnabled)
	if typeof(enabled) == "boolean" then
		return enabled
	end

	local disturberTag = CoerceString(self.config.disturberTag, DEFAULT_DISTURBER_TAG)
	return self.tagQuery:HasTag(instance, disturberTag)
end

function WindFoliage.GetDisturberConfig(
	self: any,
	instance: Instance,
	overrideConfigRaw: any,
	kind: string
): { [string]: any }
	self.attributeCache:Bind(instance)

	local baseConfig = if kind == "player" and typeof(self.config.playerDisturber) == "table"
		then self.config.playerDisturber
		else self.config.disturberDefaults
	local config = mergeTables(baseConfig, overrideConfigRaw)

	local radius = self.attributeCache:Get(instance, ATTRIBUTES.disturbanceRadius, nil)
	if typeof(radius) == "number" then
		config.radius = radius
	end

	local strength = self.attributeCache:Get(instance, ATTRIBUTES.disturbanceStrength, nil)
	if typeof(strength) == "number" then
		config.strength = strength
	end

	local lifetime = self.attributeCache:Get(instance, ATTRIBUTES.disturbanceLifetime, nil)
	if typeof(lifetime) == "number" then
		config.lifetime = lifetime
	end

	local falloffCurve = self.attributeCache:Get(instance, ATTRIBUTES.disturbanceFalloff, nil)
	if typeof(falloffCurve) == "number" then
		config.falloffCurve = falloffCurve
	end

	local propagationDistance = self.attributeCache:Get(instance, ATTRIBUTES.disturbancePropagationDistance, nil)
	if typeof(propagationDistance) == "number" then
		config.propagationDistance = propagationDistance
	end

	local propagationWeight = self.attributeCache:Get(instance, ATTRIBUTES.disturbancePropagationWeight, nil)
	if typeof(propagationWeight) == "number" then
		config.propagationWeight = propagationWeight
	end

	local velocityInfluence = self.attributeCache:Get(instance, ATTRIBUTES.disturbanceVelocityInfluence, nil)
	if typeof(velocityInfluence) == "number" then
		config.velocityInfluence = velocityInfluence
	end

	return config
end

function WindFoliage.GetLOD(self: any, distance: number): LODState?
	local controller = self.lodController
	if controller == nil then
		return nil
	end

	local tier = controller:Get(distance * distance, self:GetEferencePosition(), 0)
	if tier ~= nil and not tier.frozen then
		return tier.lodState
	end
	return nil
end

function WindFoliage.GetEferencePosition(_self: any): Vector3
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return camera.CFrame.Position
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer ~= nil and localPlayer.Character ~= nil then
		local characterRoot = GetRootPartFromModel(localPlayer.Character)
		if characterRoot ~= nil then
			return characterRoot.Position
		end
	end

	return ZERO
end

function WindFoliage.RemoveFromBucket(_self: any, _record: FoliageRecord)
	return nil
end

function WindFoliage.InsertActiveDisturbance(self: any, source: DisturbanceSource)
	local index = #self.activeDisturbances + 1
	self.activeDisturbances[index] = source
	if source.trackedInstance ~= nil then
		local trackedRecord = self.trackedDisturbers[source.trackedInstance]
		if trackedRecord ~= nil then
			trackedRecord.sourceIndex = index
		end
	end
end

function WindFoliage.RemoveActiveDisturbanceAt(self: any, index: number)
	local source = self.activeDisturbances[index]
	if source == nil then
		return
	end

	local lastIndex = #self.activeDisturbances
	local lastSource = self.activeDisturbances[lastIndex]
	self.activeDisturbances[lastIndex] = nil
	if index < lastIndex and lastSource ~= nil then
		self.activeDisturbances[index] = lastSource
		if lastSource.trackedInstance ~= nil then
			local trackedRecord = self.trackedDisturbers[lastSource.trackedInstance]
			if trackedRecord ~= nil then
				trackedRecord.sourceIndex = index
			end
		end
	end
end

function WindFoliage.ReleaseDisturbanceAt(self: any, index: number)
	local source = self.activeDisturbances[index]
	if source == nil then
		return
	end
	self:RemoveActiveDisturbanceAt(index)
	self.disturbancePool:Release(source)
end

function WindFoliage.MaybeUnbindAttributes(self: any, instance: Instance)
	if self.runtimeRegistry:Get(instance) ~= nil then
		return
	end
	if self.trackedDisturbers[instance] ~= nil then
		return
	end
	self.attributeCache:Unbind(instance)
end

function WindFoliage.RegisterFoliage(self: any, instanceRaw: any): any
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	local instance = instanceRaw :: Instance
	local existing = self.runtimeRegistry:Get(instance)
	if existing ~= nil then
		return existing
	end
	if not self:ShouldRegisterFoliage(instance) then
		return nil
	end

	self.nextFoliageId += 1
	local config = self:GetFoliageConfig(instance, self.nextFoliageId)
	local entry = self.runtimeRegistry:Register(instance, config)
	if entry == nil then
		return nil
	end

	local entryAny = entry :: any

	entryAny.destroyConnection = instance.Destroying:Connect(function()
		self:UnregisterFoliage(instance)
	end)
	entryAny.attributeDisconnect = self.attributeCache:OnChanged(instance, "*", function(changedInstance, attributeName)
		if typeof(attributeName) ~= "string" then
			return
		end
		if REFRESH_ATTRIBUTE_SET[attributeName] ~= true then
			return
		end
		self:RefreshFoliage(changedInstance)
	end)

	return entry
end

function WindFoliage.UnregisterFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local entry = self.runtimeRegistry:Get(instance)
	if entry == nil then
		return
	end

	local entryAny = entry :: any
	if entryAny.destroyConnection ~= nil then
		entryAny.destroyConnection:Disconnect()
		entryAny.destroyConnection = nil
	end
	if entryAny.attributeDisconnect ~= nil then
		entryAny.attributeDisconnect()
		entryAny.attributeDisconnect = nil
	end

	setAttributeIfChanged(instance, RUNTIME_ATTRIBUTE_LOD, nil)
	setAttributeIfChanged(instance, RUNTIME_ATTRIBUTE_WRITES, nil)
	self.runtimeRegistry:Unregister(instance)
	self:MaybeUnbindAttributes(instance)
end

function WindFoliage.RefreshFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local shouldRegister = self:ShouldRegisterFoliage(instance)
	if not shouldRegister then
		self:UnregisterFoliage(instance)
		return
	end

	if self.runtimeRegistry:Get(instance) ~= nil then
		self:UnregisterFoliage(instance)
	end
	self:RegisterFoliage(instance)
end

function WindFoliage.UpdateTrackedSource(self: any, record: TrackedDisturberRecord, dt: number)
	local instance = record.instance
	if instance.Parent == nil then
		self:UntrackDisturber(instance)
		return
	end

	if record.kind ~= "player" and not self:ShouldTrackDisturber(instance) then
		self:UntrackDisturber(instance)
		return
	end

	local position = GetWorldPosition(instance)
	if position == nil then
		self:UntrackDisturber(instance)
		return
	end

	local velocity = GetWorldVelocity(instance, position, record.lastPosition, dt)
	record.lastPosition = position

	local source = record.source
	local config = self:GetDisturberConfig(instance, record.overrideConfig, record.kind)
	local lifetime = math.max(
		clampNumber(config.lifetime, 0.24, 0.01, 10),
		clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5) * 2
	)
	DisturbanceSourceModule.Populate(source, {
		position = position,
		velocity = velocity,
		radius = config.radius,
		strength = config.strength,
		lifetime = lifetime,
		falloffCurve = config.falloffCurve,
		propagationDistance = config.propagationDistance,
		propagationWeight = config.propagationWeight,
		velocityInfluence = config.velocityInfluence,
		trackedInstance = instance,
	}, self.time, lifetime)
end

function WindFoliage.TrackDisturber(
	self: any,
	instanceRaw: any,
	overrideConfigRaw: any?,
	kindRaw: any?
): TrackedDisturberRecord?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	local instance = instanceRaw :: Instance
	local kind = CoerceString(kindRaw, "tagged")
	local existing = self.trackedDisturbers[instance]
	if existing ~= nil then
		if typeof(overrideConfigRaw) == "table" then
			existing.overrideConfig = overrideConfigRaw
		end
		existing.kind = kind
		self:UpdateTrackedSource(
			existing,
			math.max(1 / 60, clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 10))
		)
		return self.trackedDisturbers[instance]
	end

	if kind ~= "player" and not self:ShouldTrackDisturber(instance) then
		return nil
	end

	local position = GetWorldPosition(instance)
	if position == nil then
		return nil
	end

	self.attributeCache:Bind(instance)
	local source = self.disturbancePool:Acquire()
	self.nextDisturbanceId += 1
	source.id = self.nextDisturbanceId

	local record: TrackedDisturberRecord = {
		instance = instance,
		source = source,
		sourceIndex = 0,
		lastPosition = position,
		overrideConfig = if typeof(overrideConfigRaw) == "table" then overrideConfigRaw else nil,
		kind = kind,
		destroyConnection = nil,
	}

	record.destroyConnection = instance.Destroying:Connect(function()
		self:UntrackDisturber(instance)
	end)

	self.trackedDisturbers[instance] = record
	self:InsertActiveDisturbance(source)
	self:UpdateTrackedSource(record, math.max(1 / 60, clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 10)))

	return record
end

function WindFoliage.UntrackDisturber(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local record = self.trackedDisturbers[instance]
	if record == nil then
		return
	end

	self.trackedDisturbers[instance] = nil
	if record.destroyConnection ~= nil then
		record.destroyConnection:Disconnect()
		record.destroyConnection = nil
	end
	if record.sourceIndex > 0 then
		self:ReleaseDisturbanceAt(record.sourceIndex)
	end

	self:MaybeUnbindAttributes(instance)
end

function WindFoliage.AddDisturbance(self: any, paramsRaw: any): number?
	local params = if typeof(paramsRaw) == "table" then paramsRaw else {} :: any
	local position = if typeof(params.position) == "Vector3" then params.position else nil
	if position == nil then
		return nil
	end

	local source = self.disturbancePool:Acquire()
	self.nextDisturbanceId += 1
	source.id = self.nextDisturbanceId
	DisturbanceSourceModule.Populate(source, params, self.time, params.lifetime)
	self:InsertActiveDisturbance(source)
	return source.id
end

function WindFoliage.ApplyDisturbanceSource(self: any, source: DisturbanceSource, pulseDt: number)
	local queryRadius = source.radius + source.propagationDistance
	if queryRadius <= 0 then
		return
	end

	local records = self.runtimeRegistry:QueryRadius(source.position, queryRadius)
	local updateManager = self.updateManager
	local maxInteractiveTrees = updateManager.maxInteractiveTrees
	local applied = 0
	for _, entry in records do
		if entry ~= nil then
			local impulse = DisturbanceSourceModule.ComputeImpulse(source, entry.rootPosition)
			if impulse.Magnitude > 1e-5 then
				local pulseScale = math.clamp(pulseDt * 8, 0.25, 0.65)
				updateManager:ApplyInteractionImpulse(entry, impulse * pulseScale, source.position)
				applied += 1
				if applied >= maxInteractiveTrees then
					break
				end
			end
		end
	end
end

function WindFoliage.ApplyGlobalImpulse(self: any, paramsRaw: any): number
	local params = if typeof(paramsRaw) == "table" then paramsRaw else {} :: any
	local directionRaw = params.direction
	local direction = if typeof(directionRaw) == "Vector3" then Vec.FlattenY(directionRaw) else Vector3.xAxis
	if direction.Magnitude <= 1e-5 then
		direction = Vector3.xAxis
	else
		direction = direction.Unit
	end

	local strength = clampNumber(params.strength, 7, 0, 100)
	local origin = if typeof(params.origin) == "Vector3" then params.origin else nil
	local radius = if typeof(params.radius) == "number" then math.max(0, params.radius) else 0
	local maxTrees = math.max(1, math.floor(clampNumber(params.maxTrees, self.updateManager.maxActiveTrees, 1, 4096)))
	local applied = 0

	for _, entry in self.runtimeRegistry.entries do
		if entry == nil then
			continue
		end

		local falloff = 1
		if origin ~= nil and radius > 0 then
			local distance = (entry.rootPosition - origin).Magnitude
			if distance >= radius then
				continue
			end
			falloff = 1 - math.clamp(distance / radius, 0, 1)
		end

		local phase = math.sin(entry.phaseOffset + self.time * 9.17)
		local side = Vector3.new(-direction.Z, 0, direction.X)
		local impulseDirection = direction + side * phase * 0.28
		if impulseDirection.Magnitude <= 1e-5 then
			impulseDirection = direction
		else
			impulseDirection = impulseDirection.Unit
		end

		local impulseStrength = strength * falloff * (0.78 + math.abs(phase) * 0.32) * entry.amplitudeScale
		self.updateManager:ApplyInteractionImpulse(
			entry,
			impulseDirection * impulseStrength,
			origin or entry.rootPosition
		)
		applied += 1
		if applied >= maxTrees then
			break
		end
	end

	return applied
end

function WindFoliage.PulseDisturbances(self: any, pulseDt: number)
	for index = #self.activeDisturbances, 1, -1 do
		local source = self.activeDisturbances[index]
		if source == nil then
			continue
		end
		if DisturbanceSourceModule.IsExpired(source, self.time) then
			if source.trackedInstance ~= nil and self.trackedDisturbers[source.trackedInstance] ~= nil then
				source.expiresAt = self.time + clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5) * 2
				continue
			end
			self:ReleaseDisturbanceAt(index)
			continue
		end
		self:ApplyDisturbanceSource(source, pulseDt)
	end
end

function WindFoliage.RefreshBucketSamples(_self: any, _bucketIndex: number, _referencePosition: Vector3)
	return nil
end

function WindFoliage.StepActiveFoliage(_self: any, _dt: number)
	return nil
end

function WindFoliage.RefreshTrackedDisturbers(self: any, refreshDt: number)
	local records = self.bufferPool:AcquireArray()
	for _, record in self.trackedDisturbers do
		records[#records + 1] = record
	end
	for _, record in records do
		if self.trackedDisturbers[record.instance] ~= nil then
			self:UpdateTrackedSource(record, refreshDt)
		end
	end
	self.bufferPool:ReleaseArray(records)
end

function WindFoliage.OnFixedStep(self: any, dt: number)
	if self.destroyed then
		return
	end

	self.time += dt
	self.attributeCache:Update(dt)

	self.trackedRefreshAccumulator += dt
	local trackedRefreshInterval = clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5)
	while self.trackedRefreshAccumulator >= trackedRefreshInterval do
		self.trackedRefreshAccumulator -= trackedRefreshInterval
		self:RefreshTrackedDisturbers(trackedRefreshInterval)
	end

	self.disturbanceAccumulator += dt
	local disturbancePulseInterval = clampNumber(self.config.disturbancePulseInterval, 0.05, 0.01, 1)
	while self.disturbanceAccumulator >= disturbancePulseInterval do
		self.disturbanceAccumulator -= disturbancePulseInterval
		self:PulseDisturbances(disturbancePulseInterval)
	end

	self.poolShrinkAccumulator += dt
	local poolShrinkInterval = clampNumber(self.config.poolShrinkInterval, 2.5, 0.1, 60)
	if self.poolShrinkAccumulator >= poolShrinkInterval then
		self.poolShrinkAccumulator = 0
		self.disturbancePool:SoftShrink(clampNumber(self.config.maxPoolShrinkPerSweep, 12, 0, 128))
	end

	self.updateManager:Update(self.time + self.timeOffset, dt, self:GetEferencePosition())
end

function WindFoliage.TrackPlayer(self: any, player: Player)
	if self.playerTracks[player] ~= nil then
		return
	end

	local janitor = Janitor.new()
	local record: PlayerTrackRecord = {
		janitor = janitor,
		character = nil,
	}
	self.playerTracks[player] = record

	local function bindCharacter(character: Model)
		record.character = character
		self:TrackDisturber(character, nil, "player")
	end

	local function unbindCharacter(character: Model)
		if record.character == character then
			record.character = nil
		end
		self:UntrackDisturber(character)
	end

	janitor:GiveChore(player.CharacterAdded:Connect(bindCharacter))
	if typeof((player :: any).CharacterRemoving) == "RBXScriptSignal" then
		janitor:GiveChore((player :: any).CharacterRemoving:Connect(unbindCharacter))
	end
	janitor:GiveChore(function()
		if record.character ~= nil then
			self:UntrackDisturber(record.character)
		end
	end)

	if player.Character ~= nil then
		bindCharacter(player.Character)
	end
end

function WindFoliage.UntrackPlayer(self: any, player: Player)
	local record = self.playerTracks[player]
	if record == nil then
		return
	end
	self.playerTracks[player] = nil
	record.janitor:Destroy()
end

function WindFoliage.ConsiderDescendant(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance

	if self:ShouldRegisterFoliage(instance) then
		self:RegisterFoliage(instance)
	end
	if self:ShouldTrackDisturber(instance) then
		self:TrackDisturber(instance)
	end
end

function WindFoliage.CleanupDescendant(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	if self.runtimeRegistry:Get(instance) ~= nil then
		self:UnregisterFoliage(instance)
	end
	if self.trackedDisturbers[instance] ~= nil then
		self:UntrackDisturber(instance)
	end
end

function WindFoliage.Init(self: any)
	if self.initialized then
		return self
	end
	self.initialized = true
	self.destroyed = false

	local janitor = self.janitor :: JanitorClass
	local foliageTag = CoerceString(self.config.foliageTag, DEFAULT_FOLIAGE_TAG)
	local disturberTag = CoerceString(self.config.disturberTag, DEFAULT_DISTURBER_TAG)

	janitor:GiveChore(function()
		self.tagQuery:Destroy()
	end)
	janitor:GiveChore(function()
		self.attributeCache:Destroy()
	end)
	janitor:GiveChore(function()
		self.disturbancePool:Destroy()
	end)

	if self.config.observeTaggedInstances ~= false then
		janitor:GiveChore(self.tagQuery:ObserveTag(foliageTag, function(instance: Instance)
			self:RegisterFoliage(instance)
		end, function(instance: Instance)
			if self:ShouldRegisterFoliage(instance) then
				self:RefreshFoliage(instance)
			else
				self:UnregisterFoliage(instance)
			end
		end))

		janitor:GiveChore(self.tagQuery:ObserveTag(disturberTag, function(instance: Instance)
			self:TrackDisturber(instance)
		end, function(instance: Instance)
			if self:ShouldTrackDisturber(instance) then
				self:TrackDisturber(instance)
			else
				self:UntrackDisturber(instance)
			end
		end))

		janitor:GiveChore(Workspace.DescendantAdded:Connect(function(instance: Instance)
			self:ConsiderDescendant(instance)
		end))
		janitor:GiveChore(Workspace.DescendantRemoving:Connect(function(instance: Instance)
			self:CleanupDescendant(instance)
		end))
	end

	if self.config.autoTrackPlayers ~= false then
		janitor:GiveChore(Players.PlayerAdded:Connect(function(player: Player)
			self:TrackPlayer(player)
		end))
		janitor:GiveChore(Players.PlayerRemoving:Connect(function(player: Player)
			self:UntrackPlayer(player)
		end))
		for _, player in Players:GetPlayers() do
			self:TrackPlayer(player)
		end
	end

	if self.config.observeTaggedInstances ~= false then
		for _, descendant in Workspace:GetDescendants() do
			self:ConsiderDescendant(descendant)
		end
	end

	self.schedulerToken = self.tickScheduler:ScheduleFixed(
		function(dt)
			self:OnFixedStep(dt)
		end,
		1,
		{
			group = self.schedulerGroup,
			priority = TickSchedulerModule.Priority.LOW,
		}
	)
	janitor:GiveChore(function()
		if self.schedulerToken ~= nil then
			self.schedulerToken:Cancel()
			self.schedulerToken = nil
		end
	end)

	return self
end

function WindFoliage.GetStats(self: any): { [string]: number }
	local trackedCount = 0
	for _ in self.trackedDisturbers do
		trackedCount += 1
	end
	local runtimeStats = self.updateManager:GetStats()

	return {
		registeredFoliage = runtimeStats.registeredTrees,
		activeAnimatedTrees = runtimeStats.activeAnimatedTrees,
		activeDisturbances = #self.activeDisturbances,
		trackedDisturbers = trackedCount,
		nearTrees = runtimeStats.nearTrees,
		midTrees = runtimeStats.midTrees,
		farTrees = runtimeStats.farTrees,
		frozenTrees = runtimeStats.frozenTrees,
		culledTrees = runtimeStats.culledTrees,
		transformWrites = runtimeStats.transformWrites,
		inspectedTrees = runtimeStats.inspectedTrees,
		averageUpdateCostMs = runtimeStats.averageUpdateCostMs,
		time = self.time,
	}
end

function WindFoliage.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true

	local foliageInstances = {}
	for _, entry in self.runtimeRegistry.entries do
		foliageInstances[#foliageInstances + 1] = entry.instance
	end
	for _, instance in foliageInstances do
		self:UnregisterFoliage(instance)
	end

	local trackedInstances = {}
	for instance in self.trackedDisturbers do
		trackedInstances[#trackedInstances + 1] = instance
	end
	for _, instance in trackedInstances do
		self:UntrackDisturber(instance)
	end

	local trackedPlayers = {}
	for player in self.playerTracks do
		trackedPlayers[#trackedPlayers + 1] = player
	end
	for _, player in trackedPlayers do
		self:UntrackPlayer(player)
	end

	if self.janitor ~= nil then
		(self.janitor :: JanitorClass):Destroy()
	end
	table.clear(self.trackedDisturbers)
	table.clear(self.playerTracks)
	table.clear(self.activeDisturbances)
	self.runtimeRegistry:Destroy()
	self.bufferPool:Destroy()
end

WindFoliage.Tags = {
	Foliage = DEFAULT_FOLIAGE_TAG,
	Disturber = DEFAULT_DISTURBER_TAG,
}

WindFoliage.Attributes = ATTRIBUTES
WindFoliage.DefaultConfig = DEFAULT_CONFIG
WindFoliage.DefaultPresets = DEFAULT_PRESETS
WindFoliage.WindField = WindField
WindFoliage.FoliageInstance = FoliageInstance
WindFoliage.DisturbanceSource = DisturbanceSourceModule
WindFoliage.BufferPool = BufferPool
WindFoliage.LODController = LODController
WindFoliage.TreeRuntimeRegistry = TreeRuntimeRegistry
WindFoliage.FoliageUpdateManager = FoliageUpdateManager
return WindFoliage
