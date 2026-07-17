local require = require(script.Parent.loader).load(script)

--[=[
	@class AquariaBackupService
]=]

local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local NetPacketsServer = require("NetPacketsServer")
local ServiceBag = require("ServiceBag")

local AnimationServiceServer = require("AnimationServiceServer")
local AquariaBackupTranslator = require("AquariaBackupTranslator")
local AudioServiceServer = require("AudioServiceServer")
local AutotileService = require("AutotileService")
local BinderSupportServer = require("BinderSupportServer")
local BossServiceServer = require("BossServiceServer")
local BreathServiceServer = require("BreathServiceServer")
local BuffService = require("BuffService")
local BuildServiceServer = require("BuildServiceServer")
local CameraServiceServer = require("CameraServiceServer")
local CelestialCycleServer = require("CelestialCycleServer")
local CmdrBootstrapServer = require("CmdrBootstrapServer")
local CraftingServiceServer = require("CraftingServiceServer")
local CropService = require("CropService")
local GoreServiceServer = require("GoreServiceServer")
local HpServiceServer = require("HpServiceServer")
local InventoryServiceServer = require("InventoryServiceServer")
local LiquidServiceServer = require("LiquidServiceServer")
local LootServiceServer = require("LootServiceServer")
local MagicServiceServer = require("MagicServiceServer")
local ManaServiceServer = require("ManaServiceServer")
local MeleeServiceServer = require("MeleeServiceServer")
local NpcServiceServer = require("NpcServiceServer")
local PlatformServiceServer = require("PlatformServiceServer")
local PlayerDataServiceServer = require("PlayerDataServiceServer")
local PlayerServiceServer = require("PlayerServiceServer")
local RagdollServiceServer = require("RagdollServiceServer")
local TilePlacementService = require("TilePlacementService")
local TileReplicationService = require("TileReplicationService")
local TileWorldService = require("TileWorldService")
local VFXServiceServer = require("VfxServiceServer")
local WallServiceServer = require("WallServiceServer")
local WeatherServiceServer = require("WeatherServiceServer")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")
local WorldSimulationServiceServer = require("WorldSimulationServiceServer")

local CmdrService = require("CmdrService")

local AquariaBackupService = {}
AquariaBackupService.ServiceName = "AquariaBackupService"

local function getOptionalLifecycleMethod(serviceDefinition: any, methodName: string): any
	local ok, method = pcall(function()
		return serviceDefinition[methodName]
	end)
	if not ok or typeof(method) ~= "function" then
		return nil
	end

	return method
end

local function createLegacyServiceOwner(
	serviceName: string,
	serviceDefinition: any,
	initCallback: ((serviceBag: ServiceBag.ServiceBag) -> ())?
): any
	local owner = {}
	owner.ServiceName = serviceName

	function owner.Init(self: any, serviceBag: ServiceBag.ServiceBag)
		self._serviceBag = serviceBag
		if initCallback ~= nil then
			initCallback(serviceBag)
		else
			local initMethod = getOptionalLifecycleMethod(serviceDefinition, "Init")
			if initMethod ~= nil then
				initMethod(serviceDefinition, serviceBag)
			end
		end
	end

	function owner.Start(_self: any)
		local startMethod = getOptionalLifecycleMethod(serviceDefinition, "Start")
		if startMethod ~= nil then
			startMethod(serviceDefinition)
		end
	end

	function owner.GetLegacyService(_self: any): any
		return serviceDefinition
	end

	function owner.Destroy(self: any)
		local destroyMethod = getOptionalLifecycleMethod(serviceDefinition, "Destroy")
		if destroyMethod ~= nil then
			destroyMethod(serviceDefinition)
		end
		self._serviceBag = nil
	end

	return owner
end

