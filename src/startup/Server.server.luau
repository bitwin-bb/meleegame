local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local CameraServiceServer = require(ServerScriptService.Services.CameraService.CameraServiceServer)
local PlayerServiceServer = require(ServerScriptService.Services.PlayerService.PlayerServiceServer)
local AnimationServiceServer = require(ServerScriptService.Services.AnimationService.AnimationServiceServer)
local AudioServiceServer = require(ServerScriptService.Services.AudioService.AudioServiceServer)
local VFXServiceServer = require(ServerScriptService.Services.VFXService.VFXServiceServer)
local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)
local PlayerDataServiceServer = require(ServerScriptService.Services.PlayerDataService.PlayerDataServiceServer)
local InventoryServiceServer = require(ServerScriptService.Services.InventoryService.InventoryServiceServer)
local CraftingServiceServer = require(ServerScriptService.Services.CraftingService.CraftingServiceServer)
local LootServiceServer = require(ServerScriptService.Services.LootService.LootServiceServer)
local ManaServiceServer = require(ServerScriptService.Services.ManaService.ManaServiceServer)
local MeleeServiceServer = require(ServerScriptService.Services.MeleeService.MeleeServiceServer)
local MagicServiceServer = require(ServerScriptService.Services.MagicService.MagicServiceServer)
local GoreServiceServer = require(ServerScriptService.Services.GoreService.GoreServiceServer)
local RagdollServiceServer = require(ServerScriptService.Services.RagdollService.RagdollServiceServer)
local WorldGenerationServiceServer = require(ServerScriptService.Services.WorldGenerationService.WorldGenerationServiceServer)
local BuildServiceServer = require(ServerScriptService.Services.BuildService.BuildServiceServer)
local WorldSimulationServiceServer = require(ServerScriptService.Services.WorldSimulationService.WorldSimulationServiceServer)
local NpcServiceServer = require(ServerScriptService.Services.NpcService.NpcServiceServer)
local WeatherServiceServer = require(ServerScriptService.Services.WeatherService.WeatherServiceServer)

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

local runtime = CoreRuntime.getServerRuntime()
runtime:init()

PlayerDataServiceServer:init()
WorldGenerationServiceServer:init()
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
AnimationServiceServer:init()
AudioServiceServer:init()
VFXServiceServer:init()
HpServiceServer:init()
RagdollServiceServer:init()

