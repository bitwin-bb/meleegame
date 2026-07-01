local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local FoliageUpdateManager = {}
FoliageUpdateManager.__index = FoliageUpdateManager

local RUNTIME_ATTRIBUTE_LOD = "WindRuntimeLOD"
local RUNTIME_ATTRIBUTE_WRITES = "WindRuntimeWrites"
local WORLD_ANIMATOR_ACTIVE_ATTRIBUTE = "WorldAnimatorAnimating"
local MAX_EFFECTIVE_STEP_DT = 0.1
local MAX_STALE_ELAPSED = 0.75

local function setAttributeIfChanged(instance: Instance, attributeName: string, value: any)
	if instance:GetAttribute(attributeName) == value then
		return
	end
	instance:SetAttribute(attributeName, value)
end

export type FoliageUpdateManager = typeof(setmetatable({} :: any, FoliageUpdateManager))

local ZERO = Vector3.zero

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

local function GetDirectionOrFallback(vector: Vector3, fallback: Vector3): Vector3
	local planar = Vector3.new(vector.X, 0, vector.Z)
	if planar.Magnitude <= 1e-5 then
		local fallbackPlanar = Vector3.new(fallback.X, 0, fallback.Z)
		if fallbackPlanar.Magnitude <= 1e-5 then
			return Vector3.xAxis
		end
		return fallbackPlanar.Unit
	end
	return planar.Unit
end

local function approachNumber(current: number, target: number, responseRate: number, dt: number): number
	local alpha = 1 - math.exp(-math.max(0, responseRate) * dt)
	return current + (target - current) * alpha
end

local function approachVector(current: Vector3, target: Vector3, responseRate: number, dt: number): Vector3
	local alpha = 1 - math.exp(-math.max(0, responseRate) * dt)
	return current:Lerp(target, alpha)
end

local function clampVector(vector: Vector3, maximumMagnitude: number): Vector3
	if maximumMagnitude <= 0 then
		return ZERO
	end
	local magnitude = vector.Magnitude
	if magnitude <= maximumMagnitude then
		return vector
	end
	return vector.Unit * maximumMagnitude
end

local function isInAnimatingChunk(instance: Instance): boolean
	local current: Instance? = instance
	while current ~= nil do
		if current:GetAttribute(WORLD_ANIMATOR_ACTIVE_ATTRIBUTE) == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function resetEntryDrivers(entry: any)
	entry.primarySwayValue = ZERO
	entry.secondarySwayValue = ZERO
	entry.interactionBendValue = ZERO
	entry.canopyFlutterValue = 0

	local Got = entry.windSample
	Got.vector = ZERO
	Got.direction = Vector3.xAxis
	Got.strength = 0
	Got.gustAlpha = 0
	Got.detailAlpha = 0
	Got.detailVector = ZERO
	Got.flutter = 0
end

function FoliageUpdateManager.New(
	configRaw: any?,
	registry: any,
	windField: any,
	lodController: any,
	bufferPool: any
): FoliageUpdateManager
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local runtime = if typeof(config.runtime) == "table" then config.runtime else {} :: any
	local self = setmetatable({
		config = config,
		runtimeConfig = runtime,
		registry = registry,
		windField = windField,
		lodController = lodController,
		bufferPool = bufferPool,
		entryCursor = 0,
		enableSecondaryFlutter = runtime.enableSecondaryFlutter ~= false,
		maxActiveTrees = math.max(1, math.floor(clampNumber(runtime.maxActiveTrees, 128, 1, 4096))),
		maxInteractiveTrees = math.max(1, math.floor(clampNumber(runtime.maxInteractiveTrees, 24, 1, 1024))),
		maxTransformWritesPerStep = math.max(
			1,
			math.floor(clampNumber(runtime.maxTransformWritesPerStep, 24000, 1, 1000000))
		),
		branchCapPerTree = math.max(1, math.floor(clampNumber(runtime.branchCapPerTree, 99999, 1, 999999))),
		leafClusterCapPerTree = math.max(1, math.floor(clampNumber(runtime.leafClusterCapPerTree, 99999, 1, 999999))),
		debugEnabled = if typeof(runtime.debug) == "table" then runtime.debug.enabled == true else false,
		stats = {
			registeredTrees = 0,
			activeAnimatedTrees = 0,
			culledTrees = 0,
			nearTrees = 0,
			midTrees = 0,
			farTrees = 0,
			frozenTrees = 0,
			transformWrites = 0,
			averageUpdateCostMs = 0,
		},
		primaryResponseRate = clampNumber(runtime.primaryDriverResponseRate, 9, 0, 120),
		secondaryResponseRate = clampNumber(runtime.secondaryDriverResponseRate, 12, 0, 120),
		interactionDecayRate = clampNumber(runtime.interactionDriverDecayRate, 4.8, 0, 120),
		flutterResponseRate = clampNumber(runtime.flutterDriverResponseRate, 14, 0, 120),
		maxInteractionBend = clampNumber(runtime.maxInteractionBend, 3.5, 0, 25),
	}, FoliageUpdateManager)

	return self
end

function FoliageUpdateManager.ApplyInteractionImpulse(
	_self: FoliageUpdateManager,
	entry: any,
	impulseWorld: Vector3,
	originWorldRaw: any?
)
	entry.interactionBendValue = clampVector(entry.interactionBendValue + impulseWorld * 0.42, _self.maxInteractionBend)
	entry.foliage:AddDisturbance(impulseWorld * 1.2, originWorldRaw)
end

function FoliageUpdateManager.UpdateEntryDrivers(self: FoliageUpdateManager, entry: any, baseSample: any, dt: number)
	local primaryTarget = Vector3.new(baseSample.vector.X, 0, baseSample.vector.Z)
	local secondaryTarget = if self.enableSecondaryFlutter
		then baseSample.detailVector * baseSample.detailAlpha
		else ZERO

	entry.primarySwayValue = approachVector(entry.primarySwayValue, primaryTarget, self.primaryResponseRate, dt)
	entry.secondarySwayValue = approachVector(entry.secondarySwayValue, secondaryTarget, self.secondaryResponseRate, dt)
	entry.interactionBendValue = approachVector(entry.interactionBendValue, ZERO, self.interactionDecayRate, dt)
	entry.canopyFlutterValue = approachNumber(
		entry.canopyFlutterValue,
		if self.enableSecondaryFlutter then baseSample.flutter else 0,
		self.flutterResponseRate,
		dt
	)

	local Got = entry.windSample
	local combinedVector = entry.primarySwayValue + entry.interactionBendValue
	Got.vector = combinedVector
	Got.direction = GetDirectionOrFallback(combinedVector, baseSample.direction)
	Got.strength = (combinedVector + entry.secondarySwayValue).Magnitude
	Got.gustAlpha = baseSample.gustAlpha
	Got.detailAlpha = if self.enableSecondaryFlutter then baseSample.detailAlpha else 0
	Got.detailVector = entry.secondarySwayValue
	Got.flutter = entry.canopyFlutterValue
	return Got
end

function FoliageUpdateManager.Update(
	self: FoliageUpdateManager,
	simulationTime: number,
	_dt: number,
	referencePosition: Vector3
)
	local startClock = os.clock()
	local entries = self.registry.entries
	local entryCount = #entries

	local activeAnimatedTrees = 0
	local culledTrees = 0
	local nearTrees = 0
	local midTrees = 0
	local farTrees = 0
	local frozenTrees = 0
	local transformWrites = 0

	if entryCount <= 0 then
		self.stats.registeredTrees = 0
		self.stats.activeAnimatedTrees = 0
		self.stats.culledTrees = 0
		self.stats.nearTrees = 0
		self.stats.midTrees = 0
		self.stats.farTrees = 0
		self.stats.frozenTrees = 0
		self.stats.transformWrites = 0
		self.stats.averageUpdateCostMs = 0
		return
	end

	local startIndex = (self.entryCursor % entryCount) + 1
	for offset = 0, entryCount - 1 do
		local index = ((startIndex + offset - 1) % entryCount) + 1
		local entry = entries[index]
		if entry == nil then
			continue
		end
		if entry.instance.Parent == nil or entry.foliage.destroyed then
			self.registry:Unregister(entry.instance)
			continue
		end
		if isInAnimatingChunk(entry.instance) then
			entry.foliage:ResetPose()
			entry.rootPosition = entry.foliage:GetRootPosition()
			resetEntryDrivers(entry)
			entry.lastUpdateTime = simulationTime
			continue
		end

		local delta = entry.rootPosition - referencePosition
		local distanceSquared = delta:Dot(delta)
		local tier = self.lodController:Get(distanceSquared, entry.rootPosition, entry.boundingRadius)
		entry.lastDistanceSquared = distanceSquared
		entry.lastTierName = if tier ~= nil then tier.name else "Culled"

		if tier == nil then
			culledTrees += 1
			if self.debugEnabled then
				setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, "Culled")
			end
			continue
		end

		if entry.branchCount > self.branchCapPerTree or entry.leafCount > self.leafClusterCapPerTree then
			tier = self.lodController:Degrade(tier)
			entry.lastTierName = tier.name
		end

		if tier.name == "Near" then
			nearTrees += 1
		elseif tier.name == "Mid" then
			midTrees += 1
		elseif tier.name == "Far" then
			farTrees += 1
		else
			frozenTrees += 1
		end

		if entry.lastUpdateTime <= 0 then
			entry.foliage:ResetPose()
			entry.rootPosition = entry.foliage:GetRootPosition()
			resetEntryDrivers(entry)
			entry.lastUpdateTime = simulationTime
			if self.debugEnabled then
				setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, tier.name)
			end
			continue
		end

		local elapsed = simulationTime - entry.lastUpdateTime
		if elapsed > MAX_STALE_ELAPSED then
			entry.foliage:ResetPose()
			entry.rootPosition = entry.foliage:GetRootPosition()
			resetEntryDrivers(entry)
			entry.lastUpdateTime = simulationTime
			if self.debugEnabled then
				setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, tier.name)
			end
			continue
		end
		if elapsed < tier.updateInterval then
			if self.debugEnabled then
				setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, tier.name)
			end
			continue
		end

		if activeAnimatedTrees >= self.maxActiveTrees then
			culledTrees += 1
			continue
		end
		if transformWrites + entry.estimatedTransformWrites > self.maxTransformWritesPerStep then
			culledTrees += 1
			continue
		end

		local baseSample =
			self.windField:Sample(entry.rootPosition, simulationTime, entry.phaseOffset, entry.amplitudeScale)
		local effectiveDt = math.min(elapsed, MAX_EFFECTIVE_STEP_DT)
		local GotSample = self:UpdateEntryDrivers(entry, baseSample, effectiveDt)

		if not tier.frozen then
			entry.foliage:Step(simulationTime, effectiveDt, GotSample, tier.lodState, elapsed)
			entry.rootPosition = entry.foliage:GetRootPosition()
			transformWrites += entry.estimatedTransformWrites
			activeAnimatedTrees += 1
		end

		entry.lastUpdateTime = simulationTime
		if self.debugEnabled then
			setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, tier.name)
			setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_WRITES, entry.estimatedTransformWrites)
		end
	end

	self.entryCursor = startIndex
	self.stats.registeredTrees = self.registry:Count()
	self.stats.activeAnimatedTrees = activeAnimatedTrees
	self.stats.culledTrees = culledTrees
	self.stats.nearTrees = nearTrees
	self.stats.midTrees = midTrees
	self.stats.farTrees = farTrees
	self.stats.frozenTrees = frozenTrees
	self.stats.transformWrites = transformWrites
	self.stats.averageUpdateCostMs = (os.clock() - startClock) * 1000
end

function FoliageUpdateManager.GetStats(self: FoliageUpdateManager): { [string]: number }
	return Sift.Dictionary.copy(self.stats)
end
return FoliageUpdateManager
