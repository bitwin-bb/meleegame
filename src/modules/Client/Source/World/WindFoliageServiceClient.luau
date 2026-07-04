local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sift: any = require(ReplicatedStorage.Packages.Sift)

local BinderSupportClient = require("BinderSupportClient")
local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local NevermoreSupport = require("NevermoreSupport")
local WindFoliage = require("WindFoliage")

type JanitorClass = any

local WindFoliageServiceClient = {}

local MIN_WEATHER_UPDATE_INTERVAL = 1 / 240

local RAIN_WIND_PROFILE = {
	strengthMultiplier = 1.85,
	baseStrength = 0.95,
	gustStrength = 3.15,
	detailStrength = 2.35,
	gustTimeScale = 0.25,
	detailTimeScale = 0.18,
	gustSpatialScale = 0.26,
	detailSpatialScale = 0.24,
	directionJitterRadians = 2.05,
	nearUpdateIntervalIncrease = 0.04,
	midUpdateIntervalIncrease = 0.08,
	farUpdateIntervalIncrease = 0.12,
	frozenUpdateIntervalIncrease = 0,
	nearWindScale = 0.44,
	midWindScale = 0.62,
	farWindScale = 0.88,
	nearDetailScale = 0.52,
	midDetailScale = 0.86,
	farDetailScale = 1.28,
	maxActiveTreesReduction = 0.12,
	maxTransformWritesPerStepReduction = 0.18,
}

local THUNDERSTORM_WIND_PROFILE = {
	strengthMultiplier = 3.6,
	baseStrength = 1.7,
	gustStrength = 6.1,
	detailStrength = 4.1,
	gustTimeScale = 0.55,
	detailTimeScale = 0.32,
	gustSpatialScale = 0.45,
	detailSpatialScale = 0.4,
	directionJitterRadians = 3.1,
	nearUpdateIntervalIncrease = 0.08,
	midUpdateIntervalIncrease = 0.14,
	farUpdateIntervalIncrease = 0.2,
	frozenUpdateIntervalIncrease = 0.03,
	nearWindScale = 0.86,
	midWindScale = 1.12,
	farWindScale = 1.46,
	nearDetailScale = 0.94,
	midDetailScale = 1.28,
	farDetailScale = 1.92,
	maxActiveTreesReduction = 0.18,
	maxTransformWritesPerStepReduction = 0.24,
}

local function snapshotTier(tierRaw: any): { [string]: number }?
	if typeof(tierRaw) ~= "table" then
		return nil
	end

	local tier = tierRaw :: any
	local lodState = tier.lodState
	return {
		updateInterval = if typeof(tier.updateInterval) == "number"
				and tier.updateInterval == tier.updateInterval
			then tier.updateInterval
			else nil,
		windScale = if typeof(lodState) == "table"
				and typeof(lodState.windScale) == "number"
				and lodState.windScale == lodState.windScale
			then lodState.windScale
			else nil,
		detailScale = if typeof(lodState) == "table"
				and typeof(lodState.detailScale) == "number"
				and lodState.detailScale == lodState.detailScale
			then lodState.detailScale
			else nil,
	}
end

local function applyTierState(
	tierRaw: any,
	baselineRaw: any,
	stormAlpha: number,
	updateIntervalIncrease: number,
	windBoost: number,
	detailBoost: number
)
	if typeof(tierRaw) ~= "table" or typeof(baselineRaw) ~= "table" then
		return
	end

	local tier = tierRaw :: any
	local baseline = baselineRaw :: any
	if typeof(baseline.updateInterval) == "number" then
		tier.updateInterval =
			math.max(MIN_WEATHER_UPDATE_INTERVAL, baseline.updateInterval * (1 + stormAlpha * updateIntervalIncrease))
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

local function GetConfig(): { [string]: any }
	local configSource = if typeof(Configs) == "table" then (Configs :: any).windFoliage else nil
	return if typeof(configSource) == "table" then Sift.Dictionary.copy(configSource) else {} :: any
end

local function RegisterExistingFoliage(simulation: any)
	for _, descendant in Workspace:GetDescendants() do
		simulation:ConsiderDescendant(descendant)
	end
end

