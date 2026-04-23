--!strict

local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for AquariaBackupServerBootstrap.")
local packageRoot = gameRoot.Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlatformServiceServer)
local CameraServiceServer = require(script:FindFirstAncestor("game").Server.Services.CameraServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerServiceServer)
local AnimationServiceServer = require(script:FindFirstAncestor("game").Server.Services.AnimationServiceServer)
local AudioServiceServer = require(script:FindFirstAncestor("game").Server.Services.AudioServiceServer)
local VFXServiceServer = require(script:FindFirstAncestor("game").Server.Services.VFXServiceServer)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpServiceServer)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataServiceServer)
local InventoryServiceServer = require(script:FindFirstAncestor("game").Server.Services.InventoryServiceServer)
local CraftingServiceServer = require(script:FindFirstAncestor("game").Server.Services.CraftingServiceServer)
local LootServiceServer = require(script:FindFirstAncestor("game").Server.Services.LootServiceServer)
local ManaServiceServer = require(script:FindFirstAncestor("game").Server.Services.ManaServiceServer)
local MeleeServiceServer = require(script:FindFirstAncestor("game").Server.Services.MeleeServiceServer)
local MagicServiceServer = require(script:FindFirstAncestor("game").Server.Services.MagicServiceServer)
local GoreServiceServer = require(script:FindFirstAncestor("game").Server.Services.GoreServiceServer)
local RagdollServiceServer = require(script:FindFirstAncestor("game").Server.Services.RagdollServiceServer)
local WorldGenerationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldGenerationServiceServer)
local LiquidServiceServer = require(script:FindFirstAncestor("game").Server.Services.LiquidServiceServer)
local BuildServiceServer = require(script:FindFirstAncestor("game").Server.Services.BuildServiceServer)
local WorldSimulationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldSimulationServiceServer)
local BossServiceServer = require(script:FindFirstAncestor("game").Server.Services.BossServiceServer)
local NpcServiceServer = require(script:FindFirstAncestor("game").Server.Services.NpcServiceServer)
local WeatherServiceServer = require(script:FindFirstAncestor("game").Server.Services.WeatherServiceServer)
local BreathServiceServer = require(script:FindFirstAncestor("game").Server.Services.BreathServiceServer)

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
