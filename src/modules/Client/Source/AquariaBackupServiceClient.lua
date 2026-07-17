local require = require(script.Parent.loader).load(script)

--[=[
	@class AquariaBackupServiceClient
]=]

local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local NetPacketsClient = require("NetPacketsClient")
local ServiceBag = require("ServiceBag")
local UI = require("UI")

local AnimationServiceClient = require("AnimationServiceClient")
local AquariaBackupTranslator = require("AquariaBackupTranslator")
local AudioServiceClient = require("AudioServiceClient")
local AutotileRenderServiceClient = require("AutotileRenderServiceClient")
local BinderSupportClient = require("BinderSupportClient")
local BossServiceClient = require("BossServiceClient")
local BreathServiceClient = require("BreathServiceClient")
local BuffServiceClient = require("BuffServiceClient")
local BuffThunks = require("BuffThunks")
local BuildServiceClient = require("BuildServiceClient")
local CameraServiceClient = require("CameraServiceClient")
local CelestialCycleClient = require("CelestialCycleClient")
local CloudServiceClient = require("CloudServiceClient")
local CraftingServiceClient = require("CraftingServiceClient")
local CropController = require("CropController")
local CullServiceClient = require("CullServiceClient")
local GoreServiceClient = require("GoreServiceClient")
local HpServiceClient = require("HpServiceClient")
local InventoryServiceClient = require("InventoryServiceClient")
local LiquidServiceClient = require("LiquidServiceClient")
local LootServiceClient = require("LootServiceClient")
local MagicServiceClient = require("MagicServiceClient")
local ManaServiceClient = require("ManaServiceClient")
local MeleeServiceClient = require("MeleeServiceClient")
local NotificationServiceClient = require("NotificationServiceClient")
local NpcServiceClient = require("NpcServiceClient")
local PadNavBinder = require("PadNavBinder")
local ParallaxServiceClient = require("ParallaxServiceClient")
local PlatformServiceClient = require("PlatformServiceClient")
local PlayerClient = require("PlayerClient")
local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerServiceClient = require("PlayerServiceClient")
local RagdollServiceClient = require("AquariaRagdollServiceClient")
local TileBreakServiceClient = require("TileBreakServiceClient")
local VFXServiceClient = require("VfxServiceClient")
local WallAutotileServiceClient = require("WallAutotileServiceClient")
local WeatherServiceClient = require("WeatherServiceClient")
local WindFoliageServiceClient = require("WindFoliageServiceClient")
local WorldAnimatorServiceClient = require("WorldAnimatorServiceClient")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local WorldSimulationServiceClient = require("WorldSimulationServiceClient")

local CmdrBootstrapClient = require("CmdrBootstrapClient")
local ScreenGuiService = require("ScreenGuiService")
local SnackbarServiceClient = require("SnackbarServiceClient")
local SpaceClient = require("SpaceClient")

local AquariaBackupServiceClient = {}
AquariaBackupServiceClient.ServiceName = "AquariaBackupServiceClient"

export type AquariaBackupServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = AquariaBackupServiceClient })
))

type SingletonService = {
	Init: ((self: any, serviceBag: ServiceBag.ServiceBag) -> ())?,
	Destroy: ((self: any) -> ())?,
}

local function getOptionalLifecycleMethod(service: SingletonService, methodName: string): any
	local ok, method = pcall(function()
		return (service :: any)[methodName]
	end)
	if not ok or typeof(method) ~= "function" then
		return nil
	end

	return method
end

local function ownSingletonService(
	serviceBag: ServiceBag.ServiceBag,
	serviceName: string,
	service: SingletonService,
	init: ((serviceBag: ServiceBag.ServiceBag) -> ())?
)
	local owner = {
		ServiceName = serviceName,
	}

	function owner.Init(_self: any, ownerServiceBag: ServiceBag.ServiceBag)
		if init ~= nil then
			init(ownerServiceBag)
		else
			local initMethod = getOptionalLifecycleMethod(service, "Init")
			if initMethod ~= nil then
				initMethod(service, ownerServiceBag)
			end
		end
	end

	function owner.Destroy(_self: any)
		local destroyMethod = getOptionalLifecycleMethod(service, "Destroy")
		if destroyMethod ~= nil then
			destroyMethod(service)
		end
	end

	serviceBag:GetService(owner)
end

local function isCameraServiceEnabled(): boolean
	local cameraSettings = Configs.cameraSettings
	if typeof(cameraSettings) ~= "table" then
		return true
	end

	local serviceEnabled = (cameraSettings :: any).serviceEnabled
	if typeof(serviceEnabled) == "boolean" then
		return serviceEnabled
	end

	return true
end

local function isWorldSimulationReplicationEnabled(): boolean
	local worldSimulation = Configs.worldSimulation
	if typeof(worldSimulation) ~= "table" then
		return false
	end

	local enabled = (worldSimulation :: any).enableClientReplication
	if typeof(enabled) == "boolean" then
		return enabled
	end

	return false
end

