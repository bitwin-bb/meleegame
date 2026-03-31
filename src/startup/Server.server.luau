local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CmdrUtils = require(ReplicatedStorage.Shared.Cmdr.CmdrUtils)
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
local WorldGenerationServiceServer =
	require(ServerScriptService.Services.WorldGenerationService.WorldGenerationServiceServer)
local LiquidServiceServer = require(ServerScriptService.Services.LiquidService.LiquidServiceServer)
local BuildServiceServer = require(ServerScriptService.Services.BuildService.BuildServiceServer)
local WorldSimulationServiceServer =
	require(ServerScriptService.Services.WorldSimulationService.WorldSimulationServiceServer)
local BossServiceServer = require(ServerScriptService.Services.BossService.BossServiceServer)
local NpcServiceServer = require(ServerScriptService.Services.NpcService.NpcServiceServer)
local WeatherServiceServer = require(ServerScriptService.Services.WeatherService.WeatherServiceServer)
local BreathServiceServer = require(ServerScriptService.Services.BreathService.BreathServiceServer)

local EXTRA_ALLOWED_USER_IDS = {}
local MIN_CREATOR_GROUP_RANK = 254

local function isExtraAllowedUserId(userId: number): boolean
	return EXTRA_ALLOWED_USER_IDS[userId] == true
end

local function isCreatorAuthorized(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function(): number
			return player:GetRankInGroupAsync(game.CreatorId)
		end)
		return ok and rank >= MIN_CREATOR_GROUP_RANK
	end

	return false
end

local function isCmdrAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	if isExtraAllowedUserId(player.UserId) then
		return true
	end

	return isCreatorAuthorized(player)
end

local function prepareStarterGuiForCmdr()
	local existingGui = CmdrUtils.keepSingleValidCmdrGui(StarterGui)
	if existingGui ~= nil then
		return
	end
end

local function applyCmdrPlayerAttributes(player: Player)
	player:SetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE, isCmdrAuthorized(player))

	if player:GetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, false)
	end
	if player:GetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, CmdrUtils.DEFAULT_FLY_SPEED)
	end
	if player:GetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE, false)
	end
end

local function registerCmdrCommands(cmdr: any, sharedFolder: Instance, serverFolder: Instance)
	for _, child in sharedFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local serverModule = serverFolder:FindFirstChild(child.Name .. "Server")
			if serverModule == nil or not serverModule:IsA("ModuleScript") then
				error(`Missing Cmdr server module for command "{child.Name}".`)
			end

			cmdr:RegisterCommand(child, serverModule)
		elseif child:IsA("Folder") then
			local matchingServerFolder = serverFolder:FindFirstChild(child.Name)
			if matchingServerFolder == nil or not matchingServerFolder:IsA("Folder") then
				error(`Missing Cmdr server command folder "{child.Name}".`)
			end

			registerCmdrCommands(cmdr, child, matchingServerFolder)
		end
	end
end

local function initCmdr()
	local sharedRoot = ReplicatedStorage:FindFirstChild("Shared")
	if sharedRoot == nil then
		error("Shared folder was not found in ReplicatedStorage.")
	end

	local sharedCmdrFolder = sharedRoot:FindFirstChild("Cmdr")
	if sharedCmdrFolder == nil then
		error("Cmdr folder was not found in ReplicatedStorage.Shared.")
	end

	local serverCmdrFolder = ServerScriptService:FindFirstChild("Cmdr")
	if serverCmdrFolder == nil then
		error("Cmdr folder was not found in ServerScriptService.")
	end

	local cmdrTypes = sharedCmdrFolder:FindFirstChild("Types")
	local sharedCmdrCommands = sharedCmdrFolder:FindFirstChild("Commands")
	local serverCmdrCommands = serverCmdrFolder:FindFirstChild("Commands")
	if cmdrTypes == nil or sharedCmdrCommands == nil then
		error("Cmdr Types/Commands folders were not found in ReplicatedStorage.Shared.Cmdr.")
	end
	if serverCmdrCommands == nil then
		error("Cmdr Commands folder was not found in ServerScriptService.Cmdr.")
	end

	prepareStarterGuiForCmdr()

	local Cmdr = require(ReplicatedStorage.Packages.Cmdr)

	Cmdr:RegisterHook("BeforeRun", function(context)
		local executor = context.Executor
		if typeof(executor) ~= "Instance" or not executor:IsA("Player") then
			return "Only players can run developer commands."
		end

		if not isCmdrAuthorized(executor) then
			return "You do not have permission to use developer commands."
		end

		return nil
	end)

	Cmdr:RegisterDefaultCommands(function(command)
		return command.Name == "help"
	end)
	Cmdr:RegisterTypesIn(cmdrTypes:Clone())
	registerCmdrCommands(Cmdr, sharedCmdrCommands:Clone(), serverCmdrCommands)

	for _, player in Players:GetPlayers() do
		applyCmdrPlayerAttributes(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		applyCmdrPlayerAttributes(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		player:SetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE, nil)
		player:SetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE, nil)
		player:SetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE, nil)
		player:SetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE, nil)
	end)
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

initCmdr()

local runtime = CoreRuntime.getServerRuntime()
runtime:init()

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
