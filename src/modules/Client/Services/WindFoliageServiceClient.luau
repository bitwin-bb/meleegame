--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local WindFoliage = require(script:FindFirstAncestor("game").Shared.Classes.WindFoliage)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ClientBinderSupport = require(script:FindFirstAncestor("game").Client.Binders.ClientBinderSupport)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local WindFoliageServiceClient = {}

local MIN_WEATHER_UPDATE_INTERVAL = 1 / 240

local RAIN_WIND_PROFILE = {
	strengthMultiplier = 1.45,
	baseStrength = 0.7,
	gustStrength = 2.2,
	detailStrength = 1.6,
	gustTimeScale = 1.1,
	detailTimeScale = 0.9,
	gustSpatialScale = 0.22,
	detailSpatialScale = 0.2,
	directionJitterRadians = 1.45,
	nearUpdateIntervalReduction = 0.5,
	midUpdateIntervalReduction = 0.45,
	farUpdateIntervalReduction = 0.32,
	frozenUpdateIntervalReduction = 0.18,
	nearWindScale = 0.18,
	midWindScale = 0.26,
	farWindScale = 0.42,
	nearDetailScale = 0.25,
	midDetailScale = 0.48,
	farDetailScale = 0.9,
	maxActiveTrees = 0.28,
	maxTransformWritesPerStep = 0.35,
	primarySpringFrequency = 0.45,
	secondarySpringFrequency = 0.65,
	flutterSpringFrequency = 0.8,
}

local THUNDERSTORM_WIND_PROFILE = {
	strengthMultiplier = 2.2,
	baseStrength = 1.1,
	gustStrength = 3.35,
	detailStrength = 2.45,
	gustTimeScale = 1.85,
	detailTimeScale = 1.45,
	gustSpatialScale = 0.38,
	detailSpatialScale = 0.34,
	directionJitterRadians = 2.8,
	nearUpdateIntervalReduction = 0.72,
	midUpdateIntervalReduction = 0.62,
	farUpdateIntervalReduction = 0.48,
	frozenUpdateIntervalReduction = 0.32,
	nearWindScale = 0.34,
	midWindScale = 0.52,
	farWindScale = 0.82,
	nearDetailScale = 0.38,
	midDetailScale = 0.72,
	farDetailScale = 1.4,
	maxActiveTrees = 0.6,
	maxTransformWritesPerStep = 0.75,
	primarySpringFrequency = 0.9,
	secondarySpringFrequency = 1.15,
	flutterSpringFrequency = 1.35,
}

local function snapshotTier(tierRaw: any): { [string]: number }?
	if typeof(tierRaw) ~= "table" then
		return nil
	end

	local tier = tierRaw :: any
	local lodState = tier.lodState
	return {
		updateInterval = if typeof(tier.updateInterval) == "number" and tier.updateInterval == tier.updateInterval
			then tier.updateInterval
			else nil,
		windScale = if typeof(lodState) == "table" and typeof(lodState.windScale) == "number" and lodState.windScale == lodState.windScale
			then lodState.windScale
			else nil,
		detailScale = if typeof(lodState) == "table" and typeof(lodState.detailScale) == "number" and lodState.detailScale == lodState.detailScale
			then lodState.detailScale
			else nil,
	}
end

local function snapshotSpring(springRaw: any): { [string]: number }?
	if typeof(springRaw) ~= "table" then
		return nil
	end

	local spring = springRaw :: any
	return {
		frequency = if typeof(spring.frequency) == "number" and spring.frequency == spring.frequency then spring.frequency else nil,
		damping = if typeof(spring.damping) == "number" and spring.damping == spring.damping then spring.damping else nil,
	}
end

local function applyTierState(tierRaw: any, baselineRaw: any, stormAlpha: number, updateReduction: number, windBoost: number, detailBoost: number)
	if typeof(tierRaw) ~= "table" or typeof(baselineRaw) ~= "table" then
		return
	end

	local tier = tierRaw :: any
	local baseline = baselineRaw :: any
	if typeof(baseline.updateInterval) == "number" then
		tier.updateInterval = math.max(
			MIN_WEATHER_UPDATE_INTERVAL,
			baseline.updateInterval * (1 - stormAlpha * updateReduction)
		)
	end

	local lodState = tier.lodState
	if typeof(lodState) ~= "table" then
		return
	end
	if typeof(baseline.windScale) == "number" then
		lodState.windScale = baseline.windScale * (1 + stormAlpha * windBoost)
	end
	if typeof(baseline.detailScale) == "number" then
		lodState.detailScale = baseline.detailScale * (1 + stormAlpha * detailBoost)
	end
end