function WindFoliageServiceClient.Init(self: any)
	if self.janitor ~= nil then
		return
	end

	local config = GetConfig()
	if config.enabled == false then
		return
	end

	local runtime = CoreRuntime.GetClientRuntime()
	local tickScheduler = runtime:GetTickScheduler()
	config.tickScheduler = tickScheduler
	config.observeTaggedInstances = false

	self.simulation = WindFoliage.New(config)
	self.simulation:Init()
	self.binders = NevermoreSupport.GetService(BinderSupportClient)
	RegisterExistingFoliage(self.simulation)
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
	}

	local janitor = self.janitor :: JanitorClass
	janitor:GiveChore(function()
		self.binders = nil
		self.weatherWindState = nil
		if self.simulation ~= nil then
			self.simulation:Destroy()
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
		windField.detailSpatialScale =
			math.max(1, state.detailSpatialScale * (1 - stormAlpha * profile.detailSpatialScale))
	end
	if state.detailTimeScale ~= nil then
		windField.detailTimeScale = state.detailTimeScale * (1 + stormAlpha * profile.detailTimeScale)
	end
	if state.directionJitterRadians ~= nil then
		windField.directionJitterRadians =
			math.clamp(state.directionJitterRadians * (1 + stormAlpha * profile.directionJitterRadians), 0, math.pi)
	end

	local tiers = state.tiers
	if lodController ~= nil and typeof(tiers) == "table" then
		applyTierState(
			lodController.tierNear,
			tiers.near,
			stormAlpha,
			profile.nearUpdateIntervalIncrease,
			profile.nearWindScale,
			profile.nearDetailScale
		)
		applyTierState(
			lodController.tierMid,
			tiers.mid,
			stormAlpha,
			profile.midUpdateIntervalIncrease,
			profile.midWindScale,
			profile.midDetailScale
		)
		applyTierState(
			lodController.tierFar,
			tiers.far,
			stormAlpha,
			profile.farUpdateIntervalIncrease,
			profile.farWindScale,
			profile.farDetailScale
		)
		applyTierState(lodController.tierFrozen, tiers.frozen, stormAlpha, profile.frozenUpdateIntervalIncrease, 0, 0)
	end

	local updateBudget = state.updateBudget
	if updateManager ~= nil and typeof(updateBudget) == "table" then
		if typeof(updateBudget.maxActiveTrees) == "number" then
			updateManager.maxActiveTrees = math.max(
				1,
				math.floor(updateBudget.maxActiveTrees * (1 - stormAlpha * profile.maxActiveTreesReduction))
			)
		end
		if typeof(updateBudget.maxTransformWritesPerStep) == "number" then
			updateManager.maxTransformWritesPerStep = math.max(
				1,
				math.floor(
					updateBudget.maxTransformWritesPerStep
						* (1 - stormAlpha * profile.maxTransformWritesPerStepReduction)
				)
			)
		end
	end

end

function WindFoliageServiceClient.ApplyLightningImpulse(self: any, intensityRaw: any?): number?
	if self.simulation == nil then
		return nil
	end

	local intensity = if typeof(intensityRaw) == "number" and intensityRaw == intensityRaw
		then math.clamp(intensityRaw, 0, 1)
		else 1
	local windField = self.simulation.windField
	local direction = if windField ~= nil and typeof(windField.baseDirection) == "Vector3"
		then windField.baseDirection
		else Vector3.new(1, 0, 0.25)

	return self.simulation:ApplyGlobalImpulse({
		direction = direction,
		strength = 8 + intensity * 16,
	})
end

function WindFoliageServiceClient.AddDisturbance(self: any, paramsRaw: any): number?
	if self.simulation == nil then
		return nil
	end
	return self.simulation:AddDisturbance(paramsRaw)
end

function WindFoliageServiceClient.RegisterFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:RegisterFoliage(instanceRaw)
end

function WindFoliageServiceClient.UnregisterFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:UnregisterFoliage(instanceRaw)
end

function WindFoliageServiceClient.TrackDisturber(self: any, instanceRaw: any, overrideConfigRaw: any?)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:TrackDisturber(instanceRaw, overrideConfigRaw)
end

function WindFoliageServiceClient.UntrackDisturber(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:UntrackDisturber(instanceRaw)
end

function WindFoliageServiceClient.GetStats(self: any): { [string]: number }
	if self.simulation == nil then
		return {}
	end
	return self.simulation:GetStats()
end

function WindFoliageServiceClient.Destroy(self: any)
	if self.janitor ~= nil then
		local janitor = self.janitor :: JanitorClass
		janitor:Destroy()
		self.janitor = nil
	end
	self.simulation = nil
end
return WindFoliageServiceClient
