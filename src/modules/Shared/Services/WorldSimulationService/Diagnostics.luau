--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)

local Diagnostics = {}
Diagnostics.__index = Diagnostics

type DebugObject = {
	setCounter: ((self: DebugObject, name: string, valueRaw: any) -> ())?,
}

type RuntimeSampleData = {
	worldTick: number,
	deltaTime: number,
	elapsedSeconds: number,
	activeChunkCount: number,
	selectedChunkCount: number,
	chunkBudget: number,
	processedChunks: number,
	processedCorruptionClusters: number,
	processedBiomeClusters: number,
	processedAiEntities: number,
	processedPhysicsEntities: number,
}

type RollingMetricsData = {
	sampleCount: number,
	averageSelectedChunks: number,
	averageProcessedChunks: number,
	averageCorruptionClusters: number,
	averageBiomeClusters: number,
	averageAiEntities: number,
	averagePhysicsEntities: number,
}

local RuntimeSample = Matter.component("WorldSimulationRuntimeSample", {
	worldTick = 0,
	deltaTime = 0,
	elapsedSeconds = 0,
	activeChunkCount = 0,
	selectedChunkCount = 0,
	chunkBudget = 0,
	processedChunks = 0,
	processedCorruptionClusters = 0,
	processedBiomeClusters = 0,
	processedAiEntities = 0,
	processedPhysicsEntities = 0,
})

local RollingMetrics = Matter.component("WorldSimulationRollingMetrics", {
	sampleCount = 0,
	averageSelectedChunks = 0,
	averageProcessedChunks = 0,
	averageCorruptionClusters = 0,
	averageBiomeClusters = 0,
	averageAiEntities = 0,
	averagePhysicsEntities = 0,
})

local function cloneTable(source: { [string]: any }): { [string]: any }
	local cloned = {}
	for key, value in source do
		cloned[key] = value
	end
	return cloned
end

local function average(previous: number, nextValue: number, sampleCount: number): number
	return previous + (nextValue - previous) / math.max(1, sampleCount)
end

local function applyPendingSample(self: Diagnostics): boolean
	local sample = self.pendingSample
	if sample == nil then
		return false
	end

	local _, currentRolling = self.world:get(self.entityId, RuntimeSample, RollingMetrics)
	local sampleCount = currentRolling.sampleCount + 1
	local nextRolling: RollingMetricsData = {
		sampleCount = sampleCount,
		averageSelectedChunks = average(currentRolling.averageSelectedChunks, sample.selectedChunkCount, sampleCount),
		averageProcessedChunks = average(currentRolling.averageProcessedChunks, sample.processedChunks, sampleCount),
		averageCorruptionClusters = average(
			currentRolling.averageCorruptionClusters,
			sample.processedCorruptionClusters,
			sampleCount
		),
		averageBiomeClusters = average(
			currentRolling.averageBiomeClusters,
			sample.processedBiomeClusters,
			sampleCount
		),
		averageAiEntities = average(currentRolling.averageAiEntities, sample.processedAiEntities, sampleCount),
		averagePhysicsEntities = average(
			currentRolling.averagePhysicsEntities,
			sample.processedPhysicsEntities,
			sampleCount
		),
	}

	self.world:insert(self.entityId, RuntimeSample(sample), RollingMetrics(nextRolling))
	self.lastSample = sample
	self.pendingSample = nil

	local debugModule = self.debug
	if debugModule ~= nil and debugModule.setCounter ~= nil then
		debugModule:setCounter("runtime_active_chunks", sample.activeChunkCount)
		debugModule:setCounter("runtime_selected_chunks", sample.selectedChunkCount)
		debugModule:setCounter("runtime_chunk_budget", sample.chunkBudget)
		debugModule:setCounter("runtime_tick_elapsed_last", sample.elapsedSeconds)
		debugModule:setCounter("runtime_samples", sampleCount)
		debugModule:setCounter("runtime_selected_chunks_avg", nextRolling.averageSelectedChunks)
		debugModule:setCounter("runtime_chunks_processed_avg", nextRolling.averageProcessedChunks)
		debugModule:setCounter("runtime_corruption_clusters_avg", nextRolling.averageCorruptionClusters)
		debugModule:setCounter("runtime_biome_clusters_avg", nextRolling.averageBiomeClusters)
		debugModule:setCounter("runtime_ai_entities_avg", nextRolling.averageAiEntities)
		debugModule:setCounter("runtime_physics_entities_avg", nextRolling.averagePhysicsEntities)
	end

	return true
end

export type Diagnostics = typeof(setmetatable({} :: {
	debug: DebugObject?,
	world: any,
	loop: any,
	connection: { default: RBXScriptConnection }?,
	bindable: BindableEvent?,
	entityId: number,
	pendingSample: RuntimeSampleData?,
	lastSample: RuntimeSampleData?,
}, Diagnostics))

function Diagnostics.New(debugModuleRaw: any): Diagnostics
	local self = setmetatable({
		debug = if typeof(debugModuleRaw) == "table" then (debugModuleRaw :: DebugObject) else nil,
		world = Matter.World.new(),
		loop = nil,
		connection = nil,
		bindable = Instance.new("BindableEvent"),
		entityId = 0,
		pendingSample = nil :: RuntimeSampleData?,
		lastSample = nil :: RuntimeSampleData?,
	}, Diagnostics)

	self.entityId = self.world:spawn(RuntimeSample(), RollingMetrics())
	self.loop = Matter.Loop.new(self.world, self)
	self.loop:scheduleSystem(function(world, diagnostics: Diagnostics)
		applyPendingSample(diagnostics)
	end)

	self.connection = self.loop:begin({
		default = (self.bindable :: BindableEvent).Event,
	})

	return self
end

function Diagnostics.Record(self: Diagnostics, sampleRaw: RuntimeSampleData)
	local sample: RuntimeSampleData = {
		worldTick = math.max(0, math.floor(sampleRaw.worldTick)),
		deltaTime = math.max(0, sampleRaw.deltaTime),
		elapsedSeconds = math.max(0, sampleRaw.elapsedSeconds),
		activeChunkCount = math.max(0, math.floor(sampleRaw.activeChunkCount)),
		selectedChunkCount = math.max(0, math.floor(sampleRaw.selectedChunkCount)),
		chunkBudget = math.max(0, math.floor(sampleRaw.chunkBudget)),
		processedChunks = math.max(0, math.floor(sampleRaw.processedChunks)),
		processedCorruptionClusters = math.max(0, math.floor(sampleRaw.processedCorruptionClusters)),
		processedBiomeClusters = math.max(0, math.floor(sampleRaw.processedBiomeClusters)),
		processedAiEntities = math.max(0, math.floor(sampleRaw.processedAiEntities)),
		processedPhysicsEntities = math.max(0, math.floor(sampleRaw.processedPhysicsEntities)),
	}

	self.pendingSample = sample
	applyPendingSample(self)
	if self.bindable ~= nil then
		self.bindable:Fire()
	end
end

function Diagnostics.GetSnapshot(self: Diagnostics): { [string]: any }
	applyPendingSample(self)
	local sample, rolling = self.world:get(self.entityId, RuntimeSample, RollingMetrics)
	return {
		sample = cloneTable(sample),
		rolling = cloneTable(rolling),
		lastSample = if self.lastSample ~= nil then cloneTable(self.lastSample) else nil,
	}
end

function Diagnostics.AttachDebugger(self: Diagnostics, debuggerRaw: any)
	if typeof(debuggerRaw) ~= "table" or typeof((debuggerRaw :: any).autoInitialize) ~= "function" then
		return
	end

	if self.connection ~= nil then
		self.connection.default:Disconnect()
		self.connection = nil
	end

	(debuggerRaw :: any):autoInitialize(self.loop)
	self.connection = self.loop:begin({
		default = (self.bindable :: BindableEvent).Event,
	})
end

function Diagnostics.Destroy(self: Diagnostics)
	if self.connection ~= nil then
		self.connection.default:Disconnect()
		self.connection = nil
	end
	if self.bindable ~= nil then
		self.bindable:Destroy()
		self.bindable = nil
	end
	self.pendingSample = nil
	self.lastSample = nil
end

Diagnostics.new = Diagnostics.New
Diagnostics.attachDebugger = Diagnostics.AttachDebugger
Diagnostics.getSnapshot = Diagnostics.GetSnapshot
Diagnostics.destroy = Diagnostics.Destroy

return Diagnostics
