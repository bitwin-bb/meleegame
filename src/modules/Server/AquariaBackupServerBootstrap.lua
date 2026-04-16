--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)
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

local EXTRA_ALLOWED_USER_IDS = {}
local MIN_CREATOR_GROUP_RANK = 254

local started = false

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
	if player:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == nil then
		player:SetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE, false)
	end
end

local function registerCmdrCommands(cmdr: any, sharedFolder: Instance, serverFolder: Instance)
	for _, child in sharedFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local serverModuleName = `{child.Name}Server`
			local serverModule = serverFolder:FindFirstChild(serverModuleName) or serverFolder:FindFirstChild(child.Name)
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
	local gameRoot = script:FindFirstAncestor("game")
	if gameRoot == nil then
		error("Nevermore game root was not found.")
	end

	local sharedRoot = gameRoot:FindFirstChild("Shared")
	if sharedRoot == nil then
		error("Shared folder was not found in the Nevermore game root.")
	end

	local sharedCmdrFolder = sharedRoot:FindFirstChild("Cmdr")
	if sharedCmdrFolder == nil then
		error("Cmdr folder was not found in the Nevermore shared root.")
	end

	local serverRoot = gameRoot:FindFirstChild("Server")
	if serverRoot == nil then
		error("Server folder was not found in the Nevermore game root.")
	end

	local serverCmdrRoot = serverRoot:FindFirstChild("Cmdr")
	if serverCmdrRoot == nil then
		error("Cmdr folder was not found in the Nevermore server root.")
	end

	local cmdrTypes = sharedCmdrFolder:FindFirstChild("Types")
	local sharedCmdrCommands = sharedCmdrFolder:FindFirstChild("Commands")
	local serverCmdrCommands = serverCmdrRoot:FindFirstChild("ServerCommands")
	if cmdrTypes == nil or sharedCmdrCommands == nil then
		error("Cmdr Types/Commands folders were not found in the Nevermore shared Cmdr root.")
	end
	if serverCmdrCommands == nil then
		error("Cmdr ServerCommands folder was not found in the Nevermore server Cmdr root.")
	end

	prepareStarterGuiForCmdr()

	local Cmdr = require("Cmdr")

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
	registerCmdrCommands(Cmdr, sharedCmdrCommands:Clone(), serverCmdrCommands:Clone())

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
		player:SetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE, nil)
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

local function start()
	if started then
		return
	end
	started = true

	initCmdr()

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
