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
local ui = (require :: any)(gameRoot.Client.UI)

local AnimationServiceClient = (require :: any)(gameRoot.Shared.Features.animation.AnimationServiceClient)
local AquariaBackupTranslator = (require :: any)(gameRoot.Shared.AquariaBackupTranslator)
local AudioServiceClient = (require :: any)(gameRoot.Client.Features.audio.AudioServiceClient)
local BossServiceClient = (require :: any)(gameRoot.Shared.Features.npc.BossServiceClient)
local BreathServiceClient = (require :: any)(gameRoot.Shared.Features.breath.BreathServiceClient)
local BuildServiceClient = (require :: any)(gameRoot.Shared.Features.world.BuildServiceClient)
local CameraServiceClient = (require :: any)(gameRoot.Shared.Features.camera.CameraServiceClient)
local ClientBinderSupport = (require :: any)(gameRoot.Client.Binders.ClientBinderSupport)
local CloudServiceClient = (require :: any)(gameRoot.Client.Features.parallax.CloudServiceClient)
local CraftingServiceClient = (require :: any)(gameRoot.Shared.Features.crafting.CraftingServiceClient)
local GoreServiceClient = (require :: any)(gameRoot.Shared.Features.gore.GoreServiceClient)
local HpServiceClient = (require :: any)(gameRoot.Shared.Features.health.HpServiceClient)
local InventoryServiceClient = (require :: any)(gameRoot.Shared.Features.inventory.InventoryServiceClient)
local LiquidServiceClient = (require :: any)(gameRoot.Shared.Features.world.LiquidServiceClient)
local LootServiceClient = (require :: any)(gameRoot.Shared.Features.loot.LootServiceClient)
local MagicServiceClient = (require :: any)(gameRoot.Shared.Features.combat.MagicServiceClient)
local ManaServiceClient = (require :: any)(gameRoot.Shared.Features.mana.ManaServiceClient)
local MeleeServiceClient = (require :: any)(gameRoot.Shared.Features.combat.MeleeServiceClient)
local NpcServiceClient = (require :: any)(gameRoot.Shared.Features.npc.NpcServiceClient)
local PadNavBinder = (require :: any)(gameRoot.Client.Features.pad.binders.PadNavBinder)
local ParallaxServiceClient = (require :: any)(gameRoot.Client.Features.parallax.ParallaxServiceClient)
local PlatformServiceClient = (require :: any)(gameRoot.Shared.Features.platform.PlatformServiceClient)
local PlayerDataServiceClient = (require :: any)(gameRoot.Shared.Features.playerData.PlayerDataServiceClient)
local PlayerServiceClient = (require :: any)(gameRoot.Shared.Features.movement.PlayerServiceClient)
local RagdollServiceClient = (require :: any)(gameRoot.Shared.Features.ragdoll.RagdollServiceClient)
local TileBreakServiceClient = (require :: any)(gameRoot.Client.Features.tile.TileBreakServiceClient)
local VFXServiceClient = (require :: any)(gameRoot.Shared.Features.vfx.VFXServiceClient)
local WeatherServiceClient = (require :: any)(gameRoot.Shared.Features.world.WeatherServiceClient)
local WindFoliageServiceClient = (require :: any)(gameRoot.Shared.Features.world.WindFoliageServiceClient)
local WorldAnimatorServiceClient = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldAnimatorServiceClient)
local WorldGenerationServiceClient = (require :: any)(
	gameRoot.Shared.Features.worldGeneration.WorldGenerationServiceClient
)
local WorldSimulationServiceClient = (require :: any)(
	gameRoot.Shared.Features.worldGeneration.WorldSimulationServiceClient
)

local CmdrBootstrapClient = (require :: any)(gameRoot.Client.Features.commander.CmdrBootstrapClient)
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
