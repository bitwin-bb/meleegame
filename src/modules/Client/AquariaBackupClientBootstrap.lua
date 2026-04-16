--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ui = require(script:FindFirstAncestor("game").Client.UI)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)
local MatterDebugMenuClient = require(script:FindFirstAncestor("game").Client.Cmdr.MatterDebugMenuClient)
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
local cmdrClient = nil
local pendingCmdrRetry = false
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

local function findValidStarterGuiCmdr(): ScreenGui?
	local cmdrGui = CmdrUtils.keepSingleValidCmdrGui(StarterGui)

	while cmdrGui ~= nil and not CmdrUtils.isValidCmdrGui(cmdrGui) do
		task.wait()
		cmdrGui = CmdrUtils.keepSingleValidCmdrGui(StarterGui)
	end

	return cmdrGui
end

local function preparePlayerGuiForCmdr()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	return CmdrUtils.keepSingleValidCmdrGui(playerGui)
end

local function ensureCmdrClient()
	if cmdrClient ~= nil then
		return cmdrClient
	end

	local starterGuiCmdr = findValidStarterGuiCmdr()
	if starterGuiCmdr == nil then
		return nil
	end

	local existingGui = preparePlayerGuiForCmdr()

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	if existingGui == nil then
		starterGuiCmdr:Clone().Parent = playerGui
		existingGui = CmdrUtils.keepSingleValidCmdrGui(playerGui)
	end

	if existingGui == nil then
		return nil
	end

	cmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))
	cmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
	cmdrClient:SetEnabled(false)
	return cmdrClient
end

local function applyCmdrAccess()
	local cmdrEnabled = localPlayer:GetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE) == true
	if not cmdrEnabled then
		if cmdrClient ~= nil then
			cmdrClient:SetEnabled(false)
			cmdrClient:Hide()
		end
		return
	end

	local ensuredClient = ensureCmdrClient()
	if ensuredClient ~= nil then
		ensuredClient:SetEnabled(true)
	else
		if not pendingCmdrRetry then
			pendingCmdrRetry = true
			task.delay(0.1, function()
				pendingCmdrRetry = false
				applyCmdrAccess()
			end)
		end
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
	localPlayer:GetAttributeChangedSignal(CmdrUtils.CMDR_ENABLED_ATTRIBUTE):Connect(function()
		applyCmdrAccess()
	end)
	applyCmdrAccess()
	MatterDebugMenuClient:init()

	ui()
end

return {
	start = start,
}
