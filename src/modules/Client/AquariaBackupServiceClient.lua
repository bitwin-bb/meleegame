--[=[
	@class AquariaBackupServiceClient
]=]

local require = require(script.Parent.loader).load(script)
local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local ClientNetPackets = require("ClientNetPackets")
local ui = require("UI")

local AnimationServiceClient = require("AnimationServiceClient")
local AquariaBackupTranslator = require("AquariaBackupTranslator")
local AudioServiceClient = require("AudioServiceClient")
local BossServiceClient = require("BossServiceClient")
local BreathServiceClient = require("BreathServiceClient")
local BuildServiceClient = require("BuildServiceClient")
local CameraServiceClient = require("CameraServiceClient")
local CelestialCycleClient = require("CelestialCycleClient")
local ClientBinderSupport = require("ClientBinderSupport")
local CloudServiceClient = require("CloudServiceClient")
local CraftingServiceClient = require("CraftingServiceClient")
local GoreServiceClient = require("GoreServiceClient")
local HpServiceClient = require("HpServiceClient")
local InventoryServiceClient = require("InventoryServiceClient")
local LiquidServiceClient = require("LiquidServiceClient")
local LootServiceClient = require("LootServiceClient")
local MagicServiceClient = require("MagicServiceClient")
local ManaServiceClient = require("ManaServiceClient")
local MeleeServiceClient = require("MeleeServiceClient")
local NpcServiceClient = require("NpcServiceClient")
local PadNavBinder = require("PadNavBinder")
local ParallaxServiceClient = require("ParallaxServiceClient")
local PlatformServiceClient = require("PlatformServiceClient")
local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerServiceClient = require("PlayerServiceClient")
local RagdollServiceClient = require("AquariaRagdollServiceClient")
local TileBreakServiceClient = require("TileBreakServiceClient")
local VFXServiceClient = require("VFXServiceClient")
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

	PlatformServiceClient:init()
	PlayerDataServiceClient:init()
	InventoryServiceClient:init()
	CraftingServiceClient:init()
	LootServiceClient:init()
	ManaServiceClient:init()
	if isCameraServiceEnabled() then
		CameraServiceClient:init()
	end
	AudioServiceClient:init()
	VFXServiceClient:init()
	HpServiceClient:init()
	if isWorldSimulationReplicationEnabled() then
		WorldSimulationServiceClient:init()
	end
	PlayerServiceClient:init()
	WorldGenerationServiceClient:init()
	LiquidServiceClient:init()
	ParallaxServiceClient:init()
	CloudServiceClient:init()
	BuildServiceClient:init()
	TileBreakServiceClient:init()
	WeatherServiceClient:init()
	CelestialCycleClient:init()
	SpaceClient:init()
	WindFoliageServiceClient:init()
	WorldAnimatorServiceClient:init()
	AnimationServiceClient:init()
	NpcServiceClient:init()
	BossServiceClient:init()
	MeleeServiceClient:init()
	MagicServiceClient:init()
	BreathServiceClient:init()
	RagdollServiceClient:init()
	GoreServiceClient:init()
end

function AquariaBackupServiceClient.Start(self: AquariaBackupServiceClient): ()
	assert((self :: any)._serviceBag, "Not initialized")
	ui()
end

function AquariaBackupServiceClient.Destroy(self: AquariaBackupServiceClient): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupServiceClient
