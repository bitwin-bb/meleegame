--!strict

local Players = game:GetService("Players")

local ui = require(script:FindFirstAncestor("game").Client.UI)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformService.PlatformServiceClient)
local CameraServiceClient = require(script:FindFirstAncestor("game").Client.Services.CameraService.CameraServiceClient)
local PlayerServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerService.PlayerServiceClient)
local AnimationServiceClient = require(script:FindFirstAncestor("game").Client.Services.AnimationService.AnimationServiceClient)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioService.AudioServiceClient)
local VFXServiceClient = require(script:FindFirstAncestor("game").Client.Services.VFXService.VFXServiceClient)
local HpServiceClient = require(script:FindFirstAncestor("game").Client.Services.HpService.HpServiceClient)
local PlayerDataServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerDataService.PlayerDataServiceClient)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryService.InventoryServiceClient)
local CraftingServiceClient = require(script:FindFirstAncestor("game").Client.Services.CraftingService.CraftingServiceClient)
local LootServiceClient = require(script:FindFirstAncestor("game").Client.Services.LootService.LootServiceClient)
local ManaServiceClient = require(script:FindFirstAncestor("game").Client.Services.ManaService.ManaServiceClient)
local MeleeServiceClient = require(script:FindFirstAncestor("game").Client.Services.MeleeService.MeleeServiceClient)
local MagicServiceClient = require(script:FindFirstAncestor("game").Client.Services.MagicService.MagicServiceClient)
local GoreServiceClient = require(script:FindFirstAncestor("game").Client.Services.GoreService.GoreServiceClient)
local RagdollServiceClient = require(script:FindFirstAncestor("game").Client.Services.RagdollService.RagdollServiceClient)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)
local LiquidServiceClient = require(script:FindFirstAncestor("game").Client.Services.LiquidService.LiquidServiceClient)
local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildService.BuildServiceClient)
local BreathServiceClient = require(script:FindFirstAncestor("game").Client.Services.BreathService.BreathServiceClient)
local WorldSimulationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldSimulationService.WorldSimulationServiceClient)
local WorldAnimatorServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldAnimatorService.WorldAnimatorServiceClient)
local BossServiceClient = require(script:FindFirstAncestor("game").Client.Services.BossService.BossServiceClient)
local NpcServiceClient = require(script:FindFirstAncestor("game").Client.Services.NpcService.NpcServiceClient)
local ParallaxServiceClient = require(script:FindFirstAncestor("game").Client.Services.ParallaxService.ParallaxServiceClient)
local WeatherServiceClient = require(script:FindFirstAncestor("game").Client.Services.WeatherService.WeatherServiceClient)
local WindFoliageServiceClient = require(script:FindFirstAncestor("game").Client.Services.WindFoliageService.WindFoliageServiceClient)

local localPlayer = Players.LocalPlayer
local started = false
local ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS = 5
local ITEM_REGISTRY_STABLE_PASSES_REQUIRED = 2

local function countDictionaryEntries(dictionaryRaw: any): number
	if typeof(dictionaryRaw) ~= "table" then
		return 0
	end

	local count = 0
	for _ in dictionaryRaw do
		count += 1
	end
	return count
end

local function warmItemRegistry()
	local deadline = os.clock() + ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS
	local lastDefinitionCount = -1
	local stablePasses = 0

	while os.clock() < deadline do
		ItemRegistry.clearCache()

		local definitionCount = countDictionaryEntries(ItemRegistry.getDefinitionsById())
		if definitionCount > 0 then
			if definitionCount == lastDefinitionCount then
				stablePasses += 1
			else
				lastDefinitionCount = definitionCount
				stablePasses = 1
			end

			if stablePasses >= ITEM_REGISTRY_STABLE_PASSES_REQUIRED then
				return
			end
		else
			lastDefinitionCount = definitionCount
			stablePasses = 0
		end

		task.wait()
	end
end

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

local function start()
	if started then
		return
	end
	started = true

	local runtime = CoreRuntime.getClientRuntime()
	runtime:init()

	warmItemRegistry()

	PlatformServiceClient:init()
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
	PlayerServiceClient:init()
	WorldGenerationServiceClient:init()
	LiquidServiceClient:init()
	ParallaxServiceClient:init()
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
end

return {
	start = start,
}
