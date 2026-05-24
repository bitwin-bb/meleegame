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
local ui = (require :: any)(gameRoot.Client.UI)

local AnimationServiceClient = (require :: any)(gameRoot.Client.Services.AnimationServiceClient)
local AquariaBackupTranslator = (require :: any)(gameRoot.Shared.AquariaBackupTranslator)
local AudioServiceClient = (require :: any)(gameRoot.Client.Services.AudioServiceClient)
local BossServiceClient = (require :: any)(gameRoot.Shared.Features.npc.BossServiceClient)
local BreathServiceClient = (require :: any)(gameRoot.Client.Services.BreathServiceClient)
local BuildServiceClient = (require :: any)(gameRoot.Client.Services.BuildServiceClient)
local CameraServiceClient = (require :: any)(gameRoot.Client.Services.CameraServiceClient)
local ClientBinderSupport = (require :: any)(gameRoot.Client.Binders.ClientBinderSupport)
local CloudServiceClient = (require :: any)(gameRoot.Client.Features.parallax.CloudServiceClient)
local CraftingServiceClient = (require :: any)(gameRoot.Client.Services.CraftingServiceClient)
local GoreServiceClient = (require :: any)(gameRoot.Client.Services.GoreServiceClient)
local HpServiceClient = (require :: any)(gameRoot.Client.Services.HpServiceClient)
local InventoryServiceClient = (require :: any)(gameRoot.Client.Services.InventoryServiceClient)
local LiquidServiceClient = (require :: any)(gameRoot.Client.Services.LiquidServiceClient)
local LootServiceClient = (require :: any)(gameRoot.Client.Services.LootServiceClient)
local MagicServiceClient = (require :: any)(gameRoot.Client.Services.MagicServiceClient)
local ManaServiceClient = (require :: any)(gameRoot.Client.Services.ManaServiceClient)
local MeleeServiceClient = (require :: any)(gameRoot.Client.Services.MeleeServiceClient)
local NpcServiceClient = (require :: any)(gameRoot.Shared.Features.npc.NpcServiceClient)
local PadNavBinder = (require :: any)(gameRoot.Client.Binders.PadNavBinder)
local ParallaxServiceClient = (require :: any)(gameRoot.Client.Features.parallax.ParallaxServiceClient)
local PlatformServiceClient = (require :: any)(gameRoot.Client.Services.PlatformServiceClient)
local PlayerDataServiceClient = (require :: any)(gameRoot.Client.Services.PlayerDataServiceClient)
local PlayerServiceClient = (require :: any)(gameRoot.Client.Services.PlayerServiceClient)
local RagdollServiceClient = (require :: any)(gameRoot.Client.Services.RagdollServiceClient)
local TileBreakServiceClient = (require :: any)(gameRoot.Client.Features.tile.TileBreakServiceClient)
local VFXServiceClient = (require :: any)(gameRoot.Client.Services.VFXServiceClient)
local WeatherServiceClient = (require :: any)(gameRoot.Client.Services.WeatherServiceClient)
local WindFoliageServiceClient = (require :: any)(gameRoot.Client.Services.WindFoliageServiceClient)
local WorldAnimatorServiceClient = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldAnimatorServiceClient)
local WorldGenerationServiceClient = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldGenerationServiceClient)
local WorldSimulationServiceClient = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldSimulationServiceClient)

local CmdrBootstrapClient = (require :: any)(gameRoot.Client.Cmdr.CmdrBootstrapClient)
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
	CloudServiceClient:init()
	BuildServiceClient:init()
	TileBreakServiceClient:init()
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
