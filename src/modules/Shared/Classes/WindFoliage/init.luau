--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local AttributeCache = require(script:FindFirstAncestor("game").Shared.Modules.Core.AttributeCache)
local DeterministicRNG = require(script:FindFirstAncestor("game").Shared.Modules.Core.DeterministicRNG)
local ObjectPool = require(script:FindFirstAncestor("game").Shared.Modules.Core.ObjectPool)
local TagQuery = require(script:FindFirstAncestor("game").Shared.Modules.Core.TagQuery)
local TickSchedulerModule = require(script:FindFirstAncestor("game").Shared.Modules.Core.TickScheduler)

local BufferPool = require(script.BufferPool)
local DisturbanceSourceModule = require(script.DisturbanceSource)
local FoliageUpdateManager = require(script.FoliageUpdateManager)
local FoliageInstance = require(script.FoliageInstance)
local LODController = require(script.LODController)
local TreeRuntimeRegistry = require(script.TreeRuntimeRegistry)
local WindField = require(script.WindField)

type WindSample = WindField.WindSample
type DisturbanceSource = DisturbanceSourceModule.DisturbanceSource
type FoliageObject = FoliageInstance.FoliageInstance

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

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
local DEFAULT_FOLIAGE_TAG = "WindFoliage"
local DEFAULT_DISTURBER_TAG = "WindFoliageDisturber"
local WORLD_ANIMATOR_RUNTIME_FOLDER_NAME = "WorldAnimatorRuntime"
local TREE_GRAPH_ATTRIBUTE = "WindFoliageTreeGraph"
local RUNTIME_ATTRIBUTE_LOD = "WindRuntimeLOD"
local RUNTIME_ATTRIBUTE_WRITES = "WindRuntimeWrites"

