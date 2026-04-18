--!strict
--[[
	@class ClientMain
]]
local packageRoot = game:GetService("ReplicatedStorage"):WaitForChild("AquariaBackup")
local clientBootstrapModule = packageRoot:WaitForChild("game"):WaitForChild("Client"):WaitForChild("AquariaBackupClientBootstrap")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).bootstrapGame(packageRoot)
local gameRoot = packageRoot:WaitForChild("game")
local NevermoreSupport = require(gameRoot:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Core"):WaitForChild("NevermoreSupport"))
local ClientBinderSupport = require(gameRoot:WaitForChild("Client"):WaitForChild("Binders"):WaitForChild("ClientBinderSupport"))
local AquariaBackupTranslator = require(gameRoot:WaitForChild("Shared"):WaitForChild("AquariaBackupTranslator"))

NevermoreSupport.start({
	ClientBinderSupport,
	require("ScreenGuiService"),
	require("SnackbarServiceClient"),
	AquariaBackupTranslator,
})

task.spawn(require(clientBootstrapModule).start)
