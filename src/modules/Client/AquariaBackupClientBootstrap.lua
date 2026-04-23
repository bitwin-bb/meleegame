--!strict

local Players = game:GetService("Players")

local ui = require(script:FindFirstAncestor("game").Client.UI)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local CameraServiceClient = require(script:FindFirstAncestor("game").Client.Services.CameraServiceClient)
local PlayerServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerServiceClient)
local AnimationServiceClient = require(script:FindFirstAncestor("game").Client.Services.AnimationServiceClient)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
local VFXServiceClient = require(script:FindFirstAncestor("game").Client.Services.VFXServiceClient)
local HpServiceClient = require(script:FindFirstAncestor("game").Client.Services.HpServiceClient)
local PlayerDataServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerDataServiceClient)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryServiceClient)
local CraftingServiceClient = require(script:FindFirstAncestor("game").Client.Services.CraftingServiceClient)
local LootServiceClient = require(script:FindFirstAncestor("game").Client.Services.LootServiceClient)
local ManaServiceClient = require(script:FindFirstAncestor("game").Client.Services.ManaServiceClient)
local MeleeServiceClient = require(script:FindFirstAncestor("game").Client.Services.MeleeServiceClient)
local MagicServiceClient = require(script:FindFirstAncestor("game").Client.Services.MagicServiceClient)
local GoreServiceClient = require(script:FindFirstAncestor("game").Client.Services.GoreServiceClient)
local RagdollServiceClient = require(script:FindFirstAncestor("game").Client.Services.RagdollServiceClient)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)
local LiquidServiceClient = require(script:FindFirstAncestor("game").Client.Services.LiquidServiceClient)
local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
local BreathServiceClient = require(script:FindFirstAncestor("game").Client.Services.BreathServiceClient)
local WorldSimulationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldSimulationServiceClient)
local WorldAnimatorServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldAnimatorServiceClient)
local BossServiceClient = require(script:FindFirstAncestor("game").Client.Services.BossServiceClient)
local NpcServiceClient = require(script:FindFirstAncestor("game").Client.Services.NpcServiceClient)
local ParallaxServiceClient = require(script:FindFirstAncestor("game").Client.Services.ParallaxServiceClient)
local WeatherServiceClient = require(script:FindFirstAncestor("game").Client.Services.WeatherServiceClient)
local WindFoliageServiceClient = require(script:FindFirstAncestor("game").Client.Services.WindFoliageServiceClient)

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
