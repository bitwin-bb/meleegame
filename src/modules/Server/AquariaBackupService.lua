--!strict
--[=[
	@class AquariaBackupService
]=]

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Configs = (require :: any)(gameRoot.Shared.Core.Configs)
local CoreRuntime = (require :: any)(gameRoot.Shared.Core.Runtime)

local AnimationServiceServer = (require :: any)(gameRoot.Server.Services.AnimationServiceServer)
local AquariaBackupTranslator = (require :: any)(gameRoot.Shared.AquariaBackupTranslator)
local AudioServiceServer = (require :: any)(gameRoot.Client.Features.audio.AudioServiceServer)
local BossServiceServer = (require :: any)(gameRoot.Shared.Features.npc.BossServiceServer)
local BreathServiceServer = (require :: any)(gameRoot.Server.Services.BreathServiceServer)
local BuildServiceServer = (require :: any)(gameRoot.Server.Services.BuildServiceServer)
local CameraServiceServer = (require :: any)(gameRoot.Server.Services.CameraServiceServer)
local CraftingServiceServer = (require :: any)(gameRoot.Server.Services.CraftingServiceServer)
local GoreServiceServer = (require :: any)(gameRoot.Server.Services.GoreServiceServer)
local HpServiceServer = (require :: any)(gameRoot.Server.Services.HpServiceServer)
local InventoryServiceServer = (require :: any)(gameRoot.Server.Services.InventoryServiceServer)
local LiquidServiceServer = (require :: any)(gameRoot.Server.Services.LiquidServiceServer)
local LootServiceServer = (require :: any)(gameRoot.Server.Services.LootServiceServer)
local MagicServiceServer = (require :: any)(gameRoot.Server.Services.MagicServiceServer)
local ManaServiceServer = (require :: any)(gameRoot.Server.Services.ManaServiceServer)
local MeleeServiceServer = (require :: any)(gameRoot.Server.Services.MeleeServiceServer)
local NpcServiceServer = (require :: any)(gameRoot.Shared.Features.npc.NpcServiceServer)
local PlatformServiceServer = (require :: any)(gameRoot.Server.Services.PlatformServiceServer)
local PlayerDataServiceServer = (require :: any)(gameRoot.Server.Services.PlayerDataServiceServer)
local PlayerServiceServer = (require :: any)(gameRoot.Server.Services.PlayerServiceServer)
local RagdollServiceServer = (require :: any)(gameRoot.Server.Services.RagdollServiceServer)
local ServerBinderSupport = (require :: any)(gameRoot.Server.Binders.ServerBinderSupport)
local VFXServiceServer = (require :: any)(gameRoot.Server.Services.VFXServiceServer)
local WeatherServiceServer = (require :: any)(gameRoot.Server.Services.WeatherServiceServer)
local WorldGenerationServiceServer = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldGenerationServiceServer)
local WorldSimulationServiceServer = (require :: any)(gameRoot.Shared.Features.worldGeneration.WorldSimulationServiceServer)

local CmdrService = loader("CmdrService")

local AquariaBackupService = {}
AquariaBackupService.ServiceName = "AquariaBackupService"

export type AquariaBackupService = typeof(setmetatable(
	{} :: {
		_serviceBag: any,
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

function AquariaBackupService.Init(self: AquariaBackupService, serviceBag: any): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._serviceBag:GetService(ServerBinderSupport)
	self._serviceBag:GetService(AquariaBackupTranslator)
	self._serviceBag:GetService(CmdrService)

	CoreRuntime.getServerRuntime():init()

	PlatformServiceServer:init()
	PlayerDataServiceServer:init()
	WorldGenerationServiceServer:init()
	HpServiceServer:init()
	LiquidServiceServer:init()
	BuildServiceServer:init()
	WorldSimulationServiceServer:init()
	InventoryServiceServer:init()
	CraftingServiceServer:init()
	LootServiceServer:init()
	ManaServiceServer:init()
	MeleeServiceServer:init()
	MagicServiceServer:init()
	GoreServiceServer:init()
	if isCameraServiceEnabled() then
		CameraServiceServer:init()
	end
	PlayerServiceServer:init()
	WeatherServiceServer:init()
	NpcServiceServer:init()
	BossServiceServer:init()
	AnimationServiceServer:init()
	AudioServiceServer:init()
	VFXServiceServer:init()
	BreathServiceServer:init()
	RagdollServiceServer:init()
end

function AquariaBackupService.Start(self: AquariaBackupService): ()
	assert((self :: any)._serviceBag, "Not initialized")
end

function AquariaBackupService.Destroy(self: AquariaBackupService): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupService
