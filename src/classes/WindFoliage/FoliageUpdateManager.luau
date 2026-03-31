--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local RippleMotion = require(script.Parent.RippleMotion)

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

local function resolveDirectionOrFallback(vector: Vector3, fallback: Vector3): Vector3
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
	entry.primarySwayMotion:immediate(ZERO)
	entry.secondarySwayMotion:immediate(ZERO)
	entry.interactionBendMotion:immediate(ZERO)
	entry.canopyFlutterMotion:immediate(0)

	local resolved = entry.resolvedWindSample
	resolved.vector = ZERO
	resolved.direction = Vector3.xAxis
	resolved.strength = 0
	resolved.gustAlpha = 0
	resolved.detailAlpha = 0
	resolved.detailVector = ZERO
	resolved.flutter = 0
end

function FoliageUpdateManager.new(configRaw: any?, registry: any, windField: any, lodController: any, bufferPool: any): FoliageUpdateManager
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local runtime = if typeof(config.runtime) == "table" then config.runtime else {}
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
		maxTransformWritesPerStep = math.max(1, math.floor(clampNumber(runtime.maxTransformWritesPerStep, 24000, 1, 1000000))),
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
			activeRippleDrivers = 0,
			transformWrites = 0,
			averageUpdateCostMs = 0,
		},
		primarySpring = RippleMotion.resolveSpring(runtime.primaryDriverStiffness, runtime.primaryDriverDamping, 8, 5.5),
		secondarySpring = RippleMotion.resolveSpring(runtime.secondaryDriverStiffness, runtime.secondaryDriverDamping, 12, 6.5),
		interactionSpring = RippleMotion.resolveSpring(runtime.interactionDriverStiffness, runtime.interactionDriverDamping, 7.5, 5.2),
		flutterSpring = RippleMotion.resolveSpring(runtime.flutterDriverStiffness, runtime.flutterDriverDamping, 14, 7.5),
	}, FoliageUpdateManager)

	return self
end

function FoliageUpdateManager.applyInteractionImpulse(_self: FoliageUpdateManager, entry: any, impulseWorld: Vector3, originWorldRaw: any?)
	entry.interactionBendMotion:impulse(impulseWorld * 0.18)
	entry.foliage:addDisturbance(impulseWorld, originWorldRaw)
end

function FoliageUpdateManager.updateEntryDrivers(self: FoliageUpdateManager, entry: any, baseSample: any, dt: number)
	local primaryTarget = Vector3.new(baseSample.vector.X, 0, baseSample.vector.Z)
	local secondaryTarget = if self.enableSecondaryFlutter then baseSample.detailVector * baseSample.detailAlpha else ZERO

	entry.primarySwayMotion:spring(primaryTarget, self.primarySpring)
	entry.primarySwayMotion:step(dt)
	entry.secondarySwayMotion:spring(secondaryTarget, self.secondarySpring)
	entry.secondarySwayMotion:step(dt)
	entry.interactionBendMotion:spring(ZERO, self.interactionSpring)
	entry.interactionBendMotion:step(dt)
	entry.canopyFlutterMotion:spring(if self.enableSecondaryFlutter then baseSample.flutter else 0, self.flutterSpring)
	entry.canopyFlutterMotion:step(dt)

	local primaryValue = entry.primarySwayMotion:get()
	local secondaryValue = entry.secondarySwayMotion:get()
	local interactionValue = entry.interactionBendMotion:get()
	local flutterValue = entry.canopyFlutterMotion:get()

	local resolved = entry.resolvedWindSample
	local combinedVector = primaryValue + interactionValue
	resolved.vector = combinedVector
	resolved.direction = resolveDirectionOrFallback(combinedVector, baseSample.direction)
	resolved.strength = (combinedVector + secondaryValue).Magnitude
	resolved.gustAlpha = baseSample.gustAlpha
	resolved.detailAlpha = if self.enableSecondaryFlutter then baseSample.detailAlpha else 0
	resolved.detailVector = secondaryValue
	resolved.flutter = if typeof(flutterValue) == "number" then flutterValue else 0
	return resolved
end

function FoliageUpdateManager.update(self: FoliageUpdateManager, simulationTime: number, _dt: number, referencePosition: Vector3)
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
		self.stats.activeRippleDrivers = 0
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
			self.registry:unregister(entry.instance)
			continue
		end
		if isInAnimatingChunk(entry.instance) then
			entry.foliage:resetPose()
			entry.rootPosition = entry.foliage:getRootPosition()
			resetEntryDrivers(entry)
			entry.lastUpdateTime = simulationTime
			continue
		end

		local delta = entry.rootPosition - referencePosition
		local distanceSquared = delta:Dot(delta)
		local tier = self.lodController:resolve(distanceSquared, entry.rootPosition, entry.boundingRadius)
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
			tier = self.lodController:degrade(tier)
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
			entry.foliage:resetPose()
			entry.rootPosition = entry.foliage:getRootPosition()
			resetEntryDrivers(entry)
			entry.lastUpdateTime = simulationTime
			if self.debugEnabled then
				setAttributeIfChanged(entry.instance, RUNTIME_ATTRIBUTE_LOD, tier.name)
			end
			continue
		end

		local elapsed = simulationTime - entry.lastUpdateTime
		if elapsed > MAX_STALE_ELAPSED then
			entry.foliage:resetPose()
			entry.rootPosition = entry.foliage:getRootPosition()
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
			self.windField:sample(entry.rootPosition, simulationTime, entry.phaseOffset, entry.amplitudeScale)
		local effectiveDt = math.min(elapsed, MAX_EFFECTIVE_STEP_DT)
		local resolvedSample = self:updateEntryDrivers(entry, baseSample, effectiveDt)

		if not tier.frozen then
			entry.foliage:step(simulationTime, effectiveDt, resolvedSample, tier.lodState)
			entry.rootPosition = entry.foliage:getRootPosition()
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
	self.stats.registeredTrees = self.registry:count()
	self.stats.activeAnimatedTrees = activeAnimatedTrees
	self.stats.culledTrees = culledTrees
	self.stats.nearTrees = nearTrees
	self.stats.midTrees = midTrees
	self.stats.farTrees = farTrees
	self.stats.frozenTrees = frozenTrees
	self.stats.activeRippleDrivers = self.registry:count() * 4
	self.stats.transformWrites = transformWrites
	self.stats.averageUpdateCostMs = (os.clock() - startClock) * 1000
end

function FoliageUpdateManager.getStats(self: FoliageUpdateManager): { [string]: number }
	return Sift.Dictionary.copy(self.stats)
end

return FoliageUpdateManager
