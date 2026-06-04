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
local ServerNetPackets = (require :: any)(gameRoot.Server.Net.Packets)

local AnimationServiceServer = loader("AnimationServiceServer")
local AquariaBackupTranslator = loader("AquariaBackupTranslator")
local AudioServiceServer = (require :: any)(gameRoot.Client.Features.audio.AudioServiceServer)
local BossServiceServer = loader("BossServiceServer")
local BreathServiceServer = loader("BreathServiceServer")
local BuildServiceServer = loader("BuildServiceServer")
local CameraServiceServer = loader("CameraServiceServer")
local CraftingServiceServer = loader("CraftingServiceServer")
local GoreServiceServer = loader("GoreServiceServer")
local HpServiceServer = loader("HpServiceServer")
local InventoryServiceServer = loader("InventoryServiceServer")
local LiquidServiceServer = loader("LiquidServiceServer")
local LootServiceServer = loader("LootServiceServer")
local MagicServiceServer = loader("MagicServiceServer")
local ManaServiceServer = loader("ManaServiceServer")
local MeleeServiceServer = loader("MeleeServiceServer")
local NpcServiceServer = loader("NpcServiceServer")
local PlatformServiceServer = loader("PlatformServiceServer")
local PlayerDataServiceServer = loader("PlayerDataServiceServer")
local PlayerServiceServer = loader("PlayerServiceServer")
local RagdollServiceServer = loader("RagdollServiceServer")
local ServerBinderSupport = loader("ServerBinderSupport")
local VFXServiceServer = loader("VFXServiceServer")
local WeatherServiceServer = loader("WeatherServiceServer")
local WorldGenerationServiceServer = loader("WorldGenerationServiceServer")
local WorldSimulationServiceServer = loader("WorldSimulationServiceServer")

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
	ServerNetPackets:init()

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
