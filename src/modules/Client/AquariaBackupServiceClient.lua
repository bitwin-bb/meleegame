--!strict
--[=[
	@class AquariaBackupServiceClient
]=]

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Configs = (require :: any)(gameRoot.Shared.Core.Configs)
local CoreRuntime = (require :: any)(gameRoot.Shared.Core.Runtime)
local ClientNetPackets = (require :: any)(gameRoot.Client.NetClient.Packets)
local ui = loader("UI")

local AnimationServiceClient = loader("AnimationServiceClient")
local AquariaBackupTranslator = loader("AquariaBackupTranslator")
local AudioServiceClient = loader("AudioServiceClient")
local BossServiceClient = loader("BossServiceClient")
local BreathServiceClient = loader("BreathServiceClient")
local BuildServiceClient = loader("BuildServiceClient")
local CameraServiceClient = loader("CameraServiceClient")
local ClientBinderSupport = loader("ClientBinderSupport")
local CloudServiceClient = loader("CloudServiceClient")
local CraftingServiceClient = loader("CraftingServiceClient")
local GoreServiceClient = loader("GoreServiceClient")
local HpServiceClient = loader("HpServiceClient")
local InventoryServiceClient = loader("InventoryServiceClient")
local LiquidServiceClient = loader("LiquidServiceClient")
local LootServiceClient = loader("LootServiceClient")
local MagicServiceClient = loader("MagicServiceClient")
local ManaServiceClient = loader("ManaServiceClient")
local MeleeServiceClient = loader("MeleeServiceClient")
local NpcServiceClient = loader("NpcServiceClient")
local PadNavBinder = loader("PadNavBinder")
local ParallaxServiceClient = loader("ParallaxServiceClient")
local PlatformServiceClient = loader("PlatformServiceClient")
local PlayerDataServiceClient = loader("PlayerDataServiceClient")
local PlayerServiceClient = loader("PlayerServiceClient")
local RagdollServiceClient = loader("RagdollServiceClient")
local TileBreakServiceClient = loader("TileBreakServiceClient")
local VFXServiceClient = loader("VFXServiceClient")
local WeatherServiceClient = loader("WeatherServiceClient")
local WindFoliageServiceClient = loader("WindFoliageServiceClient")
local WorldAnimatorServiceClient = loader("WorldAnimatorServiceClient")
local WorldGenerationServiceClient = loader("WorldGenerationServiceClient")
local WorldSimulationServiceClient = loader("WorldSimulationServiceClient")

local CmdrBootstrapClient = loader("CmdrBootstrapClient")
local ScreenGuiService = loader("ScreenGuiService")
local SnackbarServiceClient = loader("SnackbarServiceClient")

local AquariaBackupServiceClient = {}
AquariaBackupServiceClient.ServiceName = "AquariaBackupServiceClient"

export type AquariaBackupServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: any,
	},
	{} :: typeof({ __index = AquariaBackupServiceClient })
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

local function initService(serviceName: string, service: any)
	local init = service.init
	if typeof(init) == "function" then
		init(service)
		return
	end

	local initPascal = service.Init
	if typeof(initPascal) == "function" then
		initPascal(service)
		return
	end

	error(`missing init method for {serviceName}`)
end

function AquariaBackupServiceClient.Init(self: AquariaBackupServiceClient, serviceBag: any): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._serviceBag:GetService(ClientBinderSupport)
	self._serviceBag:GetService(PadNavBinder)
	self._serviceBag:GetService(AquariaBackupTranslator)
	self._serviceBag:GetService(ScreenGuiService)
	self._serviceBag:GetService(SnackbarServiceClient)
	self._serviceBag:GetService(CmdrBootstrapClient)

	CoreRuntime.getClientRuntime():init()
	ClientNetPackets:init()

	initService("PlatformServiceClient", PlatformServiceClient)
	initService("PlayerDataServiceClient", PlayerDataServiceClient)
	initService("InventoryServiceClient", InventoryServiceClient)
	initService("CraftingServiceClient", CraftingServiceClient)
	initService("LootServiceClient", LootServiceClient)
	initService("ManaServiceClient", ManaServiceClient)
	if isCameraServiceEnabled() then
		initService("CameraServiceClient", CameraServiceClient)
	end
	initService("AudioServiceClient", AudioServiceClient)
	initService("VFXServiceClient", VFXServiceClient)
	initService("HpServiceClient", HpServiceClient)
	if isWorldSimulationReplicationEnabled() then
		initService("WorldSimulationServiceClient", WorldSimulationServiceClient)
	end
	initService("PlayerServiceClient", PlayerServiceClient)
	initService("WorldGenerationServiceClient", WorldGenerationServiceClient)
	initService("LiquidServiceClient", LiquidServiceClient)
	initService("ParallaxServiceClient", ParallaxServiceClient)
	initService("CloudServiceClient", CloudServiceClient)
	initService("BuildServiceClient", BuildServiceClient)
	initService("TileBreakServiceClient", TileBreakServiceClient)
	initService("WeatherServiceClient", WeatherServiceClient)
	initService("WindFoliageServiceClient", WindFoliageServiceClient)
	initService("WorldAnimatorServiceClient", WorldAnimatorServiceClient)
	initService("AnimationServiceClient", AnimationServiceClient)
	initService("NpcServiceClient", NpcServiceClient)
	initService("BossServiceClient", BossServiceClient)
	initService("MeleeServiceClient", MeleeServiceClient)
	initService("MagicServiceClient", MagicServiceClient)
	initService("BreathServiceClient", BreathServiceClient)
	initService("RagdollServiceClient", RagdollServiceClient)
	initService("GoreServiceClient", GoreServiceClient)
end

function AquariaBackupServiceClient.Start(self: AquariaBackupServiceClient): ()
	assert((self :: any)._serviceBag, "Not initialized")
	ui()
end

function AquariaBackupServiceClient.Destroy(self: AquariaBackupServiceClient): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupServiceClient
