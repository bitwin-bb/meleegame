--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Octree = require(ReplicatedStorage.Packages.Octree)
local FoliageInstance = require(script.Parent.FoliageInstance)
local RippleMotion = require(script.Parent.RippleMotion)

local TreeRuntimeRegistry = {}
TreeRuntimeRegistry.__index = TreeRuntimeRegistry

local RUNTIME_ATTRIBUTE_ID = "WindRuntimeId"

local function setAttributeIfChanged(instance: Instance, attributeName: string, value: any)
	if instance:GetAttribute(attributeName) == value then
		return
	end
	instance:SetAttribute(attributeName, value)
end

export type RuntimeEntry = {
	id: number,
	instance: Instance,
	foliage: any,
	config: { [string]: any },
	rootPosition: Vector3,
	boundingRadius: number,
	trunkReference: Instance?,
	seed: number,
	representation: string,
	branchCount: number,
	leafCount: number,
	boneCount: number,
	animatableNodeCount: number,
	phaseOffset: number,
	amplitudeScale: number,
	lastUpdateTime: number,
	lastDistanceSquared: number,
	lastTierName: string,
	estimatedTransformWrites: number,
	primarySwayMotion: any,
	secondarySwayMotion: any,
	interactionBendMotion: any,
	canopyFlutterMotion: any,
	resolvedWindSample: { [string]: any },
	orderIndex: number,
	debugActive: boolean,
}

export type TreeRuntimeRegistry = typeof(setmetatable({} :: any, TreeRuntimeRegistry))

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

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function sortEntriesById(a: RuntimeEntry, b: RuntimeEntry): boolean
	return a.id < b.id
end

local function resolveSeed(instance: Instance, config: { [string]: any }): number
	local seed = instance:GetAttribute("Seed")
	if typeof(seed) == "number" and seed == seed then
		return math.floor(seed)
	end
	local configSeed = config.seed
	if typeof(configSeed) == "number" and configSeed == configSeed then
		return math.floor(configSeed)
	end
	return 0
end

local function resolveBoundingRadius(instance: Instance, foliage: any): number
	if foliage.treeGraph ~= nil then
		local graph = foliage.treeGraph
		if typeof(graph.influenceRadius) == "number" then
			return math.max(2, graph.influenceRadius)
		end
	end

	if instance:IsA("BasePart") then
		return math.max(1, instance.Size.Magnitude * 0.5)
	end
	if instance:IsA("Model") then
		local ok, _, size = pcall(function()
			return instance:GetBoundingBox()
		end)
		if ok and typeof(size) == "Vector3" then
			return math.max(2, size.Magnitude * 0.5)
		end
	end
	return math.max(1, clampNumber(foliage.objectHeight, 4, 1, 512) * 0.75)
end

local function resolveTrunkReference(instance: Instance, foliage: any): Instance?
	if foliage.treeGraph ~= nil then
		local graph = foliage.treeGraph
		if typeof(graph.trunk) == "Instance" then
			return graph.trunk
		end
	end
	if foliage.part ~= nil then
		return foliage.part
	end
	if foliage.model ~= nil then
		return foliage.model.PrimaryPart or foliage.model
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance
	end
	return instance
end

local function resolveRuntimeShape(foliage: any): (number, number, number, number, string)
	if foliage.treeGraph ~= nil then
		local graph = foliage.treeGraph
		local branchCount = if typeof(graph.branchOrder) == "table" then #graph.branchOrder else 0
		local leafCount = if typeof(graph.leafNodes) == "table" then #graph.leafNodes else 0
		return branchCount, leafCount, 0, branchCount + leafCount + 1, "TreeGraph"
	end

	local boneCount = if typeof(foliage.bones) == "table" then #foliage.bones else 0
	if boneCount > 0 then
		return 0, 0, boneCount, boneCount, "Bone"
	end
	return 0, 0, 0, 1, tostring(foliage.representation or "BasePart")
end

function TreeRuntimeRegistry.new(configRaw: any?): TreeRuntimeRegistry
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local gridCellSize = clampNumber(config.gridCellSize, 18, 1, 2048)
	local octreeMaxDepth = math.max(1, math.floor(clampNumber(config.octreeMaxDepth, 4, 1, 12)))
	local octreeMaxRegionSize =
		clampNumber(config.octreeMaxRegionSize, math.max(64, gridCellSize * (2 ^ octreeMaxDepth)), 8, 32768)

	local self = setmetatable({
		config = config,
		nextId = 0,
		entries = {} :: { RuntimeEntry },
		entriesById = {} :: { [number]: RuntimeEntry },
		entriesByInstance = {} :: { [Instance]: RuntimeEntry },
		spatialIndex = Octree.new(octreeMaxRegionSize, octreeMaxDepth),
		spatialNodesById = {} :: { [number]: any },
		queryBuffer = {} :: { RuntimeEntry },
	}, TreeRuntimeRegistry)

	return self
end

function TreeRuntimeRegistry.register(self: TreeRuntimeRegistry, instanceRaw: any, configRaw: any): RuntimeEntry?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	local existing = self.entriesByInstance[instance]
	if existing ~= nil then
		return existing
	end

	local config = if typeof(configRaw) == "table" then configRaw :: { [string]: any } else {}
	local foliage = FoliageInstance.new(instance, config)
	if foliage == nil then
		return nil
	end

	self.nextId += 1
	local branchCount, leafCount, boneCount, animatableNodeCount, representation = resolveRuntimeShape(foliage)
	local entry: RuntimeEntry = {
		id = self.nextId,
		instance = instance,
		foliage = foliage,
		config = config,
		rootPosition = foliage:getRootPosition(),
		boundingRadius = resolveBoundingRadius(instance, foliage),
		trunkReference = resolveTrunkReference(instance, foliage),
		seed = resolveSeed(instance, config),
		representation = representation,
		branchCount = branchCount,
		leafCount = leafCount,
		boneCount = boneCount,
		animatableNodeCount = animatableNodeCount,
		phaseOffset = if typeof(foliage.phaseOffset) == "number" then foliage.phaseOffset else 0,
		amplitudeScale = if typeof(foliage.amplitudeScale) == "number" then foliage.amplitudeScale else 1,
		lastUpdateTime = 0,
		lastDistanceSquared = math.huge,
		lastTierName = "Uninitialized",
		estimatedTransformWrites = math.max(1, animatableNodeCount),
		primarySwayMotion = RippleMotion.createMotion(ZERO),
		secondarySwayMotion = RippleMotion.createMotion(ZERO),
		interactionBendMotion = RippleMotion.createMotion(ZERO),
		canopyFlutterMotion = RippleMotion.createMotion(0),
		resolvedWindSample = {
			vector = ZERO,
			direction = Vector3.xAxis,
			strength = 0,
			gustAlpha = 0,
			detailAlpha = 0,
			detailVector = ZERO,
			flutter = 0,
		},
		orderIndex = #self.entries + 1,
		debugActive = false,
	}

	self.entriesByInstance[instance] = entry
	self.entriesById[entry.id] = entry
	self.entries[entry.orderIndex] = entry
	self.spatialNodesById[entry.id] = self.spatialIndex:CreateNode(entry.rootPosition, entry)
	setAttributeIfChanged(instance, RUNTIME_ATTRIBUTE_ID, entry.id)

	return entry
end

function TreeRuntimeRegistry.unregister(self: TreeRuntimeRegistry, instanceRaw: any)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end

	local instance = instanceRaw :: Instance
	local entry = self.entriesByInstance[instance]
	if entry == nil then
		return
	end

	self.entriesByInstance[instance] = nil
	self.entriesById[entry.id] = nil
	local spatialNode = self.spatialNodesById[entry.id]
	if spatialNode ~= nil then
		spatialNode:Destroy()
		self.spatialNodesById[entry.id] = nil
	end

	local orderIndex = entry.orderIndex
	local lastEntry = self.entries[#self.entries]
	self.entries[#self.entries] = nil
	if lastEntry ~= nil and lastEntry ~= entry then
		self.entries[orderIndex] = lastEntry
		lastEntry.orderIndex = orderIndex
	end

	setAttributeIfChanged(instance, RUNTIME_ATTRIBUTE_ID, nil)
	entry.primarySwayMotion:destroy()
	entry.secondarySwayMotion:destroy()
	entry.interactionBendMotion:destroy()
	entry.canopyFlutterMotion:destroy()
	entry.foliage:destroy()
end

function TreeRuntimeRegistry.get(self: TreeRuntimeRegistry, instanceRaw: any): RuntimeEntry?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	return self.entriesByInstance[instanceRaw]
end

function TreeRuntimeRegistry.count(self: TreeRuntimeRegistry): number
	return #self.entries
end

function TreeRuntimeRegistry.queryRadius(self: TreeRuntimeRegistry, positionRaw: any, radiusRaw: any, outRaw: { any }?): { any }
	local position = if typeof(positionRaw) == "Vector3" then positionRaw else ZERO
	local radius = clampNumber(radiusRaw, 0, 0, 1000000)
	local out = if outRaw ~= nil then outRaw else self.queryBuffer
	clearArray(out)

	local results = self.spatialIndex:RadiusSearch(position, radius)
	for index, entry in results do
		out[index] = entry
	end

	if #out > 1 then
		table.sort(out, sortEntriesById)
	end

	return out
end

function TreeRuntimeRegistry.destroy(self: TreeRuntimeRegistry)
	for index = #self.entries, 1, -1 do
		local entry = self.entries[index]
		if entry ~= nil then
			self:unregister(entry.instance)
		end
	end
	table.clear(self.entriesByInstance)
	table.clear(self.entriesById)
	table.clear(self.spatialNodesById)
	table.clear(self.queryBuffer)
end

return TreeRuntimeRegistry
