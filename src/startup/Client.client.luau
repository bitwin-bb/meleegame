local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ui = require(ReplicatedStorage.UI)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local CmdrUtils = require(ReplicatedStorage.Shared.Cmdr.CmdrUtils)
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

local localPlayer = Players.LocalPlayer
local cmdrClient = nil
local pendingCmdrRetry = false
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

	warn(("[ClientStartup] Timed out warming the item registry after %.1fs; continuing with %d definitions."):format(
		ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS,
		math.max(0, lastDefinitionCount)
	))
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

local runtime = CoreRuntime.getClientRuntime()
runtime:init()

warmItemRegistry()

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
localPlayer:GetAttributeChangedSignal(CmdrUtils.CMDR_ENABLED_ATTRIBUTE):Connect(function()
	applyCmdrAccess()
end)
applyCmdrAccess()

ui()
