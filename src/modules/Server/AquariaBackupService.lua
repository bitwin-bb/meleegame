--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

--[=[
	@class AquariaBackupService
]=]

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Configs = (require :: any)("Configs")
local CoreRuntime = (require :: any)("Runtime")
local ServerNetPackets = (require :: any)("Packets")

local AnimationServiceServer = (require :: any)("AnimationServiceServer")
local AquariaBackupTranslator = (require :: any)("AquariaBackupTranslator")
local AudioServiceServer = (require :: any)(gameRoot.Client.Features.audio.AudioServiceServer)
local BossServiceServer = (require :: any)("BossServiceServer")
local BreathServiceServer = (require :: any)("BreathServiceServer")
local BuildServiceServer = (require :: any)("BuildServiceServer")
local CameraServiceServer = (require :: any)("CameraServiceServer")
local CraftingServiceServer = (require :: any)("CraftingServiceServer")
local GoreServiceServer = (require :: any)("GoreServiceServer")
local HpServiceServer = (require :: any)("HpServiceServer")
local InventoryServiceServer = (require :: any)("InventoryServiceServer")
local LiquidServiceServer = (require :: any)("LiquidServiceServer")
local LootServiceServer = (require :: any)("LootServiceServer")
local MagicServiceServer = (require :: any)("MagicServiceServer")
local ManaServiceServer = (require :: any)("ManaServiceServer")
local MeleeServiceServer = (require :: any)("MeleeServiceServer")
local NpcServiceServer = (require :: any)("NpcServiceServer")
local PlatformServiceServer = (require :: any)("PlatformServiceServer")
local PlayerDataServiceServer = (require :: any)("PlayerDataServiceServer")
local PlayerServiceServer = (require :: any)("PlayerServiceServer")
local RagdollServiceServer = (require :: any)("RagdollServiceServer")
local ServerBinderSupport = (require :: any)("ServerBinderSupport")
local VFXServiceServer = (require :: any)("VFXServiceServer")
local WeatherServiceServer = (require :: any)("WeatherServiceServer")
local WorldGenerationServiceServer = (require :: any)(
	gameRoot.Shared.Features.worldGeneration.WorldGenerationServiceServer
)
local WorldSimulationServiceServer = (require :: any)(
	gameRoot.Shared.Features.worldGeneration.WorldSimulationServiceServer
)

local CmdrService = require("CmdrService")

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