local CoreRuntimeServerOwner = createLegacyServiceOwner("CoreRuntimeServer", {
	Init = function(_self: any, _serviceBag: ServiceBag.ServiceBag)
		CoreRuntime.GetServerRuntime():Init()
	end,
	Destroy = function(_self: any)
		CoreRuntime.DestroyServerRuntime()
	end,
})
local NetPacketsServerOwner = createLegacyServiceOwner("NetPacketsServer", NetPacketsServer)
local PlatformServiceServerOwner = createLegacyServiceOwner(PlatformServiceServer.ServiceName, PlatformServiceServer)
local PlayerDataServiceServerOwner =
	createLegacyServiceOwner(PlayerDataServiceServer.ServiceName, PlayerDataServiceServer)
local WorldGenerationServiceServerOwner =
	createLegacyServiceOwner(WorldGenerationServiceServer.ServiceName, WorldGenerationServiceServer)
local WallServiceServerOwner = createLegacyServiceOwner(WallServiceServer.ServiceName, WallServiceServer)
local HpServiceServerOwner = createLegacyServiceOwner(HpServiceServer.ServiceName, HpServiceServer)
local LiquidServiceServerOwner = createLegacyServiceOwner(LiquidServiceServer.ServiceName, LiquidServiceServer)
local BuildServiceServerOwner = createLegacyServiceOwner(BuildServiceServer.ServiceName, BuildServiceServer)
local TileWorldServiceOwner = createLegacyServiceOwner(TileWorldService.ServiceName, TileWorldService)
local TileReplicationServiceOwner = createLegacyServiceOwner(TileReplicationService.ServiceName, TileReplicationService)
local AutotileServiceOwner = createLegacyServiceOwner(AutotileService.ServiceName, AutotileService)
local TilePlacementServiceOwner = createLegacyServiceOwner(TilePlacementService.ServiceName, TilePlacementService)
local WorldSimulationServiceServerOwner =
	createLegacyServiceOwner(WorldSimulationServiceServer.ServiceName, WorldSimulationServiceServer)
local InventoryServiceServerOwner = createLegacyServiceOwner(InventoryServiceServer.ServiceName, InventoryServiceServer)
local CraftingServiceServerOwner = createLegacyServiceOwner(CraftingServiceServer.ServiceName, CraftingServiceServer)
local LootServiceServerOwner = createLegacyServiceOwner(LootServiceServer.ServiceName, LootServiceServer)
local ManaServiceServerOwner = createLegacyServiceOwner(ManaServiceServer.ServiceName, ManaServiceServer)
local MeleeServiceServerOwner = createLegacyServiceOwner(MeleeServiceServer.ServiceName, MeleeServiceServer)
local MagicServiceServerOwner = createLegacyServiceOwner(MagicServiceServer.ServiceName, MagicServiceServer)
local GoreServiceServerOwner = createLegacyServiceOwner(GoreServiceServer.ServiceName, GoreServiceServer)
local CameraServiceServerOwner = createLegacyServiceOwner(CameraServiceServer.ServiceName, CameraServiceServer)
local PlayerServiceServerOwner = createLegacyServiceOwner(
	PlayerServiceServer.ServiceName,
	PlayerServiceServer,
	function(serviceBag: ServiceBag.ServiceBag)
		local worldOwner = serviceBag:GetService(WorldGenerationServiceServerOwner)
		local worldGenerationService = worldOwner:GetLegacyService()
		PlayerServiceServer:Init(serviceBag, worldGenerationService:GetWorld())
	end
)
local WeatherServiceServerOwner = createLegacyServiceOwner(WeatherServiceServer.ServiceName, WeatherServiceServer)
local CelestialCycleServerOwner = createLegacyServiceOwner(CelestialCycleServer.ServiceName, CelestialCycleServer)
local NpcServiceServerOwner = createLegacyServiceOwner(NpcServiceServer.ServiceName, NpcServiceServer)
local BossServiceServerOwner = createLegacyServiceOwner(BossServiceServer.ServiceName, BossServiceServer)
local AnimationServiceServerOwner = createLegacyServiceOwner(AnimationServiceServer.ServiceName, AnimationServiceServer)
local AudioServiceServerOwner = createLegacyServiceOwner(AudioServiceServer.ServiceName, AudioServiceServer)
local VFXServiceServerOwner = createLegacyServiceOwner(VFXServiceServer.ServiceName, VFXServiceServer)
local BreathServiceServerOwner = createLegacyServiceOwner(BreathServiceServer.ServiceName, BreathServiceServer)
local RagdollServiceServerOwner = createLegacyServiceOwner(RagdollServiceServer.ServiceName, RagdollServiceServer)
local BuffServiceOwner = createLegacyServiceOwner(BuffService.ServiceName, BuffService)

