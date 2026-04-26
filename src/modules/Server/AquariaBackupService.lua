--!strict
--[=[
	@class AquariaBackupService
]=]

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Configs = require(gameRoot.Shared.Modules.Core.Configs)
local CoreRuntime = require(gameRoot.Shared.Modules.Core.Runtime)

local AnimationServiceServer = require(gameRoot.Server.Services.AnimationServiceServer)
local AquariaBackupTranslator = require(gameRoot.Shared.AquariaBackupTranslator)
local AudioServiceServer = require(gameRoot.Server.Services.AudioServiceServer)
local BossServiceServer = require(gameRoot.Server.Services.BossServiceServer)
local BreathServiceServer = require(gameRoot.Server.Services.BreathServiceServer)
local BuildServiceServer = require(gameRoot.Server.Services.BuildServiceServer)
local CameraServiceServer = require(gameRoot.Server.Services.CameraServiceServer)
local CraftingServiceServer = require(gameRoot.Server.Services.CraftingServiceServer)
local GoreServiceServer = require(gameRoot.Server.Services.GoreServiceServer)
local HpServiceServer = require(gameRoot.Server.Services.HpServiceServer)
local InventoryServiceServer = require(gameRoot.Server.Services.InventoryServiceServer)
local LiquidServiceServer = require(gameRoot.Server.Services.LiquidServiceServer)
local LootServiceServer = require(gameRoot.Server.Services.LootServiceServer)
local MagicServiceServer = require(gameRoot.Server.Services.MagicServiceServer)
local ManaServiceServer = require(gameRoot.Server.Services.ManaServiceServer)
local MeleeServiceServer = require(gameRoot.Server.Services.MeleeServiceServer)
local NpcServiceServer = require(gameRoot.Server.Services.NpcServiceServer)
local PlatformServiceServer = require(gameRoot.Server.Services.PlatformServiceServer)
local PlayerDataServiceServer = require(gameRoot.Server.Services.PlayerDataServiceServer)
local PlayerServiceServer = require(gameRoot.Server.Services.PlayerServiceServer)
local RagdollServiceServer = require(gameRoot.Server.Services.RagdollServiceServer)
local ServerBinderSupport = require(gameRoot.Server.Binders.ServerBinderSupport)
local VFXServiceServer = require(gameRoot.Server.Services.VFXServiceServer)
local WeatherServiceServer = require(gameRoot.Server.Services.WeatherServiceServer)
local WorldGenerationServiceServer = require(gameRoot.Server.Services.WorldGenerationServiceServer)
local WorldSimulationServiceServer = require(gameRoot.Server.Services.WorldSimulationServiceServer)

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
