--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Packages.Signal)

local PerfTier = {}
PerfTier.__index = PerfTier

export type TierName = "Low" | "Medium" | "High"

export type TierSettings = {
	particleDensity: number,
	debrisLimit: number,
	lightUpdateHz: number,
	chunkStreamDistance: number,
	tickRateScale: number,
}

export type PerfTierConfig = {
	eventBus: any?,
	eventChannel: string?,
	changeEvent: string?,
	tickScheduler: any?,
	sampleWindow: number?,
	evaluationInterval: number?,
	lowFpsThreshold: number?,
	highFpsThreshold: number?,
	lowMemoryThresholdMb: number?,
	mediumMemoryThresholdMb: number?,
	tiers: { [TierName]: TierSettings }?,
}

export type PerfTier = typeof(setmetatable({} :: any, PerfTier))

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type TierChangedSignal = {
	Connect: (self: TierChangedSignal, callback: (tier: TierName, settings: TierSettings) -> ()) -> SignalConnection,
	Fire: (self: TierChangedSignal, tier: TierName, settings: TierSettings) -> (),
	DisconnectAll: (self: TierChangedSignal) -> (),
	Destroy: (self: TierChangedSignal) -> (),
}

local DEFAULT_TIERS: { [TierName]: TierSettings } = {
	Low = {
		particleDensity = 0.35,
		debrisLimit = 100,
		lightUpdateHz = 8,
		chunkStreamDistance = 4,
		tickRateScale = 0.75,
	},
	Medium = {
		particleDensity = 0.7,
		debrisLimit = 220,
		lightUpdateHz = 16,
		chunkStreamDistance = 6,
		tickRateScale = 1,
	},
	High = {
		particleDensity = 1,
		debrisLimit = 420,
		lightUpdateHz = 30,
		chunkStreamDistance = 9,
		tickRateScale = 1.2,
	},
}

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function clampInteger(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then math.floor(valueRaw) else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function detectBaseTier(): TierName
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Low"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Medium"
	end
	return "High"
end

local function tierToRank(tier: TierName): number
	if tier == "Low" then
		return 1
	end
	if tier == "Medium" then
		return 2
	end
	return 3
end

local function rankToTier(rank: number): TierName
	if rank <= 1 then
		return "Low"
	end
	if rank == 2 then
		return "Medium"
	end
	return "High"
end

function PerfTier.new(configRaw: PerfTierConfig?): PerfTier
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local tierTable = {
		Low = table.clone(DEFAULT_TIERS.Low),
		Medium = table.clone(DEFAULT_TIERS.Medium),
		High = table.clone(DEFAULT_TIERS.High),
	}
	if typeof(config.tiers) == "table" then
		for key, value in config.tiers do
			if (key == "Low" or key == "Medium" or key == "High") and typeof(value) == "table" then
				tierTable[key] = {
					particleDensity = clampNumber(value.particleDensity, tierTable[key].particleDensity, 0, 4),
					debrisLimit = clampInteger(value.debrisLimit, tierTable[key].debrisLimit, 0, 100000),
					lightUpdateHz = clampNumber(value.lightUpdateHz, tierTable[key].lightUpdateHz, 1, 240),
					chunkStreamDistance = clampNumber(value.chunkStreamDistance, tierTable[key].chunkStreamDistance, 1, 1024),
					tickRateScale = clampNumber(value.tickRateScale, tierTable[key].tickRateScale, 0.1, 5),
				}
			end
		end
	end

	local sampleWindow = clampInteger(config.sampleWindow, 120, 10, 600)
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "perf"),
		changeEvent = normalizeEventName(config.changeEvent, "tierChanged"),
		tickScheduler = config.tickScheduler,
		sampleWindow = sampleWindow,
		evaluationInterval = clampNumber(config.evaluationInterval, 1, 0.1, 10),
		lowFpsThreshold = clampNumber(config.lowFpsThreshold, 42, 5, 300),
		highFpsThreshold = clampNumber(config.highFpsThreshold, 57, 5, 300),
		lowMemoryThresholdMb = clampNumber(config.lowMemoryThresholdMb, 1800, 64, 100000),
		mediumMemoryThresholdMb = clampNumber(config.mediumMemoryThresholdMb, 3200, 64, 100000),
		tiers = tierTable,
		currentTier = detectBaseTier() :: TierName,
		manualTier = nil :: TierName?,
		samples = table.create(sampleWindow, 1 / 60) :: { number },
		sampleIndex = 0,
		sampleCount = 0,
		sampleSum = 0,
		evaluationAccumulator = 0,
		changedSignal = Signal.new() :: TierChangedSignal,
		loopToken = nil,
		heartbeatConnection = nil :: RBXScriptConnection?,
		isInitialized = false,
	}, PerfTier)
	return self
end

function PerfTier._readMemoryMb(self: PerfTier): number
	local ok, value = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return 0
end

function PerfTier._recordFrame(self: PerfTier, dt: number)
	if dt <= 0 then
		return
	end
	local nextIndex = (self.sampleIndex % self.sampleWindow) + 1
	local old = self.samples[nextIndex]
	self.samples[nextIndex] = dt
	self.sampleIndex = nextIndex
	if self.sampleCount < self.sampleWindow then
		self.sampleCount += 1
		self.sampleSum += dt
	else
		self.sampleSum += dt - old
	end
end

function PerfTier._averageFps(self: PerfTier): number
	if self.sampleCount <= 0 or self.sampleSum <= 0 then
		return 60
	end
	local avgDt = self.sampleSum / self.sampleCount
	if avgDt <= 0 then
		return 60
	end
	return 1 / avgDt
end

function PerfTier._computeAutoTier(self: PerfTier): TierName
	local fps = self:_averageFps()
	local memoryMb = self:_readMemoryMb()
	local tierRank = tierToRank(detectBaseTier())

	if fps < self.lowFpsThreshold then
		tierRank -= 1
	elseif fps > self.highFpsThreshold then
		tierRank += 1
	end

	if memoryMb >= self.mediumMemoryThresholdMb then
		tierRank -= 1
	elseif memoryMb > 0 and memoryMb < (self.lowMemoryThresholdMb * 0.55) then
		tierRank += 1
	end

	tierRank = math.clamp(tierRank, 1, 3)
	return rankToTier(tierRank)
end

function PerfTier._emitChange(self: PerfTier, nextTier: TierName)
	local settings = self.tiers[nextTier]
	self.changedSignal:Fire(nextTier, settings)
	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.changeEvent, {
			tier = nextTier,
			settings = settings,
			avgFps = self:_averageFps(),
			memoryMb = self:_readMemoryMb(),
		})
	end
end

function PerfTier._evaluate(self: PerfTier)
	local nextTier = if self.manualTier ~= nil then self.manualTier else self:_computeAutoTier()
	if nextTier ~= self.currentTier then
		self.currentTier = nextTier
		self:_emitChange(nextTier)
	end
end

function PerfTier.update(self: PerfTier, dtRaw: any)
	local dt = clampNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end
	self:_recordFrame(dt)
	self.evaluationAccumulator += dt
	if self.evaluationAccumulator < self.evaluationInterval then
		return
	end
	self.evaluationAccumulator = 0
	self:_evaluate()
end

function PerfTier.init(self: PerfTier)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).scheduleEvery) == "function" then
		self.loopToken = (self.tickScheduler :: any):scheduleEvery(function(dt: number)
			self:update(dt)
		end, 1 / 60, {
			group = "platform.perf",
			priority = 90,
			catchUp = false,
		})
	else
		self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
			self:update(dt)
		end)
	end
	self:_evaluate()
end

function PerfTier.getTier(self: PerfTier): TierName
	return self.currentTier
end

function PerfTier.getSettings(self: PerfTier): TierSettings
	return self.tiers[self.currentTier]
end

function PerfTier.getSnapshot(self: PerfTier): { [string]: any }
	return {
		tier = self.currentTier,
		settings = self.tiers[self.currentTier],
		avgFps = self:_averageFps(),
		memoryMb = self:_readMemoryMb(),
		manualTier = self.manualTier,
	}
end

function PerfTier.onChanged(self: PerfTier, callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.changedSignal:Connect(callbackRaw :: (tier: TierName, settings: TierSettings) -> ())
	return function()
		connection:Disconnect()
	end
end

function PerfTier.setManualTier(self: PerfTier, tierRaw: any?): boolean
	if tierRaw == nil then
		self.manualTier = nil
		self:_evaluate()
		return true
	end
	if tierRaw ~= "Low" and tierRaw ~= "Medium" and tierRaw ~= "High" then
		return false
	end
	self.manualTier = tierRaw
	self:_evaluate()
	return true
end

function PerfTier.configureTickScheduler(self: PerfTier, schedulerRaw: any?, baseFixedStepRaw: any?): boolean
	local scheduler = if schedulerRaw ~= nil then schedulerRaw else self.tickScheduler
	if scheduler == nil then
		return false
	end
	local settings = self.tiers[self.currentTier]
	local baseFixedStep = clampNumber(baseFixedStepRaw, 1 / 60, 1 / 240, 1)
	local scaledStep = baseFixedStep / settings.tickRateScale

	if typeof((scheduler :: any).setFixedStep) == "function" then
		local schedulerAny = scheduler :: any
		schedulerAny:setFixedStep(scaledStep)
		return true
	end
	if typeof((scheduler :: any).fixedStep) == "number" then
		(scheduler :: any).fixedStep = scaledStep
		return true
	end
	return false
end

function PerfTier.getScaledTickInterval(self: PerfTier, baseIntervalRaw: any): number
	local baseInterval = clampNumber(baseIntervalRaw, 1 / 60, 1 / 10000, 10)
	local scale = self.tiers[self.currentTier].tickRateScale
	return baseInterval / scale
end

function PerfTier.destroy(self: PerfTier)
	if self.loopToken ~= nil then
		if typeof((self.loopToken :: any).cancel) == "function" then
			local loopTokenAny = self.loopToken :: any
			loopTokenAny:cancel()
		elseif self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).cancel) == "function" then
			local schedulerAny = self.tickScheduler :: any
			schedulerAny:cancel(self.loopToken)
		end
		self.loopToken = nil
	end
	safeDisconnect(self.heartbeatConnection)
	self.heartbeatConnection = nil
	self.changedSignal:DisconnectAll()
	self.changedSignal:Destroy()
	self.isInitialized = false
end

PerfTier.GetTier = PerfTier.getTier
PerfTier.GetSettings = PerfTier.getSettings
PerfTier.GetSnapshot = PerfTier.getSnapshot
PerfTier.SetManualTier = PerfTier.setManualTier
PerfTier.OnChanged = PerfTier.onChanged
PerfTier.ConfigureTickScheduler = PerfTier.configureTickScheduler
PerfTier.GetScaledTickInterval = PerfTier.getScaledTickInterval
PerfTier.Update = PerfTier.update
PerfTier.Init = PerfTier.init
PerfTier.Destroy = PerfTier.destroy

return PerfTier