local function applySpringState(springRaw: any, baselineRaw: any, stormAlpha: number, frequencyBoost: number)
	if typeof(springRaw) ~= "table" or typeof(baselineRaw) ~= "table" then
		return
	end

	local spring = springRaw :: any
	local baseline = baselineRaw :: any
	if typeof(baseline.frequency) == "number" then
		spring.frequency = math.max(0.01, baseline.frequency * (1 + stormAlpha * frequencyBoost))
	end
	if typeof(baseline.damping) == "number" then
		spring.damping = baseline.damping
	end
end

local function resolveConfig(): { [string]: any }
	local configSource = if typeof(Configs) == "table" then (Configs :: any).windFoliage else nil
	return if typeof(configSource) == "table" then Sift.Dictionary.copy(configSource) else {}
end

function WindFoliageServiceClient.Init(self: any)
	if self.janitor ~= nil then
		return
	end

	local config = resolveConfig()
	if config.enabled == false then
		return
	end

	local runtime = CoreRuntime.getClientRuntime()
	local tickScheduler = runtime:getTickScheduler()
	config.tickScheduler = tickScheduler
	config.observeTaggedInstances = false

	self.simulation = WindFoliage.new(config)
	self.simulation:init()
	self.binders = NevermoreSupport.getService(ClientBinderSupport)
	self.janitor = Janitor.new()
	local windField = self.simulation.windField
	local lodController = self.simulation.lodController
	local updateManager = self.simulation.updateManager
	self.weatherWindState = {
		strengthMultiplier = if windField ~= nil then windField.strengthMultiplier else nil,
		baseStrength = if windField ~= nil then windField.baseStrength else nil,
		gustStrength = if windField ~= nil then windField.gustStrength else nil,
		detailStrength = if windField ~= nil then windField.detailStrength else nil,
		gustSpatialScale = if windField ~= nil then windField.gustSpatialScale else nil,
		gustTimeScale = if windField ~= nil then windField.gustTimeScale else nil,
		detailSpatialScale = if windField ~= nil then windField.detailSpatialScale else nil,
		detailTimeScale = if windField ~= nil then windField.detailTimeScale else nil,
		directionJitterRadians = if windField ~= nil then windField.directionJitterRadians else nil,
		tiers = {
			near = if lodController ~= nil then snapshotTier(lodController.tierNear) else nil,
			mid = if lodController ~= nil then snapshotTier(lodController.tierMid) else nil,
			far = if lodController ~= nil then snapshotTier(lodController.tierFar) else nil,
			frozen = if lodController ~= nil then snapshotTier(lodController.tierFrozen) else nil,
		},
		updateBudget = {
			maxActiveTrees = if updateManager ~= nil then updateManager.maxActiveTrees else nil,
			maxTransformWritesPerStep = if updateManager ~= nil then updateManager.maxTransformWritesPerStep else nil,
		},
		springs = {
			primary = if updateManager ~= nil then snapshotSpring(updateManager.primarySpring) else nil,
			secondary = if updateManager ~= nil then snapshotSpring(updateManager.secondarySpring) else nil,
			flutter = if updateManager ~= nil then snapshotSpring(updateManager.flutterSpring) else nil,
		},
	}

	local janitor = self.janitor :: JanitorClass
	janitor:GiveChore(function()
		self.binders = nil
		self.weatherWindState = nil
		if self.simulation ~= nil then
			self.simulation:destroy()
			self.simulation = nil
		end
	end)
end

