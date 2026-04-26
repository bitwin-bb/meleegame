--!strict
--[=[
	@class AquariaBackupServiceClient
]=]

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Configs = require(gameRoot.Shared.Modules.Core.Configs)
local CoreRuntime = require(gameRoot.Shared.Modules.Core.Runtime)
local ui = require(gameRoot.Client.UI)

local AnimationServiceClient = require(gameRoot.Client.Services.AnimationServiceClient)
local AquariaBackupTranslator = require(gameRoot.Shared.AquariaBackupTranslator)
local AudioServiceClient = require(gameRoot.Client.Services.AudioServiceClient)
local BossServiceClient = require(gameRoot.Client.Services.BossServiceClient)
local BreathServiceClient = require(gameRoot.Client.Services.BreathServiceClient)
local BuildServiceClient = require(gameRoot.Client.Services.BuildServiceClient)
local CameraServiceClient = require(gameRoot.Client.Services.CameraServiceClient)
local ClientBinderSupport = require(gameRoot.Client.Binders.ClientBinderSupport)
local PadNavBinder = require(gameRoot.Client.Binders.PadNavBinder)
local CraftingServiceClient = require(gameRoot.Client.Services.CraftingServiceClient)
local GoreServiceClient = require(gameRoot.Client.Services.GoreServiceClient)
local HpServiceClient = require(gameRoot.Client.Services.HpServiceClient)
local InventoryServiceClient = require(gameRoot.Client.Services.InventoryServiceClient)
local LiquidServiceClient = require(gameRoot.Client.Services.LiquidServiceClient)
local LootServiceClient = require(gameRoot.Client.Services.LootServiceClient)
local MagicServiceClient = require(gameRoot.Client.Services.MagicServiceClient)
local ManaServiceClient = require(gameRoot.Client.Services.ManaServiceClient)
local MeleeServiceClient = require(gameRoot.Client.Services.MeleeServiceClient)
local NpcServiceClient = require(gameRoot.Client.Services.NpcServiceClient)
local ParallaxServiceClient = require(gameRoot.Client.Services.ParallaxServiceClient)
local PlatformServiceClient = require(gameRoot.Client.Services.PlatformServiceClient)
local PlayerDataServiceClient = require(gameRoot.Client.Services.PlayerDataServiceClient)
local PlayerServiceClient = require(gameRoot.Client.Services.PlayerServiceClient)
local RagdollServiceClient = require(gameRoot.Client.Services.RagdollServiceClient)
local VFXServiceClient = require(gameRoot.Client.Services.VFXServiceClient)
local WeatherServiceClient = require(gameRoot.Client.Services.WeatherServiceClient)
local WindFoliageServiceClient = require(gameRoot.Client.Services.WindFoliageServiceClient)
local WorldAnimatorServiceClient = require(gameRoot.Client.Services.WorldAnimatorServiceClient)
local WorldGenerationServiceClient = require(gameRoot.Client.Services.WorldGenerationServiceClient)
local WorldSimulationServiceClient = require(gameRoot.Client.Services.WorldSimulationServiceClient)

local CmdrBootstrapClient = require("CmdrBootstrapClient")
local ScreenGuiService = require("ScreenGuiService")
local SnackbarServiceClient = require("SnackbarServiceClient")

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
	BuildServiceClient:init()
	WeatherServiceClient:init()
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