local ATTRIBUTES = {
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
		bendStiffness = 8.5,
		damping = 6.3,
		maxBendAngle = 10,
		heightMultiplier = 0.78,
		swayAmplitude = 0.62,
		gustSensitivity = 0.9,
		recoverySpeed = 3.2,
		disturbanceSensitivity = 0.72,
		detailAmplitude = 0.12,
		translationWeight = 0.08,
		yawWeight = 0.1,
		tipBias = 1.9,
		pivotMode = "Attachment",
	},
	BranchHeavy = {
		motionStyle = "Branch",
		bendStiffness = 5.6,
		damping = 4.9,
		maxBendAngle = 7,
		heightMultiplier = 0.65,
		swayAmplitude = 0.48,
		gustSensitivity = 0.76,
		recoverySpeed = 2.2,
		disturbanceSensitivity = 0.45,
		detailAmplitude = 0.08,
		translationWeight = 0.05,
		yawWeight = 0.08,
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
		radius = 7.5,
		strength = 2.15,
		lifetime = 0.28,
		falloffCurve = 1.4,
		propagationDistance = 4.2,
		propagationWeight = 0.46,
		velocityInfluence = 0.9,
	},
	disturberDefaults = {
		radius = 8,
		strength = 1.8,
		lifetime = 0.24,
		falloffCurve = 1.5,
		propagationDistance = 3.5,
		propagationWeight = 0.35,
		velocityInfluence = 0.5,
	},
	windField = {
		seed = "AquariaWindField",
		baseDirection = Vector3.new(1, 0, 0.25),
		strengthMultiplier = 1,
		baseStrength = 0.62,
		gustStrength = 0.92,
		detailStrength = 0.2,
		gustSpatialScale = 140,
		gustTimeScale = 0.16,
		detailSpatialScale = 22,
		detailTimeScale = 1.55,
		directionJitterDegrees = 18,
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
		midUpdateInterval = 0.12,
		farUpdateInterval = 0.32,
		frozenUpdateInterval = 0.75,
		maxActiveTrees = 128,
		maxInteractiveTrees = 24,
		maxTransformWritesPerStep = 24000,
		enableSecondaryFlutter = true,
		enableCanopyOnlyFar = false,
		branchCapPerTree = 99999,
		leafClusterCapPerTree = 99999,
		primaryDriverStiffness = 8,
		primaryDriverDamping = 5.5,
		secondaryDriverStiffness = 12,
		secondaryDriverDamping = 6.5,
		interactionDriverStiffness = 7.5,
		interactionDriverDamping = 5.2,
		flutterDriverStiffness = 14,
		flutterDriverDamping = 7.5,
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

local function sanitizeString(valueRaw: any, fallback: string): string
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

local function resolveRootPartFromModel(model: Model): BasePart?
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

local function resolveWorldPosition(instance: Instance): Vector3?
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
		local rootPart = resolveRootPartFromModel(instance)
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

local function resolveWorldVelocity(instance: Instance, currentPosition: Vector3, previousPosition: Vector3, dt: number): Vector3
	if instance:IsA("BasePart") then
		return instance.AssemblyLinearVelocity
	end
	if instance:IsA("Model") then
		local rootPart = resolveRootPartFromModel(instance)
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
		attributeCache = AttributeCache.new(),
		tagQuery = TagQuery.new(CollectionService),
		windField = WindField.new(config.windField),
		bufferPool = BufferPool.new({
			maxAvailable = 32,
		}),
		runtimeRegistry = nil,
		lodController = nil,
		updateManager = nil,
		disturbancePool = ObjectPool.new(function()
			return DisturbanceSourceModule.createTemplate()
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

	self.runtimeRegistry = TreeRuntimeRegistry.new({
		gridCellSize = clampNumber(config.gridCellSize, DEFAULT_CONFIG.gridCellSize, 1, 2048),
		octreeMaxDepth = clampNumber(config.octreeMaxDepth, DEFAULT_CONFIG.octreeMaxDepth, 1, 12),
	})
	self.lodController = LODController.new({
		lod = lodConfig,
		runtime = config.runtime,
	})
	self.updateManager = FoliageUpdateManager.new(config, self.runtimeRegistry, self.windField, self.lodController, self.bufferPool)

	return self
end

function WindFoliage.ResolvePreset(self: any, presetNameRaw: any): { [string]: any }
	local presets = if typeof(self.config.presets) == "table" then self.config.presets else DEFAULT_PRESETS
	local fallbackPresetName = sanitizeString(self.config.fallbackPreset, "GrassLight")
	local presetName = sanitizeString(presetNameRaw, fallbackPresetName)
	local preset = presets[presetName]
	if typeof(preset) ~= "table" then
		preset = presets[fallbackPresetName]
	end
	if typeof(preset) ~= "table" then
		preset = DEFAULT_PRESETS.GrassLight
	end
	return mergeTables(preset, nil)
end

function WindFoliage.ResolveFoliageConfig(self: any, instance: Instance, id: number): { [string]: any }
	self.attributeCache:bind(instance)

	local presetName = self.attributeCache:get(instance, ATTRIBUTES.preset, self.config.fallbackPreset)
	local preset = self:resolvePreset(presetName)
	local seed = DeterministicRNG.seedFrom(instance:GetFullName())
	local bucketIndex = (seed % self.bucketCount) + 1

	local function overrideNumber(fieldName: string, attributeName: string)
		local value = self.attributeCache:get(instance, attributeName, nil)
		if typeof(value) == "number" then
			preset[fieldName] = value
		end
	end

	local function overrideString(fieldName: string, attributeName: string)
		local value = self.attributeCache:get(instance, attributeName, nil)
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

	local pivotOffset = self.attributeCache:get(instance, ATTRIBUTES.pivotOffset, nil)
	if typeof(pivotOffset) == "Vector3" then
		preset.pivotOffset = pivotOffset
	end

	local boneNames = self.attributeCache:get(instance, ATTRIBUTES.boneNames, nil)
	if typeof(boneNames) == "string" and boneNames ~= "" then
		preset.boneNames = splitCommaSeparatedNames(boneNames)
	end

	preset.id = id
	preset.seed = seed
	preset.bucketIndex = bucketIndex
	preset.presetName = sanitizeString(presetName, self.config.fallbackPreset)

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

	local foliageTag = sanitizeString(self.config.foliageTag, DEFAULT_FOLIAGE_TAG)
	local hasTag = self.tagQuery:hasTag(instance, foliageTag)
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

	local disturberTag = sanitizeString(self.config.disturberTag, DEFAULT_DISTURBER_TAG)
	return self.tagQuery:hasTag(instance, disturberTag)
end

function WindFoliage.ResolveDisturberConfig(self: any, instance: Instance, overrideConfigRaw: any, kind: string): { [string]: any }
	self.attributeCache:bind(instance)

	local baseConfig =
		if kind == "player" and typeof(self.config.playerDisturber) == "table"
			then self.config.playerDisturber
			else self.config.disturberDefaults
	local config = mergeTables(baseConfig, overrideConfigRaw)

	local radius = self.attributeCache:get(instance, ATTRIBUTES.disturbanceRadius, nil)
	if typeof(radius) == "number" then
		config.radius = radius
	end

	local strength = self.attributeCache:get(instance, ATTRIBUTES.disturbanceStrength, nil)
	if typeof(strength) == "number" then
		config.strength = strength
	end

	local lifetime = self.attributeCache:get(instance, ATTRIBUTES.disturbanceLifetime, nil)
	if typeof(lifetime) == "number" then
		config.lifetime = lifetime
	end

	local falloffCurve = self.attributeCache:get(instance, ATTRIBUTES.disturbanceFalloff, nil)
	if typeof(falloffCurve) == "number" then
		config.falloffCurve = falloffCurve
	end

	local propagationDistance = self.attributeCache:get(instance, ATTRIBUTES.disturbancePropagationDistance, nil)
	if typeof(propagationDistance) == "number" then
		config.propagationDistance = propagationDistance
	end

	local propagationWeight = self.attributeCache:get(instance, ATTRIBUTES.disturbancePropagationWeight, nil)
	if typeof(propagationWeight) == "number" then
		config.propagationWeight = propagationWeight
	end

	local velocityInfluence = self.attributeCache:get(instance, ATTRIBUTES.disturbanceVelocityInfluence, nil)
	if typeof(velocityInfluence) == "number" then
		config.velocityInfluence = velocityInfluence
	end

	return config
end

function WindFoliage.ResolveLOD(self: any, distance: number): LODState?
	local controller = self.lodController
	if controller == nil then
		return nil
	end

	local tier = controller:resolve(distance * distance, self:resolveReferencePosition(), 0)
	if tier ~= nil and not tier.frozen then
		return tier.lodState
	end
	return nil
end

function WindFoliage.ResolveReferencePosition(_self: any): Vector3
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		return camera.CFrame.Position
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer ~= nil and localPlayer.Character ~= nil then
		local characterRoot = resolveRootPartFromModel(localPlayer.Character)
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
	self:removeActiveDisturbanceAt(index)
	self.disturbancePool:release(source)
end

function WindFoliage.MaybeUnbindAttributes(self: any, instance: Instance)
	if self.runtimeRegistry:get(instance) ~= nil then
		return
	end
	if self.trackedDisturbers[instance] ~= nil then
		return
	end
	self.attributeCache:unbind(instance)
end

function WindFoliage.RegisterFoliage(self: any, instanceRaw: any): any
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	local instance = instanceRaw :: Instance
	local existing = self.runtimeRegistry:get(instance)
	if existing ~= nil then
		return existing
	end
	if not self:shouldRegisterFoliage(instance) then
		return nil
	end

	self.nextFoliageId += 1
	local config = self:resolveFoliageConfig(instance, self.nextFoliageId)
	local entry = self.runtimeRegistry:register(instance, config)
	if entry == nil then
		return nil
	end

	local entryAny = entry :: any

	entryAny.destroyConnection = instance.Destroying:Connect(function()
		self:unregisterFoliage(instance)
	end)
	entryAny.attributeDisconnect = self.attributeCache:onChanged(instance, "*", function(changedInstance, attributeName)
		if typeof(attributeName) ~= "string" then
			return
		end
		if REFRESH_ATTRIBUTE_SET[attributeName] ~= true then
			return
		end
		self:refreshFoliage(changedInstance)
	end)

	return entry
end

function WindFoliage.UnregisterFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local entry = self.runtimeRegistry:get(instance)
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
	self.runtimeRegistry:unregister(instance)
	self:maybeUnbindAttributes(instance)
end

function WindFoliage.RefreshFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local shouldRegister = self:shouldRegisterFoliage(instance)
	if not shouldRegister then
		self:unregisterFoliage(instance)
		return
	end

	if self.runtimeRegistry:get(instance) ~= nil then
		self:unregisterFoliage(instance)
	end
	self:registerFoliage(instance)
end

function WindFoliage.UpdateTrackedSource(self: any, record: TrackedDisturberRecord, dt: number)
	local instance = record.instance
	if instance.Parent == nil then
		self:untrackDisturber(instance)
		return
	end

	if record.kind ~= "player" and not self:shouldTrackDisturber(instance) then
		self:untrackDisturber(instance)
		return
	end

	local position = resolveWorldPosition(instance)
	if position == nil then
		self:untrackDisturber(instance)
		return
	end

	local velocity = resolveWorldVelocity(instance, position, record.lastPosition, dt)
	record.lastPosition = position

	local source = record.source
	local config = self:resolveDisturberConfig(instance, record.overrideConfig, record.kind)
	local lifetime = math.max(
		clampNumber(config.lifetime, 0.24, 0.01, 10),
		clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5) * 2
	)
	DisturbanceSourceModule.populate(source, {
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

function WindFoliage.TrackDisturber(self: any, instanceRaw: any, overrideConfigRaw: any?, kindRaw: any?): TrackedDisturberRecord?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	local instance = instanceRaw :: Instance
	local kind = sanitizeString(kindRaw, "tagged")
	local existing = self.trackedDisturbers[instance]
	if existing ~= nil then
		if typeof(overrideConfigRaw) == "table" then
			existing.overrideConfig = overrideConfigRaw
		end
		existing.kind = kind
		self:updateTrackedSource(existing, math.max(1 / 60, clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 10)))
		return self.trackedDisturbers[instance]
	end

	if kind ~= "player" and not self:shouldTrackDisturber(instance) then
		return nil
	end

	local position = resolveWorldPosition(instance)
	if position == nil then
		return nil
	end

	self.attributeCache:bind(instance)
	local source = self.disturbancePool:acquire()
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
		self:untrackDisturber(instance)
	end)

	self.trackedDisturbers[instance] = record
	self:insertActiveDisturbance(source)
	self:updateTrackedSource(record, math.max(1 / 60, clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 10)))

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
		self:releaseDisturbanceAt(record.sourceIndex)
	end

	self:maybeUnbindAttributes(instance)
end

function WindFoliage.AddDisturbance(self: any, paramsRaw: any): number?
	local params = if typeof(paramsRaw) == "table" then paramsRaw else {}
	local position = if typeof(params.position) == "Vector3" then params.position else nil
	if position == nil then
		return nil
	end

	local source = self.disturbancePool:acquire()
	self.nextDisturbanceId += 1
	source.id = self.nextDisturbanceId
	DisturbanceSourceModule.populate(source, params, self.time, params.lifetime)
	self:insertActiveDisturbance(source)
	return source.id
end

function WindFoliage.ApplyDisturbanceSource(self: any, source: DisturbanceSource, pulseDt: number)
	local queryRadius = source.radius + source.propagationDistance
	if queryRadius <= 0 then
		return
	end

	local records = self.runtimeRegistry:queryRadius(source.position, queryRadius)
	local updateManager = self.updateManager
	local maxInteractiveTrees = updateManager.maxInteractiveTrees
	local applied = 0
	for _, entry in records do
		if entry ~= nil then
			local impulse = DisturbanceSourceModule.computeImpulse(source, entry.rootPosition)
			if impulse.Magnitude > 1e-5 then
				updateManager:applyInteractionImpulse(entry, impulse * pulseDt, source.position)
				applied += 1
				if applied >= maxInteractiveTrees then
					break
				end
			end
		end
	end
end

function WindFoliage.PulseDisturbances(self: any, pulseDt: number)
	for index = #self.activeDisturbances, 1, -1 do
		local source = self.activeDisturbances[index]
		if source == nil then
			continue
		end
		if DisturbanceSourceModule.isExpired(source, self.time) then
			if source.trackedInstance ~= nil and self.trackedDisturbers[source.trackedInstance] ~= nil then
				source.expiresAt = self.time + clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5) * 2
				continue
			end
			self:releaseDisturbanceAt(index)
			continue
		end
		self:applyDisturbanceSource(source, pulseDt)
	end
end

function WindFoliage.RefreshBucketSamples(_self: any, _bucketIndex: number, _referencePosition: Vector3)
	return nil
end

function WindFoliage.StepActiveFoliage(_self: any, _dt: number)
	return nil
end

function WindFoliage.RefreshTrackedDisturbers(self: any, refreshDt: number)
	local records = {}
	for _, record in self.trackedDisturbers do
		records[#records + 1] = record
	end
	for _, record in records do
		if self.trackedDisturbers[record.instance] ~= nil then
			self:updateTrackedSource(record, refreshDt)
		end
	end
end

function WindFoliage.OnFixedStep(self: any, dt: number)
	if self.destroyed then
		return
	end

	self.time += dt
	self.attributeCache:update(dt)

	self.trackedRefreshAccumulator += dt
	local trackedRefreshInterval = clampNumber(self.config.trackedRefreshInterval, 0.08, 0.01, 5)
	while self.trackedRefreshAccumulator >= trackedRefreshInterval do
		self.trackedRefreshAccumulator -= trackedRefreshInterval
		self:refreshTrackedDisturbers(trackedRefreshInterval)
	end

	self.disturbanceAccumulator += dt
	local disturbancePulseInterval = clampNumber(self.config.disturbancePulseInterval, 0.05, 0.01, 1)
	while self.disturbanceAccumulator >= disturbancePulseInterval do
		self.disturbanceAccumulator -= disturbancePulseInterval
		self:pulseDisturbances(disturbancePulseInterval)
	end

	self.poolShrinkAccumulator += dt
	local poolShrinkInterval = clampNumber(self.config.poolShrinkInterval, 2.5, 0.1, 60)
	if self.poolShrinkAccumulator >= poolShrinkInterval then
		self.poolShrinkAccumulator = 0
		self.disturbancePool:softShrink(clampNumber(self.config.maxPoolShrinkPerSweep, 12, 0, 128))
	end

	self.updateManager:update(self.time + self.timeOffset, dt, self:resolveReferencePosition())
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
		self:trackDisturber(character, nil, "player")
	end

	local function unbindCharacter(character: Model)
		if record.character == character then
			record.character = nil
		end
		self:untrackDisturber(character)
	end

	janitor:GiveChore(player.CharacterAdded:Connect(bindCharacter))
	if typeof((player :: any).CharacterRemoving) == "RBXScriptSignal" then
		janitor:GiveChore((player :: any).CharacterRemoving:Connect(unbindCharacter))
	end
	janitor:GiveChore(function()
		if record.character ~= nil then
			self:untrackDisturber(record.character)
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

	if self:shouldRegisterFoliage(instance) then
		self:registerFoliage(instance)
	end
	if self:shouldTrackDisturber(instance) then
		self:trackDisturber(instance)
	end
end

function WindFoliage.CleanupDescendant(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	if self.runtimeRegistry:get(instance) ~= nil then
		self:unregisterFoliage(instance)
	end
	if self.trackedDisturbers[instance] ~= nil then
		self:untrackDisturber(instance)
	end
end

function WindFoliage.Init(self: any)
	if self.initialized then
		return self
	end
	self.initialized = true
	self.destroyed = false

	local janitor = self.janitor :: JanitorClass
	local foliageTag = sanitizeString(self.config.foliageTag, DEFAULT_FOLIAGE_TAG)
	local disturberTag = sanitizeString(self.config.disturberTag, DEFAULT_DISTURBER_TAG)

	janitor:GiveChore(function()
		self.tagQuery:destroy()
	end)
	janitor:GiveChore(function()
		self.attributeCache:destroy()
	end)
	janitor:GiveChore(function()
		self.disturbancePool:destroy()
	end)

	janitor:GiveChore(self.tagQuery:observeTag(foliageTag, function(instance: Instance)
		self:registerFoliage(instance)
	end, function(instance: Instance)
		if self:shouldRegisterFoliage(instance) then
			self:refreshFoliage(instance)
		else
			self:unregisterFoliage(instance)
		end
	end))

	janitor:GiveChore(self.tagQuery:observeTag(disturberTag, function(instance: Instance)
		self:trackDisturber(instance)
	end, function(instance: Instance)
		if self:shouldTrackDisturber(instance) then
			self:trackDisturber(instance)
		else
			self:untrackDisturber(instance)
		end
	end))

	janitor:GiveChore(Workspace.DescendantAdded:Connect(function(instance: Instance)
		self:considerDescendant(instance)
	end))
	janitor:GiveChore(Workspace.DescendantRemoving:Connect(function(instance: Instance)
		self:cleanupDescendant(instance)
	end))

	if self.config.autoTrackPlayers ~= false then
		janitor:GiveChore(Players.PlayerAdded:Connect(function(player: Player)
			self:trackPlayer(player)
		end))
		janitor:GiveChore(Players.PlayerRemoving:Connect(function(player: Player)
			self:untrackPlayer(player)
		end))
		for _, player in Players:GetPlayers() do
			self:trackPlayer(player)
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		self:considerDescendant(descendant)
	end

	self.schedulerToken = self.tickScheduler:scheduleFixed(function(dt)
		self:onFixedStep(dt)
	end, 1, {
		group = self.schedulerGroup,
		priority = TickSchedulerModule.Priority.LOW,
	})
	janitor:GiveChore(function()
		if self.schedulerToken ~= nil then
			self.schedulerToken:cancel()
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
	local runtimeStats = self.updateManager:getStats()

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
		activeRippleDrivers = runtimeStats.activeRippleDrivers,
		transformWrites = runtimeStats.transformWrites,
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
		self:unregisterFoliage(instance)
	end

	local trackedInstances = {}
	for instance in self.trackedDisturbers do
		trackedInstances[#trackedInstances + 1] = instance
	end
	for _, instance in trackedInstances do
		self:untrackDisturber(instance)
	end

	local trackedPlayers = {}
	for player in self.playerTracks do
		trackedPlayers[#trackedPlayers + 1] = player
	end
	for _, player in trackedPlayers do
		self:untrackPlayer(player)
	end

	if self.janitor ~= nil then
		(self.janitor :: JanitorClass):Destroy()
	end
	table.clear(self.trackedDisturbers)
	table.clear(self.playerTracks)
	table.clear(self.activeDisturbances)
	self.runtimeRegistry:destroy()
	self.bufferPool:destroy()
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

WindFoliage.new = WindFoliage.New
WindFoliage.resolvePreset = WindFoliage.ResolvePreset
WindFoliage.resolveFoliageConfig = WindFoliage.ResolveFoliageConfig
WindFoliage.shouldRegisterFoliage = WindFoliage.ShouldRegisterFoliage
WindFoliage.shouldTrackDisturber = WindFoliage.ShouldTrackDisturber
WindFoliage.resolveDisturberConfig = WindFoliage.ResolveDisturberConfig
WindFoliage.resolveLOD = WindFoliage.ResolveLOD
WindFoliage.resolveReferencePosition = WindFoliage.ResolveReferencePosition
WindFoliage.removeFromBucket = WindFoliage.RemoveFromBucket
WindFoliage.insertActiveDisturbance = WindFoliage.InsertActiveDisturbance
WindFoliage.removeActiveDisturbanceAt = WindFoliage.RemoveActiveDisturbanceAt
WindFoliage.releaseDisturbanceAt = WindFoliage.ReleaseDisturbanceAt
WindFoliage.maybeUnbindAttributes = WindFoliage.MaybeUnbindAttributes
WindFoliage.registerFoliage = WindFoliage.RegisterFoliage
WindFoliage.unregisterFoliage = WindFoliage.UnregisterFoliage
WindFoliage.refreshFoliage = WindFoliage.RefreshFoliage
WindFoliage.updateTrackedSource = WindFoliage.UpdateTrackedSource
WindFoliage.trackDisturber = WindFoliage.TrackDisturber
WindFoliage.untrackDisturber = WindFoliage.UntrackDisturber
WindFoliage.addDisturbance = WindFoliage.AddDisturbance
WindFoliage.applyDisturbanceSource = WindFoliage.ApplyDisturbanceSource
WindFoliage.pulseDisturbances = WindFoliage.PulseDisturbances
WindFoliage.refreshBucketSamples = WindFoliage.RefreshBucketSamples
WindFoliage.stepActiveFoliage = WindFoliage.StepActiveFoliage
WindFoliage.refreshTrackedDisturbers = WindFoliage.RefreshTrackedDisturbers
WindFoliage.onFixedStep = WindFoliage.OnFixedStep
WindFoliage.trackPlayer = WindFoliage.TrackPlayer
WindFoliage.untrackPlayer = WindFoliage.UntrackPlayer
WindFoliage.considerDescendant = WindFoliage.ConsiderDescendant
WindFoliage.cleanupDescendant = WindFoliage.CleanupDescendant
WindFoliage.init = WindFoliage.Init
WindFoliage.getStats = WindFoliage.GetStats
WindFoliage.destroy = WindFoliage.Destroy

return WindFoliage