function WindFoliageServiceClient.SetWeatherWind(self: any, stormAlphaRaw: any, thunderstormRaw: any?)
	if self.simulation == nil or self.weatherWindState == nil then
		return
	end

	local windField = self.simulation.windField
	if windField == nil then
		return
	end
	local lodController = self.simulation.lodController
	local updateManager = self.simulation.updateManager

	local stormAlpha = if typeof(stormAlphaRaw) == "number" and stormAlphaRaw == stormAlphaRaw
		then math.clamp(stormAlphaRaw, 0, 1)
		else 0
	local isThunderstorm = thunderstormRaw == true
	local state = self.weatherWindState
	local profile = if isThunderstorm then THUNDERSTORM_WIND_PROFILE else RAIN_WIND_PROFILE

	if state.strengthMultiplier ~= nil then
		windField.strengthMultiplier = state.strengthMultiplier * (1 + stormAlpha * profile.strengthMultiplier)
	end
	if state.baseStrength ~= nil then
		windField.baseStrength = state.baseStrength * (1 + stormAlpha * profile.baseStrength)
	end
	if state.gustStrength ~= nil then
		windField.gustStrength = state.gustStrength * (1 + stormAlpha * profile.gustStrength)
	end
	if state.detailStrength ~= nil then
		windField.detailStrength = state.detailStrength * (1 + stormAlpha * profile.detailStrength)
	end
	if state.gustSpatialScale ~= nil then
		windField.gustSpatialScale = math.max(1, state.gustSpatialScale * (1 - stormAlpha * profile.gustSpatialScale))
	end
	if state.gustTimeScale ~= nil then
		windField.gustTimeScale = state.gustTimeScale * (1 + stormAlpha * profile.gustTimeScale)
	end
	if state.detailSpatialScale ~= nil then
		windField.detailSpatialScale = math.max(1, state.detailSpatialScale * (1 - stormAlpha * profile.detailSpatialScale))
	end
	if state.detailTimeScale ~= nil then
		windField.detailTimeScale = state.detailTimeScale * (1 + stormAlpha * profile.detailTimeScale)
	end
	if state.directionJitterRadians ~= nil then
		windField.directionJitterRadians = math.clamp(
			state.directionJitterRadians * (1 + stormAlpha * profile.directionJitterRadians),
			0,
			math.pi
		)
	end

	local tiers = state.tiers
	if lodController ~= nil and typeof(tiers) == "table" then
		applyTierState(
			lodController.tierNear,
			tiers.near,
			stormAlpha,
			profile.nearUpdateIntervalReduction,
			profile.nearWindScale,
			profile.nearDetailScale
		)
		applyTierState(
			lodController.tierMid,
			tiers.mid,
			stormAlpha,
			profile.midUpdateIntervalReduction,
			profile.midWindScale,
			profile.midDetailScale
		)
		applyTierState(
			lodController.tierFar,
			tiers.far,
			stormAlpha,
			profile.farUpdateIntervalReduction,
			profile.farWindScale,
			profile.farDetailScale
		)
		applyTierState(
			lodController.tierFrozen,
			tiers.frozen,
			stormAlpha,
			profile.frozenUpdateIntervalReduction,
			0,
			0
		)
	end

	local updateBudget = state.updateBudget
	if updateManager ~= nil and typeof(updateBudget) == "table" then
		if typeof(updateBudget.maxActiveTrees) == "number" then
			updateManager.maxActiveTrees =
				math.max(1, math.floor(updateBudget.maxActiveTrees * (1 + stormAlpha * profile.maxActiveTrees)))
		end
		if typeof(updateBudget.maxTransformWritesPerStep) == "number" then
			updateManager.maxTransformWritesPerStep = math.max(
				1,
				math.floor(updateBudget.maxTransformWritesPerStep * (1 + stormAlpha * profile.maxTransformWritesPerStep))
			)
		end
	end

	local springs = state.springs
	if updateManager ~= nil and typeof(springs) == "table" then
		applySpringState(updateManager.primarySpring, springs.primary, stormAlpha, profile.primarySpringFrequency)
		applySpringState(updateManager.secondarySpring, springs.secondary, stormAlpha, profile.secondarySpringFrequency)
		applySpringState(updateManager.flutterSpring, springs.flutter, stormAlpha, profile.flutterSpringFrequency)
	end
end

function WindFoliageServiceClient.AddDisturbance(self: any, paramsRaw: any): number?
	if self.simulation == nil then
		return nil
	end
	return self.simulation:addDisturbance(paramsRaw)
end

function WindFoliageServiceClient.RegisterFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:registerFoliage(instanceRaw)
end

function WindFoliageServiceClient.UnregisterFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:unregisterFoliage(instanceRaw)
end

function WindFoliageServiceClient.TrackDisturber(self: any, instanceRaw: any, overrideConfigRaw: any?)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:trackDisturber(instanceRaw, overrideConfigRaw)
end

function WindFoliageServiceClient.UntrackDisturber(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:untrackDisturber(instanceRaw)
end

function WindFoliageServiceClient.GetStats(self: any): { [string]: number }
	if self.simulation == nil then
		return {}
	end
	return self.simulation:getStats()
end

function WindFoliageServiceClient.Destroy(self: any)
	if self.janitor ~= nil then
		local janitor = self.janitor :: JanitorClass
		janitor:Destroy()
		self.janitor = nil
	end
	self.simulation = nil
end

WindFoliageServiceClient.init = WindFoliageServiceClient.Init
WindFoliageServiceClient.setWeatherWind = WindFoliageServiceClient.SetWeatherWind
WindFoliageServiceClient.addDisturbance = WindFoliageServiceClient.AddDisturbance
WindFoliageServiceClient.registerFoliage = WindFoliageServiceClient.RegisterFoliage
WindFoliageServiceClient.unregisterFoliage = WindFoliageServiceClient.UnregisterFoliage
WindFoliageServiceClient.trackDisturber = WindFoliageServiceClient.TrackDisturber
WindFoliageServiceClient.untrackDisturber = WindFoliageServiceClient.UntrackDisturber
WindFoliageServiceClient.getStats = WindFoliageServiceClient.GetStats
WindFoliageServiceClient.destroy = WindFoliageServiceClient.Destroy

return WindFoliageServiceClient
