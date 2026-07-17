local ServerScriptService = game:GetService("ServerScriptService")

local packageRoot = ServerScriptService:WaitForChild("AquariaBackup")
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = assert(loaderUtils.Parent, "Missing loader")
local require = require(loader).bootstrapGame(packageRoot)

local serviceBag = require("ServiceBag").new()

serviceBag:GetService(require("AquariaBackupService"))
serviceBag:Init()
serviceBag:Start()
