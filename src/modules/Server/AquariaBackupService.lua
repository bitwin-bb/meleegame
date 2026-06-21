--[=[
	@class AquariaBackupService
]=]

local require = require(script.Parent.loader).load(script)

local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local ServerNetPackets = require("ServerNetPackets")

local AnimationServiceServer = require("AnimationServiceServer")
local AquariaBackupTranslator = require("AquariaBackupTranslator")
local AudioServiceServer = require("AudioServiceServer")
local BossServiceServer = require("BossServiceServer")
local BreathServiceServer = require("BreathServiceServer")
local BuildServiceServer = require("BuildServiceServer")
local CameraServiceServer = require("CameraServiceServer")
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
local ServerBinderSupport = require("ServerBinderSupport")
local CelestialCycleServer = require("CelestialCycleServer")
local VFXServiceServer = require("VFXServiceServer")
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
	PlayerServiceServer:init(WorldGenerationServiceServer:getWorld())
	WeatherServiceServer:init()
	CelestialCycleServer:init()
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
