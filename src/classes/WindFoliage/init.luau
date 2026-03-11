--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local AttributeCache = require(ReplicatedStorage.Shared.Modules.Core.AttributeCache)
local DeterministicRNG = require(ReplicatedStorage.Shared.Modules.Core.DeterministicRNG)
local ObjectPool = require(ReplicatedStorage.Shared.Modules.Core.ObjectPool)
local SpatialHashGrid = require(ReplicatedStorage.Shared.Modules.Core.SpatialHashGrid)
local TagQuery = require(ReplicatedStorage.Shared.Modules.Core.TagQuery)
local TickSchedulerModule = require(ReplicatedStorage.Shared.Modules.Core.TickScheduler)

local DisturbanceSourceModule = require(script.DisturbanceSource)
local FoliageInstance = require(script.FoliageInstance)
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

function WindFoliage.new(configRaw: Config?): any
	local config = mergeTables(DEFAULT_CONFIG, configRaw)
	local bucketCount = math.max(1, math.floor(clampNumber(config.bucketCount, DEFAULT_CONFIG.bucketCount, 1, 32)))
	local tickScheduler = (config :: any).tickScheduler
	if tickScheduler == nil then
		error("WindFoliage.new requires a tickScheduler")
	end

	local lodConfig = mergeTables(DEFAULT_CONFIG.lod, config.lod)
	local self = setmetatable({
		config = config,
		tickScheduler = tickScheduler :: TickScheduler,
		janitor = Janitor.new(),
		attributeCache = AttributeCache.new(),
		tagQuery = TagQuery.new(CollectionService),
		windField = WindField.new(config.windField),
		foliageGrid = SpatialHashGrid.new({
			cellSize = clampNumber(config.gridCellSize, DEFAULT_CONFIG.gridCellSize, 1, 2048),
			cellsPerChunk = 4,
			deterministicQueries = true,
		}),
		disturbancePool = ObjectPool.new(function()
			return DisturbanceSourceModule.createTemplate()
		end, {
			expandBy = 16,
			minAvailable = 4,
			maxAvailable = 512,
			reset = DisturbanceSourceModule.reset,
		}),
		foliageByInstance = {} :: { [Instance]: FoliageRecord },
		foliageBuckets = table.create(bucketCount),
		trackedDisturbers = {} :: { [Instance]: TrackedDisturberRecord },
		activeDisturbances = {} :: { DisturbanceSource },
		playerTracks = {} :: { [Player]: PlayerTrackRecord },
		nextFoliageId = 0,
		nextDisturbanceId = 0,
		bucketCount = bucketCount,
		bucketCursor = 0,
		time = 0,
		timeOffset = getServerAlignedTime(),
		trackedRefreshAccumulator = 0,
		disturbanceAccumulator = 0,
		poolShrinkAccumulator = 0,
		queryBuffer = {} :: { any },
		schedulerToken = nil :: CancellationToken?,
		schedulerGroup = ("windFoliage_%s"):format(tostring(math.floor(os.clock() * 1000))),
		lodStates = {
			near = {
				level = "Near",
				windScale = 1,
				detailScale = 1,
				disturbanceScale = 1,
				updateInterval = clampNumber(lodConfig.nearUpdateInterval, 0.05, 0.01, 1),
			} :: LODState,
			mid = {
				level = "Mid",
				windScale = 0.82,
				detailScale = 0.42,
				disturbanceScale = 0.42,
				updateInterval = clampNumber(lodConfig.midUpdateInterval, 0.12, 0.02, 2),
			} :: LODState,
			far = {
				level = "Far",
				windScale = 0.56,
				detailScale = 0.1,
				disturbanceScale = 0,
				updateInterval = clampNumber(lodConfig.farUpdateInterval, 0.32, 0.04, 4),
			} :: LODState,
		},
		lodDistances = {
			near = clampNumber(lodConfig.nearDistance, 54, 0, 5000),
			mid = clampNumber(lodConfig.midDistance, 118, 0, 5000),
			far = clampNumber(lodConfig.farDistance, 190, 0, 5000),
			cull = clampNumber(lodConfig.cullDistance, 280, 0, 10000),
		},
		initialized = false,
		destroyed = false,
	}, WindFoliage)

	for index = 1, bucketCount do
		self.foliageBuckets[index] = {}
	end

	return self
end

function WindFoliage.resolvePreset(self: any, presetNameRaw: any): { [string]: any }
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

function WindFoliage.resolveFoliageConfig(self: any, instance: Instance, id: number): { [string]: any }
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

function WindFoliage.shouldRegisterFoliage(self: any, instance: Instance): boolean
	if not canBeFoliageRoot(instance) then
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

function WindFoliage.shouldTrackDisturber(self: any, instance: Instance): boolean
	if not canBeDisturber(instance) then
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

function WindFoliage.resolveDisturberConfig(self: any, instance: Instance, overrideConfigRaw: any, kind: string): { [string]: any }
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

function WindFoliage.resolveLOD(self: any, distance: number): LODState?
	if distance <= self.lodDistances.near then
		return self.lodStates.near
	end
	if distance <= self.lodDistances.mid then
		return self.lodStates.mid
	end
	if distance <= self.lodDistances.far then
		return self.lodStates.far
	end
	if distance <= self.lodDistances.cull then
		return self.lodStates.far
	end
	return nil
end

function WindFoliage.resolveReferencePosition(self: any): Vector3
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

function WindFoliage.removeFromBucket(self: any, record: FoliageRecord)
	local bucket = self.foliageBuckets[record.bucketIndex]
	local slot = record.bucketSlot
	local lastRecord = bucket[#bucket]
	bucket[#bucket] = nil
	record.bucketSlot = 0
	if lastRecord ~= nil and lastRecord ~= record and slot >= 1 and slot <= #bucket + 1 then
		bucket[slot] = lastRecord
		lastRecord.bucketSlot = slot
	end
end

function WindFoliage.insertActiveDisturbance(self: any, source: DisturbanceSource)
	local index = #self.activeDisturbances + 1
	self.activeDisturbances[index] = source
	if source.trackedInstance ~= nil then
		local trackedRecord = self.trackedDisturbers[source.trackedInstance]
		if trackedRecord ~= nil then
			trackedRecord.sourceIndex = index
		end
	end
end

function WindFoliage.removeActiveDisturbanceAt(self: any, index: number)
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

function WindFoliage.releaseDisturbanceAt(self: any, index: number)
	local source = self.activeDisturbances[index]
	if source == nil then
		return
	end
	self:removeActiveDisturbanceAt(index)
	self.disturbancePool:release(source)
end

function WindFoliage.maybeUnbindAttributes(self: any, instance: Instance)
	if self.foliageByInstance[instance] ~= nil then
		return
	end
	if self.trackedDisturbers[instance] ~= nil then
		return
	end
	self.attributeCache:unbind(instance)
end

function WindFoliage.registerFoliage(self: any, instanceRaw: any): FoliageRecord?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	local instance = instanceRaw :: Instance
	if self.foliageByInstance[instance] ~= nil then
		return self.foliageByInstance[instance]
	end
	if not self:shouldRegisterFoliage(instance) then
		return nil
	end

	self.nextFoliageId += 1
	local config = self:resolveFoliageConfig(instance, self.nextFoliageId)
	local foliage = FoliageInstance.new(instance, config)
	if foliage == nil then
		return nil
	end

	local bucketIndex = config.bucketIndex
	local record: FoliageRecord = {
		instance = instance,
		foliage = foliage,
		id = config.id,
		bucketIndex = bucketIndex,
		bucketSlot = #self.foliageBuckets[bucketIndex] + 1,
		destroyConnection = nil,
		attributeDisconnect = nil,
	}

	record.destroyConnection = instance.Destroying:Connect(function()
		self:unregisterFoliage(instance)
	end)
	record.attributeDisconnect = self.attributeCache:onChanged(instance, "*", function(changedInstance, attributeName)
		if typeof(attributeName) ~= "string" then
			return
		end
		if string.find(attributeName, "WindFoliage", 1, true) ~= 1 then
			return
		end
		self:refreshFoliage(changedInstance)
	end)

	self.foliageByInstance[instance] = record
	self.foliageBuckets[bucketIndex][record.bucketSlot] = record

	local rootPosition = foliage:getRootPosition()
	self.foliageGrid:insert(record.id, rootPosition.X, rootPosition.Y, rootPosition.Z, foliage)

	return record
end

function WindFoliage.unregisterFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local record = self.foliageByInstance[instance]
	if record == nil then
		return
	end

	self.foliageByInstance[instance] = nil
	self.foliageGrid:remove(record.id)
	self:removeFromBucket(record)

	if record.destroyConnection ~= nil then
		record.destroyConnection:Disconnect()
		record.destroyConnection = nil
	end
	if record.attributeDisconnect ~= nil then
		record.attributeDisconnect()
		record.attributeDisconnect = nil
	end

	record.foliage:destroy()
	self:maybeUnbindAttributes(instance)
end

function WindFoliage.refreshFoliage(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	local shouldRegister = self:shouldRegisterFoliage(instance)
	if not shouldRegister then
		self:unregisterFoliage(instance)
		return
	end

	if self.foliageByInstance[instance] ~= nil then
		self:unregisterFoliage(instance)
	end
	self:registerFoliage(instance)
end

function WindFoliage.updateTrackedSource(self: any, record: TrackedDisturberRecord, dt: number)
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

function WindFoliage.trackDisturber(self: any, instanceRaw: any, overrideConfigRaw: any?, kindRaw: any?): TrackedDisturberRecord?
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

function WindFoliage.untrackDisturber(self: any, instanceRaw: any)
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

function WindFoliage.addDisturbance(self: any, paramsRaw: any): number?
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

function WindFoliage.applyDisturbanceSource(self: any, source: DisturbanceSource, pulseDt: number)
	local queryRadius = source.radius + source.propagationDistance
	if queryRadius <= 0 then
		return
	end

	local records =
		self.foliageGrid:queryRadius(source.position.X, source.position.Y, source.position.Z, queryRadius, self.queryBuffer)
	for _, queryRecord in records do
		local foliage = queryRecord.payload :: FoliageObject
		if foliage ~= nil then
			local impulse = DisturbanceSourceModule.computeImpulse(source, foliage:getRootPosition())
			if impulse.Magnitude > 1e-5 then
				foliage:addDisturbance(impulse * pulseDt, source.position)
			end
		end
	end
end

function WindFoliage.pulseDisturbances(self: any, pulseDt: number)
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

function WindFoliage.processBucket(self: any, bucketIndex: number)
	local bucket = self.foliageBuckets[bucketIndex]
	if bucket == nil or #bucket <= 0 then
		return
	end

	local referencePosition = self:resolveReferencePosition()
	for index = #bucket, 1, -1 do
		local record = bucket[index]
		if record == nil then
			continue
		end

		local instance = record.instance
		if instance.Parent == nil or record.foliage.destroyed then
			self:unregisterFoliage(instance)
			continue
		end

		local foliage = record.foliage
		local distance = (foliage:getRootPosition() - referencePosition).Magnitude
		local lodState = self:resolveLOD(distance)
		if lodState == nil then
			continue
		end

		local elapsed = self.time - foliage.lastUpdateTime
		if foliage.lastUpdateTime <= 0 then
			elapsed = lodState.updateInterval
		end
		if elapsed < lodState.updateInterval then
			continue
		end

		local windSample: WindSample =
			self.windField:sample(foliage:getRootPosition(), self.time + self.timeOffset, foliage.phaseOffset, foliage.amplitudeScale)
		foliage:step(self.time, elapsed, windSample, lodState)
	end
end

function WindFoliage.refreshTrackedDisturbers(self: any, refreshDt: number)
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

function WindFoliage.onFixedStep(self: any, dt: number)
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

	self.bucketCursor = (self.bucketCursor % self.bucketCount) + 1
	self:processBucket(self.bucketCursor)
end

function WindFoliage.trackPlayer(self: any, player: Player)
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

function WindFoliage.untrackPlayer(self: any, player: Player)
	local record = self.playerTracks[player]
	if record == nil then
		return
	end
	self.playerTracks[player] = nil
	record.janitor:Destroy()
end

function WindFoliage.considerDescendant(self: any, instanceRaw: any)
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

function WindFoliage.cleanupDescendant(self: any, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local instance = instanceRaw :: Instance
	if self.foliageByInstance[instance] ~= nil then
		self:unregisterFoliage(instance)
	end
	if self.trackedDisturbers[instance] ~= nil then
		self:untrackDisturber(instance)
	end
end

function WindFoliage.init(self: any)
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

function WindFoliage.getStats(self: any): { [string]: number }
	local trackedCount = 0
	for _ in self.trackedDisturbers do
		trackedCount += 1
	end

	return {
		registeredFoliage = self.foliageGrid:count(),
		activeDisturbances = #self.activeDisturbances,
		trackedDisturbers = trackedCount,
		bucketCursor = self.bucketCursor,
		time = self.time,
	}
end

function WindFoliage.destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true

	local foliageInstances = {}
	for instance in self.foliageByInstance do
		foliageInstances[#foliageInstances + 1] = instance
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
	table.clear(self.foliageByInstance)
	table.clear(self.trackedDisturbers)
	table.clear(self.playerTracks)
	for _, bucket in self.foliageBuckets do
		table.clear(bucket)
	end
	table.clear(self.activeDisturbances)
	self.foliageGrid:clear()
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

return WindFoliage