function AquariaBackupServiceClient.Init(self: AquariaBackupServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	local binderSupport = self._serviceBag:GetService(BinderSupportClient)
	binderSupport:ConfigureDependencies({
		AudioServiceClient = AudioServiceClient,
		BuildServiceClient = BuildServiceClient,
		WindFoliageServiceClient = WindFoliageServiceClient,
	})
	self._serviceBag:GetService(PadNavBinder)
	self._serviceBag:GetService(AquariaBackupTranslator)
	self._serviceBag:GetService(ScreenGuiService)
	self._serviceBag:GetService(SnackbarServiceClient)
	self._serviceBag:GetService(CmdrBootstrapClient)
	self._serviceBag:GetService(NotificationServiceClient)

	ownSingletonService(self._serviceBag, "CoreRuntimeClient", CoreRuntime.GetClientRuntime())
	ownSingletonService(self._serviceBag, "NetPacketsClient", NetPacketsClient)

	ownSingletonService(self._serviceBag, "PlatformServiceClient", PlatformServiceClient)
	ownSingletonService(self._serviceBag, "PlayerDataServiceClient", PlayerDataServiceClient)
	ownSingletonService(self._serviceBag, "InventoryServiceClient", InventoryServiceClient)
	ownSingletonService(self._serviceBag, "CraftingServiceClient", CraftingServiceClient)
	ownSingletonService(self._serviceBag, "LootServiceClient", LootServiceClient)
	ownSingletonService(self._serviceBag, "ManaServiceClient", ManaServiceClient)
	if isCameraServiceEnabled() then
		ownSingletonService(self._serviceBag, "CameraServiceClient", CameraServiceClient)
	end
	ownSingletonService(self._serviceBag, "AudioServiceClient", AudioServiceClient)
	ownSingletonService(self._serviceBag, "VfxServiceClient", VFXServiceClient)
	ownSingletonService(self._serviceBag, "HpServiceClient", HpServiceClient)
	self._serviceBag:GetService(BuffServiceClient)
	self._serviceBag:GetService(BuffThunks)
	if isWorldSimulationReplicationEnabled() then
		ownSingletonService(self._serviceBag, "WorldSimulationServiceClient", WorldSimulationServiceClient)
	end
	ownSingletonService(self._serviceBag, "PlayerServiceClient", PlayerServiceClient)
	ownSingletonService(self._serviceBag, "PlayerClient", PlayerClient)
	ownSingletonService(self._serviceBag, "CullServiceClient", CullServiceClient)
	ownSingletonService(self._serviceBag, "WorldGenerationServiceClient", WorldGenerationServiceClient)
	ownSingletonService(self._serviceBag, "BuildServiceClient", BuildServiceClient)
	local wallAutotileService = self._serviceBag:GetService(WallAutotileServiceClient)
	local autotileRenderService = self._serviceBag:GetService(AutotileRenderServiceClient)
	binderSupport:ConfigureDependencies({
		AutotileRenderServiceClient = autotileRenderService,
		WallAutotileServiceClient = wallAutotileService,
	})
	ownSingletonService(self._serviceBag, "LiquidServiceClient", LiquidServiceClient)
	ownSingletonService(self._serviceBag, "ParallaxServiceClient", ParallaxServiceClient, function()
		ParallaxServiceClient:Init(nil)
	end)
	ownSingletonService(self._serviceBag, "CloudServiceClient", CloudServiceClient, function()
		CloudServiceClient:Init(nil)
	end)
	ownSingletonService(self._serviceBag, "TileBreakServiceClient", TileBreakServiceClient)
	ownSingletonService(self._serviceBag, "WeatherServiceClient", WeatherServiceClient, function(ownerServiceBag)
		WeatherServiceClient:Init(ownerServiceBag, AudioServiceClient)
	end)
	ownSingletonService(self._serviceBag, "CelestialCycleClient", CelestialCycleClient, function()
		CelestialCycleClient:Init(nil)
	end)
	ownSingletonService(self._serviceBag, "SpaceClient", SpaceClient)
	ownSingletonService(self._serviceBag, "WindFoliageServiceClient", WindFoliageServiceClient)
	ownSingletonService(self._serviceBag, "WorldAnimatorServiceClient", WorldAnimatorServiceClient)
	ownSingletonService(self._serviceBag, "AnimationServiceClient", AnimationServiceClient)
	ownSingletonService(self._serviceBag, "NpcServiceClient", NpcServiceClient)
	ownSingletonService(self._serviceBag, "BossServiceClient", BossServiceClient)
	ownSingletonService(self._serviceBag, "MeleeServiceClient", MeleeServiceClient)
	ownSingletonService(self._serviceBag, "MagicServiceClient", MagicServiceClient)
	ownSingletonService(self._serviceBag, "BreathServiceClient", BreathServiceClient)
	ownSingletonService(self._serviceBag, "AquariaRagdollServiceClient", RagdollServiceClient)
	ownSingletonService(self._serviceBag, "GoreServiceClient", GoreServiceClient)

	self._serviceBag:GetService(CropController)
	self._serviceBag:GetService(UI)
end

function AquariaBackupServiceClient.Start(self: AquariaBackupServiceClient): ()
	assert((self :: any)._serviceBag, "Not initialized")
end

function AquariaBackupServiceClient.Destroy(self: AquariaBackupServiceClient): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupServiceClient
