--[=[
	@class AquariaBackupService
]=]

local require = require(script.Parent.loader).load(script)

local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local NetPacketsServer = require("NetPacketsServer")

local AnimationServiceServer = require("AnimationServiceServer")
local AquariaBackupTranslator = require("AquariaBackupTranslator")
local AudioServiceServer = require("AudioServiceServer")
local AutotileService = require("AutotileService")
local BinderSupportServer = require("BinderSupportServer")
local BossServiceServer = require("BossServiceServer")
local BreathServiceServer = require("BreathServiceServer")
local BuildServiceServer = require("BuildServiceServer")
local CameraServiceServer = require("CameraServiceServer")
local CelestialCycleServer = require("CelestialCycleServer")
local CraftingServiceServer = require("CraftingServiceServer")
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
local WeatherServiceServer = require("WeatherServiceServer")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")
local WorldSimulationServiceServer = require("WorldSimulationServiceServer")

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

	self._serviceBag:GetService(BinderSupportServer)
	self._serviceBag:GetService(AquariaBackupTranslator)
	self._serviceBag:GetService(CmdrService)

	CoreRuntime.GetServerRuntime():Init()
	NetPacketsServer:Init()

	PlatformServiceServer:Init()
	PlayerDataServiceServer:Init()
	WorldGenerationServiceServer:Init()
	HpServiceServer:Init()
	LiquidServiceServer:Init()
	BuildServiceServer:Init()
	TileWorldService:Init()
	TileReplicationService:Init()
	AutotileService:Init()
	TilePlacementService:Init()
	WorldSimulationServiceServer:Init()
	InventoryServiceServer:Init()
	CraftingServiceServer:Init()
	LootServiceServer:Init()
	ManaServiceServer:Init()
	MeleeServiceServer:Init()
	MagicServiceServer:Init()
	GoreServiceServer:Init()
	if isCameraServiceEnabled() then
		CameraServiceServer:Init()
	end
	PlayerServiceServer:Init(WorldGenerationServiceServer:GetWorld())
	WeatherServiceServer:Init()
	CelestialCycleServer:Init()
	NpcServiceServer:Init()
	BossServiceServer:Init()
	AnimationServiceServer:Init()
	AudioServiceServer:Init()
	VFXServiceServer:Init()
	BreathServiceServer:Init()
	RagdollServiceServer:Init()
end

function AquariaBackupService.Start(self: AquariaBackupService): ()
	assert((self :: any)._serviceBag, "Not initialized")
end

function AquariaBackupService.Destroy(self: AquariaBackupService): ()
	(self :: any)._serviceBag = nil
end

return AquariaBackupService
