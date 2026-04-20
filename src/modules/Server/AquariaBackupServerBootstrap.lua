--!strict

local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for AquariaBackupServerBootstrap.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlatformService.PlatformServiceServer)
local CameraServiceServer = require(script:FindFirstAncestor("game").Server.Services.CameraService.CameraServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local AnimationServiceServer = require(script:FindFirstAncestor("game").Server.Services.AnimationService.AnimationServiceServer)
local AudioServiceServer = require(script:FindFirstAncestor("game").Server.Services.AudioService.AudioServiceServer)
local VFXServiceServer = require(script:FindFirstAncestor("game").Server.Services.VFXService.VFXServiceServer)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpService.HpServiceServer)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataService.PlayerDataServiceServer)
local InventoryServiceServer = require(script:FindFirstAncestor("game").Server.Services.InventoryService.InventoryServiceServer)
local CraftingServiceServer = require(script:FindFirstAncestor("game").Server.Services.CraftingService.CraftingServiceServer)
local LootServiceServer = require(script:FindFirstAncestor("game").Server.Services.LootService.LootServiceServer)
local ManaServiceServer = require(script:FindFirstAncestor("game").Server.Services.ManaService.ManaServiceServer)
local MeleeServiceServer = require(script:FindFirstAncestor("game").Server.Services.MeleeService.MeleeServiceServer)
local MagicServiceServer = require(script:FindFirstAncestor("game").Server.Services.MagicService.MagicServiceServer)
local GoreServiceServer = require(script:FindFirstAncestor("game").Server.Services.GoreService.GoreServiceServer)
local RagdollServiceServer = require(script:FindFirstAncestor("game").Server.Services.RagdollService.RagdollServiceServer)
local WorldGenerationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldGenerationService.WorldGenerationServiceServer)
local LiquidServiceServer = require(script:FindFirstAncestor("game").Server.Services.LiquidService.LiquidServiceServer)
local BuildServiceServer = require(script:FindFirstAncestor("game").Server.Services.BuildService.BuildServiceServer)
local WorldSimulationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldSimulationService.WorldSimulationServiceServer)
local BossServiceServer = require(script:FindFirstAncestor("game").Server.Services.BossService.BossServiceServer)
local NpcServiceServer = require(script:FindFirstAncestor("game").Server.Services.NpcService.NpcServiceServer)
local WeatherServiceServer = require(script:FindFirstAncestor("game").Server.Services.WeatherService.WeatherServiceServer)
local BreathServiceServer = require(script:FindFirstAncestor("game").Server.Services.BreathService.BreathServiceServer)

local started = false

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

local function start()
	if started then
		return
	end
	started = true

	local runtime = CoreRuntime.getServerRuntime()
	runtime:init()

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

return {
	start = start,
}
