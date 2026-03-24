local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ui = require(ReplicatedStorage.UI)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local CameraServiceClient = require(ReplicatedStorage.Shared.Services.CameraService.CameraServiceClient)
local PlayerServiceClient = require(ReplicatedStorage.Shared.Services.PlayerService.PlayerServiceClient)
local AnimationServiceClient = require(ReplicatedStorage.Shared.Services.AnimationService.AnimationServiceClient)
local AudioServiceClient = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceClient)
local VFXServiceClient = require(ReplicatedStorage.Shared.Services.VFXService.VFXServiceClient)
local HpServiceClient = require(ReplicatedStorage.Shared.Services.HpService.HpServiceClient)
local PlayerDataServiceClient = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceClient)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)
local CraftingServiceClient = require(ReplicatedStorage.Shared.Services.CraftingService.CraftingServiceClient)
local LootServiceClient = require(ReplicatedStorage.Shared.Services.LootService.LootServiceClient)
local ManaServiceClient = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceClient)
local MeleeServiceClient = require(ReplicatedStorage.Shared.Services.MeleeService.MeleeServiceClient)
local MagicServiceClient = require(ReplicatedStorage.Shared.Services.MagicService.MagicServiceClient)
local GoreServiceClient = require(ReplicatedStorage.Shared.Services.GoreService.GoreServiceClient)
local RagdollServiceClient = require(ReplicatedStorage.Shared.Services.RagdollService.RagdollServiceClient)
local WorldGenerationServiceClient =
	require(ReplicatedStorage.Shared.Services.WorldGenerationService.WorldGenerationServiceClient)
local LiquidServiceClient = require(ReplicatedStorage.Shared.Services.LiquidService.LiquidServiceClient)
local BuildServiceClient = require(ReplicatedStorage.Shared.Services.BuildService.BuildServiceClient)
local BreathServiceClient = require(ReplicatedStorage.Shared.Services.BreathService.BreathServiceClient)
local WorldSimulationServiceClient =
	require(ReplicatedStorage.Shared.Services.WorldSimulationService.WorldSimulationServiceClient)
local WorldAnimatorServiceClient =
	require(ReplicatedStorage.Shared.Services.WorldAnimatorService.WorldAnimatorServiceClient)
local BossServiceClient = require(ReplicatedStorage.Shared.Services.BossService.BossServiceClient)
local NpcServiceClient = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceClient)
local ParallaxServiceClient = require(ReplicatedStorage.Shared.Services.ParallaxService.ParallaxServiceClient)
local WeatherServiceClient = require(ReplicatedStorage.Shared.Services.WeatherService.WeatherServiceClient)
local WindFoliageServiceClient = require(ReplicatedStorage.Shared.Services.WindFoliageService.WindFoliageServiceClient)
local DevPromptServiceClient = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceClient)

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

local runtime = CoreRuntime.getClientRuntime()
runtime:init()

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
DevPromptServiceClient:init()
PlayerServiceClient:init()
WorldGenerationServiceClient:init()
ParallaxServiceClient:init()
LiquidServiceClient:init()
BuildServiceClient:init()
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

ui()
