--!strict
--[[
	@class ClientMain
]]
local packageRoot = game:GetService("ReplicatedStorage"):WaitForChild("AquariaBackup")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)
local gameRoot = packageRoot:WaitForChild("game")
local NevermoreSupport = require(gameRoot:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Core"):WaitForChild("NevermoreSupport"))
local ClientBinderSupport = require(gameRoot:WaitForChild("Client"):WaitForChild("Binders"):WaitForChild("ClientBinderSupport"))
local AquariaBackupTranslator = require(gameRoot:WaitForChild("Shared"):WaitForChild("AquariaBackupTranslator"))
local AquariaBackupServiceClient = require(gameRoot:WaitForChild("Client"):WaitForChild("AquariaBackupServiceClient"))
local CmdrBootstrapClient = require(gameRoot:WaitForChild("Client"):WaitForChild("Cmdr"):WaitForChild("CmdrBootstrapClient"))

local serviceBag = NevermoreSupport.start({
	ClientBinderSupport,
	require("ScreenGuiService"),
	require("SnackbarServiceClient"),
	AquariaBackupTranslator,
	AquariaBackupServiceClient,
})

CmdrBootstrapClient.start(serviceBag)