export type AquariaBackupService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = AquariaBackupService })
))

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

function AquariaBackupService.Init(self: AquariaBackupService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	local binderSupport = self._serviceBag:GetService(BinderSupportServer)
	binderSupport:ConfigureDependencies({
		BossServiceServer = BossServiceServer,
		GoreServiceServer = GoreServiceServer,
		HpServiceServer = HpServiceServer,
		InventoryServiceServer = InventoryServiceServer,
		LiquidServiceServer = LiquidServiceServer,
		LootServiceServer = LootServiceServer,
		MagicServiceServer = MagicServiceServer,
		MeleeServiceServer = MeleeServiceServer,
		NpcServiceServer = NpcServiceServer,
	})
	self._serviceBag:GetService(AquariaBackupTranslator)
	self._serviceBag:GetService(CmdrService)
	self._serviceBag:GetService(CmdrBootstrapServer)

	self._serviceBag:GetService(CoreRuntimeServerOwner)
	self._serviceBag:GetService(NetPacketsServerOwner)

	self._serviceBag:GetService(PlatformServiceServerOwner)
	self._serviceBag:GetService(PlayerDataServiceServerOwner)
	self._serviceBag:GetService(WorldGenerationServiceServerOwner)
	self._serviceBag:GetService(WallServiceServerOwner)
	self._serviceBag:GetService(HpServiceServerOwner)
	self._serviceBag:GetService(LiquidServiceServerOwner)
	self._serviceBag:GetService(BuildServiceServerOwner)
	self._serviceBag:GetService(TileWorldServiceOwner)
	self._serviceBag:GetService(TileReplicationServiceOwner)
	self._serviceBag:GetService(AutotileServiceOwner)
	self._serviceBag:GetService(TilePlacementServiceOwner)
	self._serviceBag:GetService(WorldSimulationServiceServerOwner)
	self._serviceBag:GetService(InventoryServiceServerOwner)
	self._serviceBag:GetService(CraftingServiceServerOwner)
	self._serviceBag:GetService(LootServiceServerOwner)
	self._serviceBag:GetService(ManaServiceServerOwner)
	self._serviceBag:GetService(MeleeServiceServerOwner)
	self._serviceBag:GetService(MagicServiceServerOwner)
	self._serviceBag:GetService(GoreServiceServerOwner)
	if isCameraServiceEnabled() then
		self._serviceBag:GetService(CameraServiceServerOwner)
	end
	self._serviceBag:GetService(PlayerServiceServerOwner)
	self._serviceBag:GetService(WeatherServiceServerOwner)
	self._serviceBag:GetService(CelestialCycleServerOwner)
	self._serviceBag:GetService(NpcServiceServerOwner)
	self._serviceBag:GetService(BossServiceServerOwner)
	self._serviceBag:GetService(AnimationServiceServerOwner)
	self._serviceBag:GetService(AudioServiceServerOwner)
	self._serviceBag:GetService(VFXServiceServerOwner)
	self._serviceBag:GetService(BreathServiceServerOwner)
	self._serviceBag:GetService(RagdollServiceServerOwner)

	self._serviceBag:GetService(CropService)
	self._serviceBag:GetService(BuffServiceOwner)
end

function AquariaBackupService.Start(self: AquariaBackupService): ()
	assert((self :: any)._serviceBag, "Not initialized")
end

function AquariaBackupService.Destroy(self: AquariaBackupService): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupService
